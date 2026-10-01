#!/usr/bin/env bash
# ============================================================================
#  SideWinder X6 — Linux Tam Kurulum Scripti
#
#  Desteklenen sistemler:
#    - Arch tabanlı (CachyOS, Manjaro, EndeavourOS...): pacman
#    - Debian/Ubuntu tabanlı (Ubuntu, Mint, Pop!_OS...): apt
#
#  Kurulumun tamamini tek komutta yapar:
#    - sidewinderd (GitHub: tolga9009/sidewinderd) derler ve kurar
#    - systemd servislerini ve yapilandirmayi hazirlar
#    - keyd + x6-profd ile profil bazli Windows-tusu kilidi kurar
#    - x6feat aracini derler (macro-pad modu kontrolu)
#    - macro-pad modunu acar
#
#  Kullanim:  sudo ./install.sh
# ============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "HATA: root ile calistirin -> sudo ./install.sh"
    exit 1
fi

USER_NAME="${SUDO_USER:-$USER}"
echo "==> Kurulum kullanicisi: $USER_NAME"

# ---------------------------------------------------------------- 1. Bagimliliklar
echo "==> Bagimliliklar kuruluyor..."
if command -v pacman &>/dev/null; then
    pacman -S --needed --noconfirm base-devel cmake git libconfig tinyxml2 keyd
elif command -v apt-get &>/dev/null; then
    apt-get update
    apt-get install -y build-essential cmake git libconfig-dev libtinyxml2-dev libudev-dev
    # keyd Ubuntu/Debian depolarinda yok -> kaynaktan derle
    if ! command -v keyd &>/dev/null; then
        echo "==> keyd kaynaktan derleniyor (Ubuntu/Debian)..."
        KTMP=$(mktemp -d)
        git clone --depth 1 https://github.com/rvaiya/keyd "$KTMP/keyd"
        make -C "$KTMP/keyd"
        make -C "$KTMP/keyd" install
        rm -rf "$KTMP"
    fi
else
    echo "HATA: ne pacman ne apt-get bulundu. Elle kurulum icin README'ye bakin."
    exit 1
fi

# ---------------------------------------------------------------- 2. sidewinderd
echo "==> sidewinderd derleniyor..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git clone --depth 1 https://github.com/tolga9009/sidewinderd "$TMP/sidewinderd"
cmake -S "$TMP/sidewinderd" -B "$TMP/build" \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -DCMAKE_INSTALL_PREFIX=/usr
cmake --build "$TMP/build"
cmake --install "$TMP/build"

# systemd servisi (cmake kurmadiysa diye garantiye alalim)
cat > /etc/systemd/system/sidewinderd.service <<'SVCEOF'
[Unit]
Description=Support for Microsoft SideWinder X4 / X6 and Logitech G105 / G710+

[Service]
ExecStart=/usr/bin/sidewinderd
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
SVCEOF

# yapilandirma: root yerine gercek kullanici + kalici profil dizini
cat > /etc/sidewinderd.conf <<CFGEOF
user = "$USER_NAME";
capture_delays = true;
pid-file = "/var/run/sidewinderd.pid";
workdir = "/var/lib/sidewinderd";
CFGEOF

mkdir -p /var/lib/sidewinderd
chown "$USER_NAME:$USER_NAME" /var/lib/sidewinderd
usermod -aG input "$USER_NAME"
systemctl daemon-reload
systemctl enable --now sidewinderd

# ---------------------------------------------------------------- 3. keyd
echo "==> keyd etkinlestiriliyor..."
systemctl enable --now keyd

# ---------------------------------------------------------------- 4. x6feat (C araci)
echo "==> x6feat derleniyor..."
cat > "$TMP/x6feat.c" <<'CEOF'
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/hidraw.h>

int main(int argc, char **argv) {
    const char *node = argc > 1 ? argv[1] : "/dev/hidraw1";
    int ledon = argc > 2 && strstr(argv[2], "ledon");
    int force = argc > 2 && strstr(argv[2], "on") && !ledon;

    fprintf(stderr, "HIDIOCGFEATURE(2)=0x%lx  HIDIOCSFEATURE(2)=0x%lx\n",
            (unsigned long)HIDIOCGFEATURE(2),
            (unsigned long)HIDIOCSFEATURE(2));

    int fd = open(node, O_RDWR | O_NONBLOCK);
    if (fd < 0) { perror("open"); return 1; }

    unsigned char buf[2] = {7, 0};
    if (ioctl(fd, HIDIOCGFEATURE(2), buf) < 0) { perror("GFEATURE"); return 1; }
    printf("rapor 07: %02x %02x -> macro-pad %s\n",
           buf[0], buf[1], (buf[1] & 1) ? "ACIK" : "KAPALI");

    if (ledon) {
        buf[1] |= 0x60;   /* record LED bitleri */
        if (ioctl(fd, HIDIOCSFEATURE(2), buf) < 0) { perror("SFEATURE"); return 1; }
        printf("record LED yakildi - klavyeye bak!\n");
    } else if (force && !(buf[1] & 1)) {
        buf[1] |= 1;
        if (ioctl(fd, HIDIOCSFEATURE(2), buf) < 0) { perror("SFEATURE"); return 1; }
        printf("macro-pad ACILDI\n");
    }
    close(fd);
    return 0;
}
CEOF
gcc -O2 "$TMP/x6feat.c" -o /usr/local/bin/x6feat

# ---------------------------------------------------------------- 5. x6-profd (profil izleyici)
echo "==> x6-profd kuruluyor..."
cat > /usr/local/bin/x6-profd.py <<'PYEOF'
#!/usr/bin/env python3
# x6-profd.py - X6 profil izleyici: profil 2/3'te Windows tuslarini kilitler
import os, fcntl, selectors, subprocess, time

LOCK_PROFILES = {2, 3}          # bu profillerde Windows kilitli
CONF = "/etc/keyd/zz-x6-winlock.conf"
CONF_BODY = """[ids]
045e:074b

[main]
leftmeta = noop
rightmeta = noop
"""

def ioc(d, nr, ln):
    return (d << 30) | (0x48 << 8) | nr | (ln << 16)

def find_node():
    base = "/sys/class/hidraw"
    for n in sorted(os.listdir(base)):
        try:
            u = open(os.path.join(base, n, "device", "uevent")).read().upper()
        except OSError:
            continue
        if "045E" in u and "074B" in u:
            p = "/dev/" + n
            try:
                f = os.open(p, os.O_RDWR | os.O_NONBLOCK)
            except OSError:
                continue
            b = bytearray(2); b[0] = 7
            try:
                fcntl.ioctl(f, ioc(3, 7, 2), b)      # 0xC0024807
            except OSError:
                os.close(f); continue
            os.close(f)
            return p
    return None

def read_profile(fd):
    b = bytearray(2); b[0] = 7
    fcntl.ioctl(fd, ioc(3, 7, 2), b)
    if b[1] & 0x08: return 2
    if b[1] & 0x10: return 3
    return 1

def apply(prof):
    lock = prof in LOCK_PROFILES
    exists = os.path.exists(CONF)
    if lock and not exists:
        open(CONF, "w").write(CONF_BODY)
        subprocess.run(["keyd", "reload"], capture_output=True)
        print(f"profil {prof}: Windows tuslari KILITLI", flush=True)
    elif not lock and exists:
        os.remove(CONF)
        subprocess.run(["keyd", "reload"], capture_output=True)
        print(f"profil {prof}: Windows tuslari serbest", flush=True)

def main():
    while True:
        node = find_node()
        if not node:
            print("X6 bulunamadi, 3 sn...", flush=True)
            time.sleep(3); continue
        print("izleniyor:", node, flush=True)
        fd = os.open(node, os.O_RDWR | os.O_NONBLOCK)
        try:
            apply(read_profile(fd))
        except OSError:
            pass
        sel = selectors.DefaultSelector()
        sel.register(fd, selectors.EVENT_READ)
        try:
            while True:
                for key, _ in sel.select():
                    data = os.read(key.fileobj, 64)
                    if len(data) >= 8 and data[0] == 1 and data[6] == 0x14:
                        time.sleep(0.15)   # LED bitsinin guncellenmesini bekle
                        try:
                            apply(read_profile(fd))
                        except OSError:
                            pass
        except OSError:
            os.close(fd); time.sleep(2)

main()
PYEOF
chmod +x /usr/local/bin/x6-profd.py

cat > /etc/systemd/system/x6-profd.service <<SVCEOF
[Unit]
Description=X6 profil izleyici (profil bazli Windows kilidi)
After=keyd.service

[Service]
ExecStart=/usr/local/bin/x6-profd.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
SVCEOF
systemctl daemon-reload
systemctl enable --now x6-profd

# ---------------------------------------------------------------- 6. Macro-pad modunu ac
echo "==> Macro-pad modu etkinlestiriliyor..."
python3 - <<'PYEOF'
import os, fcntl

def ioc(d, n, l):
    return (d << 30) | (0x48 << 8) | n | (l << 16)

base = "/sys/class/hidraw"
for n in sorted(os.listdir(base)):
    try:
        u = open(os.path.join(base, n, "device", "uevent")).read().upper()
    except OSError:
        continue
    if "045E" in u and "074B" in u:
        try:
            f = os.open("/dev/" + n, os.O_RDWR)
        except OSError:
            continue
        b = bytearray(2)
        b[0] = 7
        try:
            fcntl.ioctl(f, ioc(3, 7, 2), b)          # 0xC0024807
        except OSError:
            os.close(f)
            continue
        if not (b[1] & 1):
            b[1] |= 1
            fcntl.ioctl(f, ioc(3, 6, 2), bytes(b))   # 0xC0024806
            print("    Macro-pad modu acildi.")
        else:
            print("    Macro-pad modu zaten acik.")
        os.close(f)
        break
PYEOF

echo
echo "========================================================"
echo " KURULUM TAMAM"
echo "========================================================"
echo " Servisler:  sidewinderd, keyd, x6-profd"
echo " Araclar:    sudo x6feat /dev/hidrawX        (rapor 07 durumu)"
echo "             sudo x6feat /dev/hidrawX on     (macro-pad ac)"
echo
echo " Makro kaydi: makro tusu (karede top) -> S tusuna bas -> dizi -> makro tusu"
echo " Makro silme: makro tusu -> S tusuna bas -> HICBIR SEY basmadan makro tusu"
echo " Profiller:   1/2/3 tuslari; profil 2-3'te Windows kilidi"
echo " NOT: Kilit grubu icin OTURUMU KAPATIP ACIN (input grubu)."
echo "========================================================"
