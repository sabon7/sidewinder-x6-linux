# SideWinder X6 — Linux Destek Paketi

Microsoft SideWinder X6 klavyesinin oyun özelliklerini Linux'ta tam çalıştıran
paket: **makrolar, profil bankaları, profil bazlı Windows-tusu kilidi ve
özelleştirilebilir media center tuşu** — tek komutla kurulum.

Makro altyapısı [sidewinderd](https://github.com/tolga9009/sidewinderd) projesine
dayanır; bu paket onu kurar, yapılandırır ve GitHub'da bulunmayan ek
özellikleriyle sarar.

## Donanım Durumu

| Özellik | Durum |
|---|---|
| Makro kaydı ve oynatma (makro tuşu / karede top) | ✅ |
| 3 profil bankası (1/2/3) × 10 makro tuşu (S1–S10) | ✅ |
| Makro (S) ve profil LED'leri | ✅ |
| Profil bazlı Windows-tusu kilidi | ✅ |
| Media center tuşu (F13, özelleştirilebilir) | ✅ |
| Macro-pad modu yönetimi (`x6feat`) | ✅ |
| Koşan adam tuşu | ❌ Sinyal göndermiyor; yalnızca LED'i değil tuşun kendisi de çalışmıyor |

## Desteklenen Sistemler

| Dağıtım | Durum |
|---|---|
| CachyOS / Arch / Manjaro / EndeavourOS | ✅ `pacman` |
| Ubuntu / Debian / Mint / Pop!_OS | ✅ `apt-get` (keyd otomatik kaynaktan derlenir) |

Gereksinim: Linux çekirdek 6.x, X11 veya Wayland.

## Kurulum

```bash
git clone https://github.com/sabon7/sidewinder-x6-linux.git
cd sidewinder-x6-linux
sudo ./install.sh
```

Script bağımlılıkları kurar, sidewinderd'i derler, servisleri yapılandırır,
macro-pad modunu açar. Kurulumdan sonra **oturumu kapatıp açın** (input grubu
için) ve klavyenizi çıkarıp takın.

## Kullanım

### Tuşların haritası (üst bölüm)

| Tuş | HID kodu | İşlev |
|---|---|---|
| Makro tuşu (kare içinde top) | `0x11` | Makro kaydını başlatır/bitirir |
| Media center tuşu | `0x10` | Sanal **F13** tuşu basar (aşağıda özelleştirme) |
| Profil tuşları (1/2/3) | `0x14` | Aktif makro bankasını değiştirir |
| Koşan adam tuşu | — | Hiçbir sinyal üretmiyor (bkz. Protokol Notları) |

### Makro kaydı

1. **Makro tuşuna bas** (kare içinde top) → ışık yanar; S tuşları ve makro
   tuşu yanıp sönmeye başlar
2. **Makro atayacağın S tuşuna bas** → o tuş için kayıt başlar
3. **İstediğin tuş dizisini bas** (örn. `Ctrl+Shift+T`)
4. **Makro tuşuna tekrar bas** → kayıt biter, makro o S tuşuna atanmış olur

Makroyu oynatmak için S tuşuna normal basman yeterli.

**Alternatif:** S tuşuna **basılı tutarak** da kayıt yapılabilir
(basılı tut → LED yanıp söner → dizi → tekrar basılı tut).

**Makro silme** — boş makro kaydetmek silmek demektir:
1. Makro tuşuna bas
2. Silinecek makronun kayıtlı olduğu S tuşuna bas
3. Hiçbir tuşa basmadan makro tuşuna tekrar bas → eski makro silinir

### Profiller (1/2/3)

Her profilin kendi S1–S10 makro seti vardır (toplam 30 makro). Önerilen düzen:

| Profil | Windows tuşu | Kullanım |
|---|---|---|
| 1 | Serbest | Masaüstü / günlük işler |
| 2 | Kilitli | Oyun profili A |
| 3 | Kilitli | Oyun profili B |

Kilitli profiller `x6-profd.py` içindeki `LOCK_PROFILES = {2, 3}` satırından
değiştirilebilir.

### Media center tuşu

Varsayılan olarak media center tuşuna basınca sanal bir **F13** tuşu basılır.
F13 normal klavyelerde bulunmadığı için hiçbir şeyle çakışmaz; masaüstü
kısayollarından istediğiniz işleve bağlayın:

- **KDE:** Sistem Ayarları → Kısayollar → kendi kısayollarınız → yeni öğe →
  komut/uygulama seçin (ör. `konsole`, `spectacle`) → kısayol olarak media
  center tuşuna basın
- **GNOME:** Ayarlar → Klavye → Kısayollar → Özel Kısayollar

**İşlevi değiştirmek isterseniz:** `x6-profd.py` içindeki tek satırı değiştirin:

```python
MEDIA_ACTION = "f13"   # "lock" | "mute" | "brightness" | "none"
```

| Değer | Davranış |
|---|---|
| `"f13"` | Sanal F13 basar (varsayılan) — sistem kısayollarına bağlanır |
| `"lock"` | Ekranı kilitle |
| `"mute"` | Sesi aç/kapat |
| `"brightness"` | Kısa bas: kıs / uzun bas: aç — yalnızca dizüstü ekranlarda |
| `"none"` | İşlev yok |

Değişiklikten sonra: `sudo systemctl restart x6-profd`

## Araçlar

```bash
sudo x6feat /dev/hidrawX        # rapor 07 durumu (macro-pad açık/kapalı)
sudo x6feat /dev/hidrawX on     # macro-pad aç (numpad makro moduna geçer)
sudo x6feat /dev/hidrawX off    # macro-pad kapat (numpad rakam moduna döner)
```

(X düğüm numarası için: `/sys/class/hidraw/*/device/uevent` içinde `045E`/`074B`
aranan düğümdür.)

## Protokol Notları (tersine mühendislik)

### Çalışan ioctl değerleri

Yeni çekirdeklerde hidraw'ın "raw" ioctl ailesi (`0x07`, yön `READ`) reddedilebiliyor
ya da boş veri dönüyor. Çalışan değerler:

```
Okuma:  0xC0024807   (_IOC(READ|WRITE, 'H', 0x07, 2))
Yazma:  0xC0024806   (_IOC(READ|WRITE, 'H', 0x06, 2))
```

### Rapor 07 (feature — kontrol/LED, 1 bayt veri)

| Bit | Anlam |
|---|---|
| `0x01` | Macro-pad modu |
| `0x02` | Otomatik profil (?) |
| `0x04` | Profil 1 LED |
| `0x08` | Profil 2 LED |
| `0x10` | Profil 3 LED |
| `0x60` | Record LED bitleri (X6'da etkisiz — bkz. aşağı) |

### Rapor 01 (input — özel tuşlar, 6. bayt)

| Değer | Tuş |
|---|---|
| `0x11` | Makro tuşu (karede top) — kayıt başlat/bitir |
| `0x10` | Media center tuşu |
| `0x14` | Profil tuşları (1/2/3) |

### Bilinen sorun: koşan adam tuşu

Koşan adam tuşu Linux'ta **hiçbir HID raporu üretmiyor**; sidewinderd'in
kayıt LED'i bitleri (0x60) de rapor 07'ye `0xFF` yazılsa bile bu tuşu yakmıyor.
Rapor 09 ve `0A` hidraw üzerinden yazılamıyor (`EPIPE`). Donanım Windows'ta
Intellitype ile çalışıyor; kullanılan protokol bilinmiyor. Bu bulgu
[sidewinderd #50](https://github.com/tolga9009/sidewinderd/issues/50)'nin
eksik kalan parçasıdır.

## Bilinen Sorunlar

- **`keyd reload` SEGV (keyd 2.6.0)**: SIGHUP ile yeniden yapılandırma
  çökebiliyor. `x6-profd` bu yüzden `systemctl restart keyd` kullanır; profil
  değişiminde çok kısa bir giriş kesintisi normaldir.
- **Koşan adam tuşu**: yukarıdaki Protokol Notları'na bakın.

## Sorun Giderme

```bash
journalctl -u sidewinderd -f     # makro servisi
journalctl -u x6-profd -f        # profil izleyici + media center
systemctl status keyd            # tuş haritalama
```

- Makro kaydı tepkisizse: `sudo x6feat /dev/hidrawX on` (macro-pad modu
  kapanmış olabilir)
- `brightnessctl` yalnızca dizüstü ekranlarda çalışır; masaüstü monitörler
  için DDC/CI gerekir (paket kapsamı dışı)

## Dosya Yapısı

```
install.sh     # tek parça kurulum (tüm araçlar ve servisler gömülü)
uninstall.sh   # kurulumu kaldırır
x6-profd.py    # profil izleyici + media center işlevi (install.sh aynısını kurar)
README.md      # bu dosya
```

## Faydalandığımız Açık Kaynak Projeler

| Proje | Geliştirici | Rolü |
|---|---|---|
| [sidewinderd](https://github.com/tolga9009/sidewinderd) | Tolga Cakır ([@tolga9009](https://github.com/tolga9009)) | X6'nın makro, profil ve LED altyapısı |
| [keyd](https://github.com/rvaiya/keyd) | Raheman Vaiya ([@rvaiya](https://github.com/rvaiya)) | Windows tuşu kilidinin tuş haritalama motoru |

## Lisans

sidewinderd kısmı [GPL](https://github.com/tolga9009/sidewinderd) ile dağıtılır.
Bu repodaki ek scriptler serbestçe kullanılabilir.
