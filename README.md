# SideWinder X6 — CachyOS/Arch Linux Tam Destek Paketi

Microsoft SideWinder X6 klavyenin oyun özelliklerini (makro tuşları, profil bankları,
makro kayıt tuşu, LED'ler, profil bazlı Windows-tusu kilidi) Arch Linux türevi
dağıtımlarda çalışır hale getiren tek-parça kurulum scripti ve dokümantasyon.

> Üstteki [sidewinderd](https://github.com/tolga9009/sidewinderd) projesine dayanır;
> bu repo onun kurulumunu, yapılandırmasını ve GitHub'da bulunmayan ek özellikleri
> (profil bazlı Windows kilidi, macro-pad kontrol aracı, çekirdek ioctl uyumluluğu
> çözümü) bir araya getirir.

## sidewinderd ile Farkımız Ne?

Bu repo [sidewinderd](https://github.com/tolga9009/sidewinderd)'in üzerine kuruludur
ve ona dokunmaz; tüm başarı sidewinderd'e aittir. Farkımız şunlar:

| Özellik | sidewinderd | Bu repo |
|---|---|---|
| Makrolar, profil bankaları, LED'ler (X4/X6/G105/G710+) | ✅ | ✅ (aynısı) |
| Tek komutla sıfırdan kurulum (CMake ≥ 4 yaması dahil) | ❌ | ✅ |
| Profil bazlı Windows-tusu kilidi | ❌ | ✅ (`keyd` + `x6-profd`) |
| Macro-pad modu elle kontrol aracı | ❌ | ✅ (`x6feat`) |
| HID protokolü tersine mühendislik notları | ❌ | ✅ |

## Donanım Özellik Durumu

| Özellik | Durum | Açıklama |
|---|---|---|
| Makro tuşları (S1–S10) | ✅ | sidewinderd |
| Profil bankları (1/2/3) | ✅ | 3 × 10 = 30 ayrı makro kapasitesi |
| Makro kayıt tuşu (koşan adam) | ✅ | Kayıt fonksiyonu çalışıyor; **ışığı yanmıyor** |
| Makro (S) ve profil LED'leri | ✅ | Hepsi yanıyor |
| Top tuşu (karede top) | ✅ | Macro-pad modunu aç/kapatır |
| Koşan adam (record) LED'i | ❌ | Tek çalışmayan ışık bu (protokol notlarına bakın) |
| Profil bazlı Windows kilidi | ✅ | **Bu repoya özel** (keyd + x6-profd) |
| Macro-pad modu elle kontrol | ✅ | **Bu repoya özel** (x6feat) |
| Kayıt (record) LED'i | ❌ | Donanım sağlam; protokolü çözülmemiş (bkz. Protokol Notları) |

## Desteklenen Sistemler

| Dağıtım | Durum | Not |
|---|---|---|
| CachyOS / Arch / Manjaro / EndeavourOS | ✅ tam | `pacman`; keyd deposda mevcut |
| Ubuntu / Debian / Mint / Pop!_OS | ✅ tam | `apt`; keyd otomatik kaynaktan derlenir |
| Fedora / diğerleri | ⚠️ elle | Gerekenler: cmake, libconfig, tinyxml2, udev geliştirme başlıkları, keyd |

Gereksinimler: Linux çekirdek 6.x (hidraw), X11 veya Wayland (keyd ikisinde de
çalışır). Protokol bulguları çekirdek seviyesinde olduğundan dağıtımdan bağımsızdır.

## Kurulum

```bash
git clone https://github.com/KULLANICI_ADIN/sidewinder-x6-linux.git
cd sidewinder-x6-linux
sudo ./install.sh
```

Script şunları yapar:

1. Bağımlılıkları kurar: `base-devel cmake git libconfig tinyxml2 keyd`
2. [sidewinderd](https://github.com/tolga9009/sidewinderd)'i kaynak kodundan derler
   (CMake ≥ 4 uyumluluk bayrağı ile) ve kurar
3. `/etc/sidewinderd.conf` yapılandırmasını oluşturur (root yerine gerçek kullanıcı,
   kalıcı profil dizini `/var/lib/sidewinderd`)
4. Kullanıcıyı `input` grubuna ekler
5. `keyd`'yi kurar ve başlatır
6. `x6feat` C aracını derler, `x6-profd` Python izleyicisini kurar
7. Sistem servislerini (`sidewinderd`, `x6-profd`) etkinleştirir
8. Macro-pad modunu açar

**Kurulumdan sonra oturumu kapatıp açın** (`input` grubu üyeliğinin etkinleşmesi için).

## Kullanım

### Profiller (1/2/3 tuşları)

1/2/3 tuşları üç ayrı makro "sayfası" arasında geçiş yapar; aktif profilin LED'i yanar.
Her profilin kendi S1–S10 makro seti vardır (toplam 30 makro).

| Profil | Windows tuşu | Önerilen kullanım |
|---|---|---|
| 1 | Serbest | Masaüstü / günlük işler |
| 2 | Kilitli | Oyun profili A |
| 3 | Kilitli | Oyun profili B |

Kilitli profiller `x6-profd.py` içindeki `LOCK_PROFILES = {2, 3}` satırından
değiştirilebilir.

### Makro kaydı

1. **Koşan adam tuşuna bas** → ışık yanar; S tuşları ve koşan adam ışığı
   yanıp sönmeye başlar (atama modu)
2. **Makro atayacağın S tuşuna bas** → o tuş için kayıt başlar
3. **İstediğin tuş dizisini bas** (örn. `Ctrl+Shift+T`)
4. **Koşan adam tuşuna tekrar bas** → kayıt biter, makro o S tuşuna atanmış olur

Makroyu oynatmak için S tuşuna normal şekilde basman yeterli.

**Alternatif yol — koşan adama hiç basmadan:** Makro atayacağın S tuşuna
**basılı tut** → LED yanıp söner → diziyi bas → aynı S tuşuna **tekrar basılı tut**
→ kayıt biter.

### Makro silme

Boş makro kaydetmek silmek demektir:

1. **Koşan adam tuşuna bas** → ışıklar yanıp sönmeye başlar
2. **Sileceğin makronun kayıtlı olduğu S tuşuna bas**
3. **Hiçbir tuşa basmadan** koşan adam tuşuna tekrar bas → o S tuşuna boş makro
   kaydedilir, eski makro silinir

Makrolar sistem çapında çalışır (X11/Wayland fark etmez).

> Teknik not: Makrolar `/var/lib/sidewinderd/profile_X/sY.xml` dosyalarında
> tutulur; elle düzenleme/yedekleme için bu dizine bakabilirsiniz.

### Araçlar

```bash
sudo x6feat /dev/hidrawX        # rapor 07 durumunu okur (macro-pad açık/kapalı)
sudo x6feat /dev/hidrawX on     # macro-pad modunu açar
sudo x6feat /dev/hidrawX ledon  # record LED bitlerini yakar (test amaçlı)
```

(X düğüm numarası cihaza göre değişir; `ls /dev/hidraw*` ile bakın veya
`/sys/class/hidraw/*/device/uevent` içinde `045E`/`074B` arayın.)

**Macro-pad modu nedir:** Top tuşu (karede top) bu modu aç/kapatır. Kapalıyken
ayrılabilir numpad normal rakam tuşu, açıkken ek makro tuşu (S11+) olarak çalışır.
Bazı işlevler (ör. kayıt tuşu) bu moda bağlıdır; mod kapanırsa `x6feat ... on` ile
açın ya da top tuşuna bir kez basın.

**Top tuşu ne işe yarıyor?** X6'nın mıknatıslı numpad'ı iki kişilik çalışır:
normal rakam tuşları ya da **ek makro tuşları (S11+)**. Top tuşu bu iki kişilik
arasında geçiş yapar — Windows'taki "Game Center" tuşunun birebir karşılığıdır.
Numpad'ı hiç makro tuşu olarak kullanmıyorsanız bu tuşa basmanıza gerek yok;
yalnızca makro-pad modunun **açık** kaldığından emin olun (`sudo x6feat /dev/hidrawX`
ile `ACIK` görmelisiniz). Yanlışlıkla basıp modu kapatırsanız kayıt tuşu gibi bazı
işlevler tepkisizleşir — o durumda bir kez daha basarak geri açın.

## Protokol Notları (tersine mühendislik bulguları)

Bu depo, X6'nın üreticiye özel HID protokolüne dair şu bulguları belgeler:

### Çalışan ioctl değerleri

Yeni Linux çekirdeklerinde hidraw'ın "raw" ioctl ailesi (`HIDIOCGRAWFEATURE`,
numara `0x07`, yön `READ`) bazı sistemlerde `EINVAL` ile reddediliyor veya boş veri
dönüyor. **Çalışan değerler** (sistem başlıklarındaki `HIDIOCGFEATURE`/`HIDIOCSFEATURE`
makrolarından alınmıştır):

```
Okuma:  0xC0024807   (_IOC(READ|WRITE, 'H', 0x07, 2))
Yazma:  0xC0024806   (_IOC(READ|WRITE, 'H', 0x06, 2))
```

Örnek (rapor 07 = kontrol/LED raporu, 2 bayt):

```python
import os, fcntl
f = os.open("/dev/hidrawX", os.O_RDWR)
buf = bytearray(2); buf[0] = 7
fcntl.ioctl(f, 0xC0024807, buf)          # oku
buf[1] |= 1                              # macro-pad biti
fcntl.ioctl(f, 0xC0024806, bytes(buf))   # yaz
```

### Rapor 07 (feature, 1 bayt veri)

| Bit | Anlam |
|---|---|
| `0x01` | Macro-pad modu (top tuşu ters çevirir) |
| `0x02` | Otomatik profil (?) |
| `0x04` | Profil 1 LED |
| `0x08` | Profil 2 LED |
| `0x10` | Profil 3 LED |
| `0x60` | Record LED (sidewinderd tanımı — X6'da **etkisiz**, bkz. aşağı) |

### Rapor 01 (input, 8 bayt) — özel tuşlar (6. bayt)

| Değer | Tuş |
|---|---|
| `0x10` | Top tuşu ("Game Center") — macro-pad aç/kapa |
| `0x11` | Koşan adam (Record) — makro kaydı başlat/bitir |
| `0x14` | Profil tuşu — bank değiştir |

### Bilinen sorun: Record LED

Rapor 07'nin **tüm bitleri 1 yapıldığında** (`0xFF` testi) X6'da bütün LED'ler
yanarken record LED'i yanmaz. Rapor 09 ve `0A` ise hidraw üzerinden yazılamaz
(`EPIPE`). Windows Intellitype bu LED'i sürüyor; kullanılan protokol adımı
bilinmiyor. Donanım sağlamdır (Windows'ta çalışıyor). Bu bulgu
[sidewinderd #50](https://github.com/tolga9009/sidewinderd/issues/50)'nin
eksik kalan parçasıdır.

## Bilinen Sorunlar

- **`keyd reload` SEGV (keyd 2.6.0)**: keyd'in SIGHUP ile yeniden yapılandırma
  yolunda çökme hatası vardır (`SIGSEGV`). `x6-profd` bu yüzden `reload` yerine
  `systemctl restart keyd` kullanır; profil değişiminde çok kısa bir giriş
  kesintisi olması normaldir.
- **Kayıt (record) LED'i**: Yukarıdaki Protokol Notları bölümüne bakın.

## Sorun Giderme

```bash
# Servis logları
journalctl -u sidewinderd -f
journalctl -u x6-profd -f

# Cihaz doğru tanınmış mı
journalctl -u sidewinderd -n 30 | grep "Found device"

# X6 hangi hidraw düğümleri
grep -l . /sys/class/hidraw/hidraw*/device/uevent | xargs grep -l 045E
```

- Koşan adam tepkisizse → macro-pad modu kapalıdır: `sudo x6feat /dev/hidrawX on`
- Makro kaydı çalışmıyorsa → kullanıcı `input` grubunda mı? (`groups`) Oturum
  kapatıp açtınız mı?
- `CMake < 3.5 uyumluluğu kaldırıldı` hatası alırsanız → script zaten
  `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` ile derliyor; eski elle kurulum yaptıysanız
  bu repodaki `install.sh`'yi kullanın.

## Dosya Yapısı

```
install.sh     # tek parça kurulum (tüm araçlar ve servisler gömülü)
uninstall.sh   # kurulumu kaldırır (paketleri elle kaldırma notu içinde)
README.md      # bu dosya
```

## Kaynaklar ve Teşekkürler

- [sidewinderd](https://github.com/tolga9009/sidewinderd) — Tolga Cakir (GPL).
  Bu repo onun çalışmasını kurulum ve ek özelliklerle sarar; sidewinderd'in
  kendisi değiştirilmemiştir.
- [keyd](https://github.com/rvaiya/keyd) — sistem çapında tuş haritalama.
- USB HID rapor tanımları `usbhid-dump` ile, davranış `strace` ve
  sidewinderd kaynak kodu ile analiz edilmiştir.

## Lisans

sidewinderd kısmı [GPL](https://github.com/tolga9009/sidewinderd) lisansıyla
dağıtılır. Bu repodaki ek scriptler (`install.sh`, `x6feat.c`, `x6-profd.py`)
istediğiniz gibi kullanılabilir (public domain / MIT gibi düşünebilirsiniz).
