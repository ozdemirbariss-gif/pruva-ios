# Pruva — yarış karar modeli

Bu belge, paylaşılan yarış konuşmasının ürün kurallarına dönüştürülmesini açıklar. İlk sürüm bu kuralların deterministik, basitleştirilmiş bir simülasyonudur. Aşağıdaki denklemler mühendislik modelidir; kalibre edilmiş yarış tahmini veya evrensel otomatik manevra talimatı değildir.

## 1. Rüzgârı bir referansa göre oku

Referans, son okuma değil, belirlenen zaman penceresindeki rüzgâr yönlerinin dairesel ortalamasıdır. Dereceler önce radyana çevrilir:

```text
C = Σ cos(θᵢ) / n
S = Σ sin(θᵢ) / n
ortalama = normalize360(atan2(S, C))
fark = normalizeSigned(güncelYön − ortalama)
```

`normalizeSigned`, farkı −180° ile +180° aralığına taşır. 359° ve 1° yaklaşık kuzeyi verir; 180° vermez. Yönler birbirini tamamen dengeliyorsa tek ortalama anlamlı değildir; gerçek sensör sürümünde bu durum kalite sorunu olarak işaretlenir.

Mevcut motor bir `circularMean` yardımcı hesabı sunar; karar girdisindeki ortalama, senaryo veya kullanıcı tarafından verilir. Kayan zaman penceresinden gerçek sensör örneği toplama henüz uygulanmış değildir. Referansın örnekleme aralığı ve yaşı, ölçüm fazında görünür hale getirilecektir.

Örnek: referans 0°, sancak kontrada +10° lift, ardından +4° olsun. Son örnekten 6° düşüş vardır; tekne hâlâ referansa göre +4° lift'tedir. “6° header geldi, hemen tramola” sonucu çıkarılmaz. Bu ayrım, başlıkların ortalamaya göre yorumlanması ilkesiyle uyumludur. [Speed & Smarts — Upwind Strategy](https://www.speedandsmarts.com/toolbox/articles2/the-smart-course/upwind-strategy).

## 2. Layline bir koşul sonucudur

Layline; şamandıra, rüzgâr yönü, teknenin hedef seyir açısı/hızı ve akıntı ile yeniden hesaplanır. Koşullar veya polar değişince çizgi de değişir. Ekrandaki çizgi sabit bir parkur sınırı değildir. Tekne ve koşula göre farklılaşan layline yaklaşımı ile akıntının etkisi kaynakta açıklanır. [Speed & Smarts — Smart Basics](https://www.speedandsmarts.com/toolbox/articles2/the-smart-course/smart-basics).

Yerel düzlemde hız vektörü doğu/kuzey bileşenleriyle ifade edilir:

```text
suyaGöreHız(heading) = hız × (sin(heading), cos(heading))
karayaGöreHız = suyaGöreHız + akıntıVektörü
şamandırayaVektör = sancakHız × sancakSüresi + iskeleHız × iskeleSüresi
```

Son denklem iki bilinmeyenli bir sistemdir. Mevcut motor konumu metre, hız vektörünü m/s kullanır; çözüm doğrudan saniyedir. Knot girdileri vektöre çevrilirken 1852/3600 ile çarpılır. Negatif çözüm süresi, iki pozitif seyir parçasıyla hedefe ulaşan iç bölge çözümünün bulunmadığını söyler. Bu sonucu sıfıra kırpıp geçerli rota gibi göstermek yanlıştır; dışarı taşma/final yaklaşım ayrı değerlendirilir. Yakın paralel vektörler ve sıfır hız için geçersiz çözüm yolu gerekir.

Sabit rüzgâr, sabit akıntı, sabit hız/açı ve aynı uç noktalar varsayımında; pozitif iki kontra toplamları yer değiştirse de geometri değişmez. Basamak sayısını artırmak tek başına ilerleme yaratmaz. Ek manevralar zaman kaybettirir. Basınç farkı, dalga, değişen akıntı, rüzgâr değişimi veya filo etkisi bu eşitliğin varsayımlarını değiştirebilir.

## 3. Uzun kontra kalan işle ilgilidir

“Uzun kontra”, şimdiye kadar daha fazla yelken açılan taraf değil, mevcut konumdan hedefe kalan çözümde daha çok süre gerektiren kontradır. Parkur dengesi kararın bağlamıdır: içeri götüren uzun kontrada küçük/geçici bir header'ı kovalamak gereksiz manevra yaratabilir. Kenara yaklaşırken içeri dönme fırsatı daha değerlidir. Bunlar otomatik tek eşik yerine geometri ve manevra maliyetiyle birlikte ele alınır. [Speed & Smarts — Upwind Strategy](https://www.speedandsmarts.com/toolbox/articles2/the-smart-course/upwind-strategy).

## 4. Kazancı manevra maliyetiyle karşılaştır

Alternatif yollar aynı hedef, aynı başlangıç zamanı ve aynı koşul varsayımlarıyla kıyaslanır. Örnek bir karar muhasebesi:

```text
kullanılabilirUfuk = min(beklenenShiftSüresi, kalanEtapSüresi, 600 saniye)
brütFayda = bu ufuk içinde kullanılabilecek tahmini zaman faydası
ekManevraKaybı = alternatifin ek manevra sayısı × manevra başı kayıp
netFayda = brütFayda − ekManevraKaybı
```

Manevra kaybı, manevranın baştan sona süresi değil, manevrasız referansa karşı eşdeğer kayıptır. Bir alternatif iki ek tramola gerektiriyor, her biri 8 saniye kaybettiriyorsa eşik en az 16 saniyedir. Alternatifler zaten birer tramola gerektiriyorsa ortak maliyet iki kez düşülmez. Kullanıcı tarafından girilen kayıp bir varsayımdır; tekne loglarından ölçülmüş gibi sunulmaz.

Mevcut motor iki varsayımsal rota karşılaştırır: aynı kontrada kalmak ve şimdi diğer kontraya geçmek. Her iki yol kullanılabilir ufukta girilen güncel rüzgârla ilerler, ardından girilen ortalama rüzgâr koşulunda tamamlanır. Ortalama yöne geri dönüş, kullanıcı senaryosunun basitleştirmesidir; ölçülmüş bir tahmin değildir. Ufuk ayrıca 10 dakikayla sınırlandırılır. Diğer kontradaki basınç avantajı, iki adayın bu kontrada ufuk içinde kaldığı sürelerin farkına kullanıcı tahmini yüzde uygulanarak eklenir. İki aday da bacağı tamamladıysa bu katkı sıfırdır. Bu yaklaşık katkı, gerçek rüzgâr alanı veya polar simülasyonu değildir.

Shift bittikten veya etap tamamlandıktan sonraki shift faydası hesaba yazılamaz. İlk sürümün basitleştirilmiş fayda metriği olasılık ağırlıklı hava tahmini, tam rota optimizasyonu veya tekneye özel polar çözümü değildir. Pozitif gösterge yalnızca girilmiş senaryo koşullarında destekleyici gerekçedir.

## 5. Final yaklaşımı dış kenardan ayır

| Durum | Karar mantığı |
| --- | --- |
| Tekne dış kenara gidiyor, karşı kontrada son yaklaşım henüz başlamadı | İçeri dönme ve layline'a erken kilitlenmeme seçeneğini değerlendir |
| Tekne son kontrada, şamandıra mevcut kontrada ulaşılabilir | Ulaşılabilir doğrudan rota önceliklidir; sadece yeni bir lift olduğu için tramola önerme |
| Son yaklaşımda lift sonucu şamandıra hedef orsa açısının altında kaldı | Gerekirse şamandıraya doğru açıyı açma; kesin açı için geometri/polar gerekir |
| Tekne gerçekten overstand etti | Geçmiş fazla yol geri kazanılamaz; bundan sonraki uygun rota ve trim değerlendirilir |
| Shift için kalan zaman çok az | Uzak gelecekteki salınımı etap kazancı gibi sayma |

Final faz sınıflaması, tek bir “layline dışındayım” bayrağına indirgenemez. Mevcut kontra, hedef doğrultusu ve karşı kontraya gerçekten ihtiyaç olup olmadığı birlikte değerlendirilir. Bu tablo paylaşılan konuşmanın mühendislik yorumudur; motor testlerinde ayrı örneklerle korunmalıdır.

## 6. Pupa ve basınç

Pupada lift/header'ın geometrik adı değişmez; tercih edilen faz değişir. Orsa için yararlı lift, pupada otomatik olarak yararlı kabul edilmez. Salınımlı rüzgârda header üzerinde kalma ve lift'te kavança seçeneği değerlendirilir. Hedef açı/hız rüzgâr şiddetine ve tekne polarına bağlıdır; daha güçlü rüzgârda hız ve açı birlikte değişebilir. [Speed & Smarts — Downwind Strategy](https://www.speedandsmarts.com/toolbox/articles2/the-smart-course/downwind-strategy).

Bu nedenle uygulamada rüzgâr şiddeti bağlamı görünür olmalıdır. İlk sürüm her iki kontrada sabit tekne hızı ve sabit akıntı kullanır; örnek hız/açı varsayımları gerçek bir teknenin basınç tepkisini modellemez. Kirli hava girdisi varsa nitel bağlamdır, aerodinamik hesap değildir. Dalga, akış alanı, rakip örtmesi, dönüş kuralları ve filo ayrışması bu çekirdeğin dışında kalır. İleri fazda her yeni etkenin kazanç bileşeni ve veri kaynağı açıklanacaktır.

## Kabul örnekleri

| Girdi | Beklenen davranış |
| --- | --- |
| Yönler 359° ve 1° | Ortalama kuzeye yakın |
| Referans 0°, sancak +10° → +4° | Son düşüşe rağmen hâlâ +4° lift |
| Aynı uç noktalar, sabit koşullar, ek basamak | Geometrik avantaj yok; ek manevra kaybı var |
| İki ek manevra, 8 saniye kayıp, 12 saniye brüt fayda | Net −4 saniye; maliyet karşılanmadı |
| Beklenti 120 saniye, kalan etap 30 saniye | Fayda ufku en fazla 30 saniye |
| Son kontrada şamandıra doğrudan erişilebilir, lift var | Yeni tramola otomatik önerilmez |
| Akıntı vektörü değişti | Karaya göre yollar ve layline yeniden hesaplanır |
| Pupa senaryosunda faz karşılaştırması | Orsa tercihi körlemesine kullanılmaz |

Bu örnekler ürün kabul hedefleridir. Depodaki testlerin kapsamı ve çalıştırma sonucu ayrıca raporlanır; tabloda yer almak bir testin geçtiği anlamına gelmez.
