# Pruva — ürün tanımı

Pruva, yelken yarışında “şimdi ne değişti, bu bize ne kazandırabilir, manevraya değer mi?” sorularını görselleştiren bir iOS karar yardımcısıdır. Navigatör koşulu ve geometriyi inceler; taktisyen seçeneklerin nedenlerini ve bedelini görür. Ortak çıktı, bir emir yerine kısa bir öneri ve onu destekleyen anlaşılır görsel bağlamdır.

## İlk sürümde kullanıcı akışı

1. Bir örnek yarış durumu seçilir ve **Simülasyon** etiketi görünür.
2. Parkurda tekne, şamandıra, kontra yolları ve güncel layline ilişkisi incelenir.
3. Rüzgâr ve manevra varsayımları değiştirilerek önerinin nasıl değiştiği görülür.
4. Karar kartındaki gerekçe, referansa göre shift ve manevra maliyetiyle birlikte okunur.
5. Rüzgâr kaydırıcısı ve örnek salınım oynatmasıyla değişim izlenir; desteklenen ayarlar/kullanıcı kayıtları yerelde saklanır.

Oynatma, kurgulanmış rüzgâr koşullarını değiştirir. “Replay” benzeri bir sunum, gerçek yarış telemetrisi veya kamera kaydı varmış anlamına gelmez. Kaynak etiketi ekran hiyerarşisinde görünür kalmalıdır.

## Karar ekranının öncelikleri

| Öncelik | Gösterim | Kullanıcının cevabını bulduğu soru |
| --- | --- | --- |
| 1 | Kısa karar ve birincil gerekçe | Şu anda hangi seçenek destekleniyor? |
| 2 | Büyük parkur görseli | Tekne layline'a ve şamandıraya göre nerede? |
| 3 | Referans rüzgâr, güncel fark ve eğilim | Son örnek mi değişti, anlamlı faz mı değişti? |
| 4 | Kalan etap ve manevra bedeli | Faydayı kullanmak için yeterli zaman var mı? |
| 5 | Açılabilir varsayım açıklamaları | Bu sonucu hangi girdiler üretti? |

Şamandıra mesafesi, VMG ve varış süresi birbirinin yerine etiketlenmez. Rüzgâra göre VMG ile doğrudan şamandıraya yaklaşma hızı farklı büyüklüklerdir. Gösterilen kazanç, girilmiş model varsayımlarına bağlı olduğunda buna uygun kısa dil kullanılır: “model faydası”, “tahmini” veya “senaryo”.

## Görsel yön

İstenen görünüm yumuşak, premium bir beyaz palettir: kırık beyaz zemin, beyaz kartlar, koyu lacivert metin, soluk deniz yeşili vurgu, az ve yumuşak gölge. Sancak ve iskele yalnızca renkle ayrılmaz; çizgi biçimi ve açık etiketler kullanılır. Parkur görseli dekor değil, kararın nedenini anlatan ana araçtır.

Tipografi büyük sayıları kısa birimleriyle birlikte gösterir; saniye, derece ve knot okunabilir kalır. Telefon ekranında birincil karar ve parkur baskındır. iPad'in genişliğinde aynı bağlam yan yana gösterilebilir. Hareketler sakin ve anlamlıdır; yön veya layline değişikliği animasyonla izlenebilir, sürekli dikkat dağıtan döngüler kullanılmaz.

Erişilebilirlik hedefi: en az 44 pt etkileşim alanı, Dynamic Type ile taşmayan kartlar, azaltılmış hareket tercihine uyum ve Canvas için metinsel eşdeğer açıklama. Paletin yumuşak olması metin kontrastının düşürülmesi anlamına gelmez. Fiziksel cihazda güneş/ıslak el kontrolleri daha sonraki saha doğrulamasına dahildir.

## Gerçekten teslim edilen ile yol haritası

Bu başlangıç ürünü yerel SwiftUI uygulaması, sınanabilir yarış çekirdeği ve elle yönetilen örnekler üzerinden görsel karar inceleme deneyimidir. Gerçek sensör alımı, hava tahmini servisi, kalibre polar, fotoğraf/video analizi, rakip takibi ve otomatik rota optimizasyonu sonraki fazlardır. Bu özellikler için hazır gibi görünen sahte canlı veri veya bağlanmış hesap durumu gösterilmez.

İlk görsel medya vektörel parkur, rüzgâr gösterimi ve senaryo ilerlemesidir. Sonraki medya sürümü, kullanıcının videosuna gerçek zaman damgalarıyla eşlenen açıklamalar ekler. Video üzerinden rakip veya rüzgâr okuması ayrıca doğrulanmış bir araştırma/ürün işi gerektirir; çizilmiş bir animasyon bu yeteneği sağlamaz.

## Ürün kabul ölçütleri

- Küçük bir rüzgâr geri dönüşü, referansa göre hâlâ lift olan durumda yalnız başına tramola emrine dönüşmez.
- Kullanıcı geometriyi ve manevra bedelini aynı karar bağlamında görebilir.
- Son yaklaşım ile dış kenara ilerleme, açıklama düzeyinde ayırt edilir.
- Her örnek değer açıkça simülasyon bağlamındadır; kayıt ve veri kaynağı belirsiz değildir.
- Senaryo veya parametre değiştiğinde parkur ve karar aynı girdilere göre yenilenir.
- Uygulama internet, hesap veya harici enstrüman olmadan ilk deneyimini açar.

Teknik sınırlar, doğrulama planı ve sonraki entegrasyonların koşulları [mimari belgesinde](ARCHITECTURE.md); yarış kurallarının hesap karşılığı [karar modelinde](DECISION_MODEL.md) yer alır.
