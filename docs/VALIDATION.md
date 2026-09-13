# Doğrulama kaydı

13 Eylül 2026 · Xcode 26.6 · Swift 6.3.3 · iOS Simulator 26.5.

## Geçen kontroller

| Kontrol | Sonuç |
| --- | --- |
| RaceCore Swift Package testleri | **21 test, 0 hata** |
| iPhone 17 Pro arayüz kabul testleri | **3 test, 0 hata** |
| iPad Pro 11 inç (M5) rol/harita kontrolü | **1 test, 0 hata** |
| iOS Simulator uygulama derlemesi | Başarılı |

Motor testleri; kuzey etrafında dairesel ortalama, kontra ve bacaklara göre shift işareti, knot/metre/saniye dönüşümü, sabit koşullarda rota sırası eşitliği, manevra maliyeti, kısa/süren kafalama, layline yakınlığı, iki ayrı overstand durumu, son yaklaşım düzeltmesi, akıntı etkisi, sıfır/geçersiz veri, bitişten sonraki kazancın sayılmaması, iki rotaya ortak basınç katkısının düşülmesi ve JSON dönüşümünü kapsar.

Arayüz testleri gerçek uygulamayı açar; farklı bacaklı hazır senaryoların hedefini koruduğunu, rol metriklerinin değiştiğini, harita katmanı anahtarının değer değiştirdiğini ve kararın seyir defterine kaydedildiğini doğrular. XCTest görselleri [screenshots](screenshots) klasöründedir.

Yerel sonuç paketleri `TestResults/Pruva-Acceptance.xcresult` ve `TestResults/Pruva-iPad.xcresult` altında tutulur; büyük test çıktıları git'e dahil edilmez. Swift Package test komutu `swift test` ile tekrarlanabilir. GitHub Actions motor testlerini ve imzasız simülatör derlemesini çalıştırır.

## Sınırlar

Fiziksel teknede, gerçek sensörle, fiziksel iPhone/iPad'de veya deniz koşullarında saha testi yapılmadı. Minimum iOS 17 hedefiyle derlenir; çalışma zamanı kontrolleri iOS 26.5 simülatöründedir. Apple takım imzası, TestFlight ve App Store dağıtımı yapılmadı. Enerji tüketimi, güneş altında okunabilirlik, su geçirmez kullanım ve kalibre edilmiş polar doğruluğu bu sonuçların kapsamı dışındadır.
