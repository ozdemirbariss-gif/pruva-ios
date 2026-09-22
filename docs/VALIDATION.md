# Doğrulama kaydı

## 22 Eylül 2026 — seyir uyarıları

RaceCore: **64 test, 0 hata**. Uygulama: **25 birim testi, 0 hata**. **iPhone: 7 UI testi**, **iPad: 2 UI testi** geçti.

RaceCore'da hat parçasına en kısa mesafe, uçların dışı, ters pin sırası, geçersiz koordinat, eşik histerezisi, hızda kısa sapma/süren düşüş, tekrar eden örnek, kaynak değişimi ve eski veri testleri eklendi. RaceStore testleri canlı NMEA örnekleriyle start mesafesinin güncel GPS'e bağlı olduğunu ve hız uyarısının bağlantı kesilince temizlendiğini kontrol eder. iPhone arayüz testi [layline yaklaşma görüntüsünü](screenshots/layline-warning.png) kaydetti ve senaryo değişince uyarının söndüğünü doğruladı. Fiziksel tekne ölçümü ve açık havada parlaklık testi hâlâ gereklidir.


## 19 Eylül 2026 — erişilebilirlik ve dil katmanı

- RaceCore: 57 test, 0 hata. Karar hesabı korunur; güven seviyesi enum'a taşındı.
- Uygulama: 19 birim testi, 0 hata. Kalıcılık/bozuk dosya/yazma hatası, canlı moddan çıkış, pin mesafe reddi, gürültülü/olumsuz komutlar, AI kapalıyken standart yanıt ve üretilen kayıt indekslerinin doğrulanması kapsanır.
- iPhone 17 Pro: 6 UI testi, 0 hata. iPad Pro 11 inç: büyük yazı/kaydetme ve harita/rol testleri, 2 test, 0 hata. En büyük erişilebilirlik yazı boyutunda sekme geçişi ve gerçek kayıt oluşturma doğrulandı. Son kaydetme düzeni her iki cihazda ayrıca yeniden geçti; [iPhone büyük yazı görüntüsü](screenshots/iphone-dynamic-type-largest.png) görsel olarak kontrol edildi.
- Minimum uygulama hedefi iOS/iPadOS 26; Xcode 26.6 ve iOS Simulator 26.5 ile derlendi. RaceCore'un kendi platform hedefleri korunur.
- Kaynak taramasında UI altında sabit `.system(size:)` yazı tipi kalmadı. Dinamik metin stilleri ve büyük boyutlarda dikey kart düzenleri kullanılır.

Modelin gerçek cihazda Türkçe üretim kalitesi, fiziksel VoiceOver kullanımı, güneşte/eldivenle etkileşim ve gerçek tekne bağlantısı doğrulanmadı. Simülatörde derleme, standart komut yolu ve model çıktısının sınırlandırılması test edildi; bunlar gerçek Foundation Models çıkarım testi değildir. Polar öğrenimi ve salınım periyodu uygulanmadı; veri gereksinimleri ARCHITECTURE.md'de açıklandı. CI için Xcode 26 seçimi eklendi, uzak CI koşusu bu oturumda yapılmadı.

## Önceki doğrulama (15 Eylül 2026)

15 Eylül 2026 · Xcode 26.6 · Swift 6.3.3 · iOS Simulator 26.5.

## Geçen kontroller

| Kontrol | Sonuç |
| --- | --- |
| RaceCore Swift Package testleri | **57 test, 0 hata** |
| Pruva iOS uygulama birim testleri | **12 test, 0 hata**; canlı GPS start pini, kalıcılık, Türkçe komut yorumlama ve eski/verisiz konum reddi dahil |
| iPhone 17 Pro arayüz kabul testleri | **4 test, 0 hata**; yazılı rüzgâr bildirimi ve model yanıtı dahil |
| iPad Pro 11 inç (M5) rol/harita kontrolü | **1 test, 0 hata** |
| iOS Simulator uygulama derlemesi | Başarılı |

Motor testleri; kuzey etrafında dairesel ortalama, kontra ve bacaklara göre shift işareti, knot/metre/saniye dönüşümü, sabit koşullarda rota sırası eşitliği, manevra maliyeti, kısa/süren kafalama, layline yakınlığı, iki ayrı overstand durumu, son yaklaşım düzeltmesi, akıntı etkisi, sıfır/geçersiz veri, bitişten sonraki kazancın sayılmaması, iki rotaya ortak basınç katkısının düşülmesi ve JSON dönüşümünü kapsar.

Arayüz testleri gerçek uygulamayı açar; farklı bacaklı hazır senaryoların hedefini koruduğunu, rol metriklerinin değiştiğini, harita katmanı anahtarının değer değiştirdiğini, kararın seyir defterine kaydedildiğini ve yazılı “Rüzgâr açtı” komutunun karar yanıtı ürettiğini doğrular. iPhone görselleri XCTest eklerinden, iPad görseli çalışan simülatörden alınıp [screenshots](screenshots) klasörüne kaydedildi. Yerel sentetik NMEA akışıyla komite ve port pinleri simülatörde ayrı ayrı alındı; parkurda 77 m start hattı oluştu ve [iPad start görseli](screenshots/ipad-start-hatti.png) kaydedildi.

Test sonuç paketleri depo dışında geçici olarak tutulur; büyük test çıktıları git'e dahil edilmez. Swift Package test komutu `swift test` ile tekrarlanabilir. GitHub Actions motor testlerini ve imzasız simülatör derlemesini çalıştırır.

## Sınırlar

Fiziksel teknede, gerçek sensörle, fiziksel iPhone/iPad'de veya deniz koşullarında saha testi yapılmadı. Gerçek mikrofon konuşma tanıması ve fiziksel ses tuşu kısayolu simülatörde doğrulanamadı. 15 Eylül çalışmasında minimum iOS 17 hedefi kullanılmıştı; güncel uygulama hedefi iOS/iPadOS 26'dır. Apple takım imzası, TestFlight ve App Store dağıtımı yapılmadı. Enerji tüketimi, güneş altında okunabilirlik, su geçirmez kullanım ve kalibre edilmiş polar doğruluğu bu sonuçların kapsamı dışındadır.
