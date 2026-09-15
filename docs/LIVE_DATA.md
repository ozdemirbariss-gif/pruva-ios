# Pruva — Wi-Fi üzerinden NMEA 0183

Pruva'nın canlı veri yolu, teknenin Wi-Fi NMEA 0183 ağ geçidinden **TCP istemcisi** veya **UDP unicast dinleyicisi** olarak veri alır. Simülasyon ayrı bir moddur. Uygulamanın yeniden açılması veya daha önce kaydedilmiş bağlantı ayarları, eski sensör değerlerini kendiliğinden canlı veriye dönüştürmez.

Teknedeki cihazın marka/modeli ve yayın ayarları henüz bilinmiyor. Bu geliştirmede belirli bir tekne enstrümanıyla bağlantı kurulmuş değildir. Yerel sentetik testler, donanım uyumluluk veya deniz doğrulamasının yerine geçmez.

## Bağlantı kurulumu

| Tür | Pruva'nın rolü | Gerekli bilgi |
| --- | --- | --- |
| TCP — başlangıç tercihi | Ağ geçidinin NMEA sunucusuna bağlanan istemci | Ağ geçidinin IP adresi/host adı ve NMEA veri portu |
| UDP unicast | Seçilen yerel portta gelen datagramları dinleyen alıcı | Ağ geçidinde hedef olarak iPhone/iPad'in Wi-Fi IP adresi ve Pruva'nın dinlediği port |

Port alanının başlangıç değeri **10110**'dur; bu evrensel bir cihaz portu değildir. Donanımın yapılandırılmış portunu kullanın. HTTP yönetim portu ile NMEA veri portunu karıştırmayın. Üretici örneği olarak Actisense, ağ geçidi IP adresi ile veri sunucusu portunun uygulamaya girilmesini tarif eder; bu bağlantı belgesi Pruva kullanıcısının Actisense cihazı olduğu anlamına gelmez. [Actisense W2K-1 ürün ve bağlantı açıklaması](https://actisense.com/products/w2k-1-nmea-2000-wifi-gateway/).

Teknede iPhone/iPad ile ağ geçidi aynı erişilebilir Wi-Fi ağında olmalıdır. TCP'de host **ağ geçididir**. UDP'de ağ geçidinin gönderim hedefi **telefondur**; uygulama host'a TCP benzeri bir oturum açmaz. Telefonun DHCP adresi değişirse UDP hedefini güncellemek gerekir. NMEA 2000 CAN hattı doğrudan desteklenmez; ağ geçidinin NMEA 0183 metin cümleleri üretmesi gerekir.

**Broadcast ve multicast bu sürümde etkin değildir.** Böyle yayın yapan bir ağ geçidini TCP veya telefona özel UDP unicast olarak yapılandırın. iOS'ta IP multicast/broadcast göndermek veya almak ayrıca `com.apple.developer.networking.multicast` yetkisi gerektirir. TCP yerel ağ erişimi için sistemin yerel ağ izin akışı kullanılır; unicast alımının izin davranışı farklı olabilir. [Apple TN3179 — Local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy), [Apple multicast entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast).

## Desteklenen ölçümler

| Cümle | Kullanılan alanlar | Sınır |
| --- | --- | --- |
| RMC | Enlem/boylam, SOG, COG | Geçerli GPS durumuyla |
| GGA | Enlem/boylam ve fix durumu | Hız sağlamaz |
| VTG | SOG ve gerçek kuzeye göre COG | Konum sağlamaz |
| HDT | Gerçek kuzeye göre pruva | Manyetik heading yerine kullanılamaz |
| VHW | Gerçek heading ve STW | Suya göre hız, SOG'dan ayrı tutulur |
| MWD | Gerçek kuzeye göre rüzgâr yönü ve hız | Manyetik yön gerçek kuzey gibi kullanılmaz |
| MWV, `T` | Tekneye göre gerçek rüzgâr açısı ve hız | Mutlak yön için güncel HDT/VHW heading gerekir |
| MWV, `R` | Görünür rüzgâr açısı ve hız | Gerçek rüzgâr veya taktik rüzgâr ortalaması üretilmez |

Yalnız checksum doğrulamasından geçen, alanları ve geçerlilik durumu uygun cümleler kabul edilir. NMEA cümle yapısı ve alan anlamları için [GPSD — NMEA Revealed](https://gpsd.gitlab.io/gpsd/NMEA.html) uygulama referansıdır; resmi NMEA standardının yerine geçirilmez.

`MWV(T)` içindeki **T, kuzeye göre pusula yönü demek değildir**. Motorun kullanacağı yön, gerçek heading ile göreli gerçek rüzgâr açısının toplamının 0–360° aralığına getirilmesidir. Güncel `MWD` varsa mutlak gerçek rüzgâr kaynağı olarak tercih edilir; yoksa güncel `MWV(T)` ve heading birlikte kullanılır. `MWV(R)` üzerinden yalnız SOG çıkararak gerçek rüzgâr uydurulmaz.

## Veri yaşı, rüzgâr referansı ve karar kapısı

Ölçümlerin yaşı cihazın **alım zamanına** göre izlenir. RMC'nin kaynak UTC alanı sensör saati eşleme veya gecikme telafisi olarak kullanılmaz. Her gerekli ölçümün güncel olması gerekir; devam eden GPS paketi, durmuş rüzgârın yaşını yenilemez. Eşik **15 saniye**dir. Bozuk checksum veya geçersiz durum, ölçümü güncel kabul ettirmez.

Rüzgâr referansı, güncel bağlantı oturumunda son **2 dakikalık dairesel ortalama** üzerinden oluşur. 359°/1° geçişi kuzeyde kalır. Ortalama geçmişi bağlantı başında yeterince dolu olmayabilir; ilk örnekler bir yarış öncesi uzun gözlem serisi değildir. Dağılımın belirsiz olduğu durumda kesin bir rüzgâr fazı varsayılmaz.

Taktik öneri için güncel **GPS konumu, GPS hızı/yer rotası, gerçek heading, STW ve gerçek rüzgâr** ile yapılandırılmış bir gerçek şamandıra gerekir. SOG, STW'nin yerine konmaz: motorun tekne hızı suya göre hızdır; yer hızı/COG ayrıca gösterilir. Veri kısmen geldiyse alınan SOG veya görünür rüzgâr gibi alanlar gösterilebilir, ancak eksik gereksinimler giderilmeden canlı manevra önerisi üretilmez. Bağlantı veya veri eskidiğinde son rakamın ekranda kalması, önerinin geçerli kaldığı anlamına gelmez.

Hedef seyir açısı, manevra kaybı, beklenen shift süresi ve akıntı gibi hesap girdileri bu bağlantı sayesinde otomatik kalibre olmuş sayılmaz. GPS/rüzgâr ölçümü, parkurun her noktasında bir rüzgâr haritası sağlamaz. Taktik motorun polar, sabit hız ve çevre varsayımları ayrıca geçerlidir.

## Gerçek şamandıra ve yerel çizim

Canlı hedefi ondalık derece cinsinden **enlem/boylam** ile girin veya şamandıra konumundayken güncel GPS konumunu hedef olarak kaydedin. Güncel konum olmadan kayıt yapılmamalıdır. Bağlantı ve şamandıra ayarları bu cihazda saklanır. Simülasyondaki yerel bir nokta gerçek şamandıra yerine geçirilmez.

Gerçek GPS konumu ve hedef, hesap için yerel doğu/kuzey metre düzlemine çevrilir. Bu yaklaşım yakın yarış parkuru içindir; dönüşüm 100 km altı ve mutlak enlem 85° altıyla sınırlıdır. Ekran **şematik yarış diyagramıdır**; kıyı, derinlik, engel veya deniz haritası tabanı sağlamaz.

Tüm sensör verileri cihazda işlenir; ham telemetri sunucuya yüklenmez. Kullanıcının kendi seçimiyle paylaşacağı karar notu ayrı bir dışa aktarma eylemidir. Arka planda kesintisiz kayıt veya otomatik yeniden bağlanma garantisi yoktur; uygulamaya dönüldüğünde güncellik yeniden kontrol edilmelidir.

## Yerel sentetik yayıncı

`scripts/nmea_fixture.py` yalnız Python standart kütüphanesini kullanır. Varsayılan TCP uç noktası `127.0.0.1:10110`'dur; tek istemci bağlandıktan sonra saniyede bir örnek grubu yollar. UDP kullanımı açıkça seçilir ve yalnız unicast hedef kabul edilir. Geliştirme örnekleri loopback'e yöneliktir; LAN yayını yapmayın.

```sh
# TCP: sunucuyu başlat, sonra simülatörde bağlan
python3 scripts/nmea_fixture.py --count 60

# UDP: önce simülatörde UDP dinleyicisini aç
python3 scripts/nmea_fixture.py --udp --target 127.0.0.1 --port 10110 --count 60

# Ağ soketi açmadan örnekleri incele; sabit UTC ile tekrarlanabilir çıktı
python3 scripts/nmea_fixture.py --print-only --count 1 --start-time 2026-09-14T09:00:00Z
```

Koordinat/hız/rüzgâr dizisi deterministiktir; kaynak UTC varsayılan olarak yayın başlangıcındaki saattir. `--start-time` bütün çıktıyı tekrar üretilebilir yapar. RMC/GGA UTC taşır; diğer cümlelerin doğal formatına sahte bir zaman alanı eklenmez. Sayısal örnekler aynı saniyelik gruba aittir. Terminal çıktısı sentetik olduğunu belirtir. **Uygulamanın soketi canlı veri olarak alması, test yayıncısının gerçek tekne ölçümü olduğu anlamına gelmez.**

İlk sentetik konum `40.950000, 29.050000`'dır. Yerel test hedefi olarak `40.965000, 29.045000` girilebilir. Bu sayılar yalnız test parkurudur. iOS simülatörüyle aynı Mac üzerinde loopback kullanın; fiziksel telefonda `127.0.0.1` telefonun kendisini ifade eder, Mac'i değil. `Ctrl-C` yayıncıyı kapatır; TCP istemcisi ayrıldığında sunucu da sonlanır.

## Elle kabul kontrolü

Bu bölüm uygulanacak kontrol prosedürüdür; tamamlanmış tekne testi kaydı değildir.

1. **TCP:** yayıncıyı başlatın; uygulamada TCP, `127.0.0.1`, `10110` seçip bağlanın. SOG ile STW'nin ayrı ve farklı, heading ile COG'nin ayrı olduğunu doğrulayın. Hedef girmeden öneri kapısını, yukarıdaki test hedefini girdikten sonra parkuru kontrol edin.
2. **UDP:** TCP'yi ayırın. Uygulamada UDP `10110` dinleyin, ardından UDP örneğini çalıştırın. Aynı ölçümler gelmeli; TCP bağlantısı varmış gibi host oturumu beklenmemelidir.
3. **Tek alanın eskimesi:** aşağıdaki komutta ilk 5 örnekten sonra tüm rüzgâr cümleleri kesilir. GPS/heading/STW devam ederken son rüzgârdan 15 saniye sonra canlı öneri durmalıdır; kalan GPS akışı eski rüzgârı güncel tutmamalıdır.

   ```sh
   python3 scripts/nmea_fixture.py --drop-wind-after 5 --count 30
   ```

4. **Gerçek/görünür ayrımı:** yeni bağlantı oturumlarında `--wind-source mwd`, `--wind-source mwvt` ve `--wind-source apparent` ile ayrı ayrı deneyin. MWV(T) heading ile gerçek yön verebilir. Yalnız görünür rüzgârda SOG gelmeye devam ederken gerçek rüzgâr gereksinimi eksik kalmalıdır.
5. **Checksum:** yeni bağlantı oturumunda aşağıdaki komut bütün checksum'ları bilerek bozar. Paket alınması ölçüm kabulü anlamına gelmemeli; eski ölçümler yenilenmemeli ve canlı öneri açılmamalıdır.

   ```sh
   python3 scripts/nmea_fixture.py --corrupt-every 1 --count 20
   ```

6. **Kesinti ve açılış:** yayıncıyı durdurun; bağlantı/eski veri durumunu kontrol edin. Uygulamayı kapatıp açınca kayıtlı host/port/şamandıra korunabilir, fakat sensör değerleri ve canlı durum otomatik geri gelmemelidir. Yeni bağlantı ve yeni örnekler gerekir.

Gerçek teknede son kabul; üretici ayarları, fiziksel iPhone yerel ağ izni, aynı Wi-Fi, seçilen cümleler, gerçek şamandıra koordinatı ve sensör kalibrasyonu ile ayrıca yapılır. Protokol olarak TCP/UDP desteklemek, bütün NMEA ağ geçitleriyle sahada doğrulanmış olmak değildir.
