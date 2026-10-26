# FX Console — AutoHotkey v2 arayüzü

Bu klasör, FX Palette/FX Console tasarımını Windows'ta bağımsız bir AHK v2 penceresi olarak uygular. Bar 384×44 px; arama alanı, Presets/Effects başlıkları, 31 px sonuç satırları, seçim mavisi, favori yıldızları ve 152 px ayar çekmecesi UXP/web tasarımındaki değerleri kullanır.

## Çalıştırma

1. Windows'a AutoHotkey v2 kurun.
2. `FXConsole.ahk` dosyasını çalıştırın.
3. Premiere Pro açıkken `Ctrl+Alt+Space` ile arama barını açın.

Script şu temel etkileşimleri içerir: arama ve `v:`/`a:`/`p:` filtreleri, ↑/↓ ve PgUp/PgDn ile kaydırma, Enter ile seçileni uygulama isteği, Alt+F favori filtresi, yıldızla favori değiştirme, sağ tık menülerini bastırma, dışarı tıklayınca kapanma ve fare Geri tuşunun çift basışıyla açma. Boş aramada 5 saniye beklenirse bar kapanır. `Ctrl+Alt+Space` tekrar çağrıldığında yeni aramayı imlecin yanında başlatır.

## Katalog ve Premiere bağlantısı

İsteğe bağlı `FXConsole.tsv` dosyası script'in yanına konabilir; her satır `Video<TAB>Efekt adı`, `Audio<TAB>Efekt adı` veya `Preset<TAB>Preset adı` biçimindedir. Dosya yoksa arayüzü deneyebilmek için küçük bir örnek katalog kullanılır.

Enter, `apply-request.json` dosyasına seçilen öğeyi yazar. Gerçek efekt ekleme Premiere UXP API'sinin sorumluluğunda kalmalıdır: bu depo sürümündeki UXP paneli henüz bu isteği izleyen bir köprü sunmuyor. Dolayısıyla AHK arayüzünün çizimi ve arama etkileşimleri hazır; UXP uygulama köprüsü kurulduğunda gerçek uygulama devreye girer. AHK tek başına UXP'nin Premiere içindeki efekt uygulama API'sini çağıramaz.

> Not: Depoda önceki bir AHK kaynak dosyası bulunmadığı için bu, mevcut bir script'e yapılan stil yaması değil; yeni ve ayrı bir AHK v2 arayüz giriş noktasıdır. AHK v2/Windows üzerinde çalıştırma testi bu Linux geliştirme ortamında yapılamadı.
