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
MEDIA_ACTION = "f13"
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
        r = subprocess.run(["loginctl", "lock-sessions"],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print("lock calismadi:", r.stderr.strip(), flush=True)
        else:
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
