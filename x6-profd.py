#!/usr/bin/env python3
# x6-profd.py - X6 profil izleyici: profil 2/3'te Windows tuslarini kilitler
#
# Tamamen YOKLAMA tabanli: HID input raporlari (rapor 01) bu cihazda
# cekirdekte tek okuyucuya (sidewinderd) aktarildigi icin profil tespiti
# feature raporu (rapor 07) okunarak yapilir - tum okuyucularla uyumlu.
#
# Media center tusunun islevlendirilmesi icin bkz. README (KDE/GNOME
# kisayollarindan baglanir; keyd sanal klavyesi uzerinden iletilir).
import os, fcntl, subprocess, time

LOCK_PROFILES = {2, 3}          # bu profillerde Windows kilidi

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
        try:
            fd = os.open(node, os.O_RDWR | os.O_NONBLOCK)
        except OSError:
            time.sleep(2); continue
        last = None
        try:
            while True:
                try:
                    prof = read_profile(fd)
                except OSError:
                    break                            # cihaz gitti -> yeniden tara
                if prof != last:
                    apply(prof)
                    last = prof
                time.sleep(0.3)
        except OSError:
            pass
        try:
            os.close(fd)
        except OSError:
            pass
        time.sleep(2)

main()
