#!/usr/bin/env bash
# ============================================================================
#  SideWinder X6 — Linux Tam Kurulum Scripti
#
#  Desteklenen sistemler:
#    - Arch tabanlı (CachyOS, Manjaro, EndeavourOS...): pacman
#    - Debian/Ubuntu tabanlı (Ubuntu, Mint, Pop!_OS...): apt
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
    pacman -S --needed --noconfirm base-devel cmake git libconfig tinyxml2 keyd python-evdev brightnessctl
elif command -v apt-get &>/dev/null; then
    apt-get update
    apt-get install -y build-essential cmake git libconfig-dev libtinyxml2-dev libudev-dev python3-evdev brightnessctl
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

# Yamalar:
#  a) CMake >= 4 uyumlulugu (CMAKE_MINIMUM_REQUIRED 2.8.8 reddediliyor)
#  b) Media center (0x10) mod-degistirme islevini kapat -> F13 kisayoluna donusur
#     (mod durumu x6feat araciyla yonetilir; makro kaydi bu moddan bagimsizdir)
sed -i 's/keyData->index == SW_KEY_GAMECENTER/false \/\* media center: ozel islev *\//' \
    "$TMP/sidewinderd/src/vendor/microsoft/sidewinder.cpp"

cmake -S "$TMP/sidewinderd" -B "$TMP/build" \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -DCMAKE_INSTALL_PREFIX=/usr
cmake --build "$TMP/build"
cmake --install "$TMP/build"

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
    int ledon  = argc > 2 && strstr(argv[2], "ledon");
    int off    = argc > 2 && strstr(argv[2], "off");
    int force  = argc > 2 && strstr(argv[2], "on") && !off;

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
    } else if (off) {
        buf[1] &= ~1;
        if (ioctl(fd, HIDIOCSFEATURE(2), buf) < 0) { perror("SFEATURE"); return 1; }
        printf("macro-pad KAPATILDI (numpad rakam moduna doner)\n");
    } else if (force && !(buf[1] & 1)) {
        buf[1] |= 1;
        if (ioctl(fd, HIDIOCSFEATURE(2), buf) < 0) { perror("SFEATURE"); return 1; }
        printf("macro-pad ACILDI (numpad makro modunda)\n");
    }
    close(fd);
    return 0;
}
CEOF
gcc -O2 "$TMP/x6feat.c" -o /usr/local/bin/x6feat

# ---------------------------------------------------------------- 5. x6-profd (profil izleyici + F13)
echo "==> x6-profd kuruluyor..."
cat > /usr/local/bin/x6-profd.py <<'PYEOF'
#!/usr/bin/env python3
# x6-profd.py - X6 profil izleyici + media center (0x10) ozellestirilebilir islev
import os, fcntl, selectors, subprocess, time

LOCK_PROFILES = {2, 3}          # bu profillerde Windows kilidi

# Media center (0x10) islevi: "brightness" | "mute" | "lock" | "f13" | "none"
#   brightness : kisa bas = parlaklik kis / uzun bas = ac   (brightnessctl)
#   mute       : sesi ac/kapat (toggle)                     (pactl)
#   lock       : ekrani kilitle                             (loginctl)
#   f13        : sanal F13 tusuna bas (sistem kisayollarina baglanir)
#   none       : islev yok
MEDIA_ACTION = "brightness"
LONG_PRESS_SEC = 0.5
BRIGHTNESS_STEP = "5%"

CONF = "/etc/keyd/zz-x6-winlock.conf"
CONF_BODY = """[ids]
045e:074b

[main]
leftmeta = noop
rightmeta = noop
"""

_ui = None
def fire_f13():
    global _ui
    if _ui is None:
        from evdev import UInput, ecodes as ec
        _ui = UInput({ec.EV_KEY: [ec.KEY_F13]}, name="x6-media",
                     vendor=0x045e, product=0x074b)
    _ui.write(1, 0x1AF, 1)   # EV_KEY, KEY_F13, press
    _ui.syn()
    _ui.write(1, 0x1AF, 0)
    _ui.syn()

def media_action(long_press):
    if MEDIA_ACTION == "brightness":
        subprocess.run(["brightnessctl", "set",
                        ("+" if long_press else "-") + BRIGHTNESS_STEP],
                       capture_output=True)
        print("parlaklik:", "+" if long_press else "-", BRIGHTNESS_STEP, flush=True)
    elif MEDIA_ACTION == "mute":
        subprocess.run(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"],
                       capture_output=True)
        print("ses: ac/kapat", flush=True)
    elif MEDIA_ACTION == "lock":
        subprocess.run(["loginctl", "lock-session"], capture_output=True)
        print("ekran kilitlendi", flush=True)
    elif MEDIA_ACTION == "f13":
        fire_f13()

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
        subprocess.run(["systemctl", "restart", "keyd"], capture_output=True)
        print(f"profil {prof}: Windows tuslari KILITLI", flush=True)
    elif not lock and exists:
        os.remove(CONF)
        subprocess.run(["systemctl", "restart", "keyd"], capture_output=True)
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
        press_t = None
        try:
            while True:
                for key, _ in sel.select():
                    data = os.read(key.fileobj, 64)
                    if len(data) >= 8 and data[0] == 1:
                        code = data[6]
                        if code == 0x14:              # profil tuşu
                            time.sleep(0.15)
                            try:
                                apply(read_profile(fd))
                            except OSError:
                                pass
                        elif code == 0x10 and MEDIA_ACTION != "none":
                            press_t = time.time()     # media center basıldı
                        elif code == 0 and press_t is not None:
                            held = time.time() - press_t
                            press_t = None            # media center bırakıldı
                            media_action(held >= LONG_PRESS_SEC)
        except OSError:
            os.close(fd); time.sleep(2)

main()
PYEOF
chmod +x /usr/local/bin/x6-profd.py

cat > /etc/systemd/system/x6-profd.service <<SVCEOF
[Unit]
Description=X6 profil izleyici (profil bazli Windows kilidi + F13)
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
echo "             sudo x6feat /dev/hidrawX off    (macro-pad kapat)"
echo
echo " Makro kaydi: makro tusu (karede top) -> S tusuna bas -> dizi -> makro tusu"
echo " Makro silme: makro tusu -> S tusuna bas -> HICBIR SEY basmadan makro tusu"
echo " Media center: ozellestirilebilir (x6-profd.py icindeki MEDIA_ACTION)"
echo " Profiller:   1/2/3 tuslari; profil 2-3'te Windows kilidi"
echo "========================================================"
