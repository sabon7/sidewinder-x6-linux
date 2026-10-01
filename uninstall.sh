#!/usr/bin/env bash
# SideWinder X6 kurulumunu kaldirir (paketleri birakir, nota bakin)
set -e

if [[ $EUID -ne 0 ]]; then
    echo "HATA: root ile calistirin -> sudo ./uninstall.sh"
    exit 1
fi

systemctl disable --now x6-profd sidewinderd keyd 2>/dev/null || true

rm -f /etc/systemd/system/x6-profd.service
rm -f /etc/systemd/system/sidewinderd.service
rm -f /usr/local/bin/x6feat /usr/local/bin/x6feat.c /usr/local/bin/x6-profd.py
rm -f /usr/local/bin/x6-extras.py /usr/local/bin/x6-feat.py
rm -f /usr/bin/sidewinderd /etc/sidewinderd.conf
rm -rf /var/lib/sidewinderd
rm -f /etc/keyd/zz-x6-winlock.conf
systemctl daemon-reload

echo "Kaldırıldı. Elle yapılacaklar:"
echo "  1) Paketler:  pacman -Rs keyd sidewinderd tinyxml2"
echo "     (Ubuntu'da: apt purge keyd; libconfig-dev libtinyxml2-dev libudev-dev)"
echo "  2) Kullanıcı input grubundan (isterseniz):  gpasswd -d KULLANICI input"
