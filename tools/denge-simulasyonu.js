#!/usr/bin/env node
/**
 * MinerInMine — Denge Simulasyonu
 *
 * NE ISE YARAR?
 * Oyunu bastan sona "oynayan" bir robot calistirir ve tempoyu olcer:
 * ilk saatte nereye gelinir, otomasyona ne zaman gecilir, 50. seviye ne kadar
 * surer, aninda bitirme ne zaman cazip hale gelir.
 *
 * NEDEN GEREKLI?
 * Denge rakamlarini tahminle ayarlamak korlemesine calismaktir. Bir sayiyi
 * degistirip "daha iyi hissettirdi mi" diye bakmak yerine, degisikligin
 * tempoya etkisini OLCUYORUZ.
 *
 * EN ONEMLI TASARIM KARARI:
 * Denge rakamlari BU DOSYADA YAZILI DEGIL — hepsi veritabanindan okunur.
 * Kopyalasaydik, SQL'de bir degeri degistirdigimizde simulasyon eski rakamla
 * calismaya devam eder ve bizi yaniltirdi. Simulasyon her zaman GERCEK oyunu
 * modeller.
 *
 * KULLANIM:
 *   node tools/denge-simulasyonu.js [saat] [mod]
 *     saat : kac saat simule edilecek (varsayilan 24)
 *     mod  : sabirli | aceleci | ikisi   (varsayilan ikisi)
 *
 *   "sabirli" oyuncu insaat surelerini bekler.
 *   "aceleci" oyuncu Kristal odeyip bekleme surelerini atlar.
 *   Ikisinin farki, aninda bitirme fiyatinin dogru olup olmadigini gosterir.
 */

const { execFileSync } = require('child_process');

const SQLCMD = 'C:/Program Files/Microsoft SQL Server/Client SDK/ODBC/170/Tools/Binn/SQLCMD.EXE';
const VERITABANI = 'MinerInMineDb';

// String.raw: sablon icindeki ters bolu OLDUGU GIBI kalir.
// Duz tirnakli '.\SQLEXPRESS' yazsaydik JS bunu bilinmeyen bir kacis sayip
// ters boluyu yutar ve sunucu adi '.SQLEXPRESS' olurdu (bu tuzaga dustuk).
const SUNUCU = String.raw`.\SQLEXPRESS`;

// ============================================================================
// VERITABANINDAN DENGE VERISINI OKU
// ============================================================================

/**
 * sqlcmd calistirir ve boru ile ayrilmis ciktiyi nesne dizisine cevirir.
 *
 * -h -1  : baslik satirini bastirma
 * -s"|"  : sutun ayraci
 * -W     : bosluk dolgusunu kaldir
 * -f 65001 : UTF-8 (Turkce karakterler icin)
 */
function sorgula(sql, sutunlar) {
  // execFileSync kullaniyoruz, execSync degil: argumanlar DIZI olarak gecer ve
  // kabuk hic devreye girmez. Kabuk uzerinden gecseydik ".\SQLEXPRESS" icindeki
  // ters bolu yutulur ve sunucu adi bozulurdu (bu tuzaga bir kez dustuk).
  const cikti = execFileSync(
    SQLCMD,
    [
      '-S', SUNUCU, '-E', '-d', VERITABANI, '-f', '65001',
      '-h', '-1', '-s', '|', '-W', '-Q', `SET NOCOUNT ON; ${sql}`
    ],
    { encoding: 'utf8', maxBuffer: 10 * 1024 * 1024 }
  );

  return cikti
    .split('\n')
    .map((s) => s.trim())
    .filter((s) => s && !s.startsWith('(') && !s.includes('rows affected'))
    .map((satir) => {
      const parcalar = satir.split('|');
      const nesne = {};
      sutunlar.forEach((ad, i) => {
        const ham = (parcalar[i] ?? '').trim();
        const sayi = Number(ham);
        nesne[ad] = ham === 'NULL' ? null : (ham !== '' && !isNaN(sayi) ? sayi : ham);
      });
      return nesne;
    });
}

function dengeyiYukle() {
  return {
    kaynaklar: sorgula(
      'SELECT Id, Code, SellValue, IsCurrency FROM ResourceTypes ORDER BY Id',
      ['id', 'kod', 'satisDegeri', 'paraMi']
    ),
    tesisTurleri: sorgula(
      `SELECT ft.Id, ft.Code, rt.Code, ft.MaxLevel, ISNULL(ft.UnlockFacilityTypeId,0), ft.UnlockLevel
       FROM FacilityTypes ft JOIN ResourceTypes rt ON rt.Id=ft.ResourceTypeId ORDER BY ft.DisplayOrder`,
      ['id', 'kod', 'kaynakKod', 'maxSeviye', 'acilisTesisId', 'acilisSeviye']
    ),
    tesisSeviyeleri: sorgula(
      'SELECT FacilityTypeId, Level, Cost, Production, UpgradeMinutes FROM FacilityLevels ORDER BY FacilityTypeId, Level',
      ['tesisId', 'seviye', 'maliyet', 'uretim', 'dakika']
    ),
    kazmalar: sorgula(
      'SELECT Id, Code, CooldownSeconds, YieldMultiplier, UnlockCost FROM ClickTypes ORDER BY DisplayOrder',
      ['id', 'kod', 'bekleme', 'carpan', 'acilisBedeli']
    ),
    madenciler: sorgula(
      'SELECT Id, Code, ClickTypeId, HireCost, MaxCount FROM MinerTypes ORDER BY DisplayOrder',
      ['id', 'kod', 'kazmaId', 'ucret', 'tavan']
    ),
    guclendirmeler: sorgula(
      'SELECT Id, Code, EffectType, EffectValue, MaxLevel FROM UpgradeTypes ORDER BY DisplayOrder',
      ['id', 'kod', 'etkiTuru', 'etkiDegeri', 'maxSeviye']
    ),
    guclendirmeSeviyeleri: sorgula(
      'SELECT UpgradeTypeId, Level, Cost FROM UpgradeLevels ORDER BY UpgradeTypeId, Level',
      ['guclendirmeId', 'seviye', 'maliyet']
    ),
    ayarlar: sorgula(
      'SELECT SettingKey, SettingValue FROM GameSettings',
      ['anahtar', 'deger']
    )
  };
}

// ============================================================================
// SIMULASYON MOTORU
// ============================================================================

/**
 * Oyunun 1 saniyelik adimlarla ilerletilmesi.
 *
 * MODELLENEN OYUNCU: "en iyiyi arayan" bir robot. Her an elindeki Kristal ile
 * alabilecegi seyler arasindan KRISTAL BASINA EN COK GELIR ARTISI saglayani
 * secer. Gercek bir oyuncu bu kadar iyi oynamaz; bu yuzden simulasyon
 * OYUNUN EN HIZLI HALINI olcer — denge icin dogru olcut budur.
 *
 * BASITLESTIRMELER (bilincli):
 *   - Cikarilan maden aninda satilir (biriktirme stratejisi yok)
 *   - Manuel tiklama, bekleme suresi dolar dolmaz yapilir (aktif oyuncu)
 *   - Gelir surekli akiyormus gibi hesaplanir (saniye ici kesirler dahil)
 */
function simule(denge, { saat = 24, aceleci = false } = {}) {
  const toplamSaniye = saat * 3600;

  const ayar = (a) => Number(denge.ayarlar.find((x) => x.anahtar === a)?.deger ?? 0);
  const dakikaBasinaKristal = ayar('INSTANT_FINISH_PER_MINUTE');

  const satisDegeri = {};
  denge.kaynaklar.forEach((k) => (satisDegeri[k.kod] = k.satisDegeri));

  const seviyeBilgisi = (tesisId, seviye) =>
    denge.tesisSeviyeleri.find((x) => x.tesisId === tesisId && x.seviye === seviye);

  // --- Baslangic durumu: yeni bir oyuncu ---
  const ilkTesis = denge.tesisTurleri[0];
  const durum = {
    zaman: 0,
    kristal: 100,
    tesisler: [{ id: ilkTesis.id, kod: ilkTesis.kod, kaynakKod: ilkTesis.kaynakKod, seviye: 1, insaatBitis: null }],
    madenciler: {},                       // "tesisId:madenciId" -> adet
    acikKazmalar: new Set([denge.kazmalar[0].id]),
    guclendirmeler: {},                   // guclendirmeId -> seviye
    kilometreTaslari: []
  };

  const carpan = (etkiTuru) =>
    1 + denge.guclendirmeler
      .filter((g) => g.etkiTuru === etkiTuru)
      .reduce((t, g) => t + g.etkiDegeri * (durum.guclendirmeler[g.id] ?? 0), 0);

  /** Saniyelik Kristal geliri: manuel tiklamalar + madenciler. */
  function gelirSn(d = durum) {
    const tiklamaCarpani = carpan('CLICK_POWER');
    const madenciCarpani = carpan('MINER_SPEED');
    const satisCarpani = carpan('SELL_BONUS');
    let toplam = 0;

    for (const t of d.tesisler) {
      const uretim = seviyeBilgisi(t.id, t.seviye).uretim;
      const deger = satisDegeri[t.kaynakKod] * satisCarpani;

      for (const kz of denge.kazmalar) {
        if (!d.acikKazmalar.has(kz.id)) continue;

        const birim = (uretim * kz.carpan) / kz.bekleme;      // saniyelik ham uretim
        toplam += birim * tiklamaCarpani * deger;             // manuel tiklama (aktif oyuncu)

        const md = denge.madenciler.find((m) => m.kazmaId === kz.id);
        if (md) {
          const adet = d.madenciler[`${t.id}:${md.id}`] ?? 0;
          toplam += birim * adet * madenciCarpani * deger;    // madenciler
        }
      }
    }
    return toplam;
  }

  /** Bir satin almanin gelire etkisini, gecici olarak uygulayip olcuyoruz. */
  function gelirFarki(uygula, geriAl) {
    const once = gelirSn();
    uygula();
    const sonra = gelirSn();
    geriAl();
    return sonra - once;
  }

  /** O an alinabilecek tum secenekler ve "Kristal basina gelir artisi" degerleri. */
  function secenekler() {
    const liste = [];

    // 1) Tesis gelistirme
    for (const t of durum.tesisler) {
      if (t.insaatBitis !== null) continue;
      const hedef = seviyeBilgisi(t.id, t.seviye + 1);
      if (!hedef) continue;
      const fark = gelirFarki(() => t.seviye++, () => t.seviye--);
      liste.push({ tur: 'gelistir', tesis: t, maliyet: hedef.maliyet, fark, dakika: hedef.dakika });
    }

    // 2) Madenci ise alma
    for (const t of durum.tesisler) {
      for (const md of denge.madenciler) {
        if (!durum.acikKazmalar.has(md.kazmaId)) continue;
        const anahtar = `${t.id}:${md.id}`;
        const adet = durum.madenciler[anahtar] ?? 0;
        if (adet >= md.tavan) continue;
        const fark = gelirFarki(
          () => (durum.madenciler[anahtar] = adet + 1),
          () => (durum.madenciler[anahtar] = adet)
        );
        liste.push({ tur: 'madenci', anahtar, ad: md.kod, tesis: t, maliyet: md.ucret, fark });
      }
    }

    // 3) Kazma turu acma
    for (const kz of denge.kazmalar) {
      if (durum.acikKazmalar.has(kz.id)) continue;
      const fark = gelirFarki(
        () => durum.acikKazmalar.add(kz.id),
        () => durum.acikKazmalar.delete(kz.id)
      );
      liste.push({ tur: 'kazma', kazma: kz, maliyet: kz.acilisBedeli, fark });
    }

    // 4) Yeni tesis satin alma (on kosul saglanmissa)
    for (const tt of denge.tesisTurleri) {
      if (durum.tesisler.some((t) => t.id === tt.id)) continue;
      if (tt.acilisTesisId) {
        const gerekli = durum.tesisler.find((t) => t.id === tt.acilisTesisId);
        if (!gerekli || gerekli.seviye < tt.acilisSeviye) continue;
      }
      const bilgi = seviyeBilgisi(tt.id, 1);
      const yeni = { id: tt.id, kod: tt.kod, kaynakKod: tt.kaynakKod, seviye: 1, insaatBitis: null };
      const fark = gelirFarki(
        () => durum.tesisler.push(yeni),
        () => durum.tesisler.pop()
      );
      liste.push({ tur: 'tesis', tesisTuru: tt, yeni, maliyet: bilgi.maliyet, fark });
    }

    // 5) Kalici guclendirme
    for (const g of denge.guclendirmeler) {
      const sv = durum.guclendirmeler[g.id] ?? 0;
      if (sv >= g.maxSeviye) continue;
      const bilgi = denge.guclendirmeSeviyeleri.find((x) => x.guclendirmeId === g.id && x.seviye === sv + 1);
      if (!bilgi) continue;
      const fark = gelirFarki(
        () => (durum.guclendirmeler[g.id] = sv + 1),
        () => (durum.guclendirmeler[g.id] = sv)
      );
      liste.push({ tur: 'guclendirme', guclendirme: g, maliyet: bilgi.maliyet, fark });
    }

    return liste.filter((s) => s.fark > 0 || s.tur === 'gelistir');
  }

  const not = (metin) =>
    durum.kilometreTaslari.push({ saniye: durum.zaman, metin, gelir: gelirSn() });

  not('Oyun basladi');

  // --- ANA DONGU ---
  for (durum.zaman = 1; durum.zaman <= toplamSaniye; durum.zaman++) {
    // 1) Suresi dolan gelistirmeleri uygula (tembel tamamlama)
    for (const t of durum.tesisler) {
      if (t.insaatBitis !== null && t.insaatBitis <= durum.zaman) {
        t.seviye++;
        t.insaatBitis = null;
        if (t.seviye === 10 || t.seviye === 25 || t.seviye === 50) {
          not(`${t.kod} seviye ${t.seviye}`);
        }
      }
    }

    // 2) Gelir birikir (maden aninda satiliyor kabulu)
    durum.kristal += gelirSn();

    // 3) Aceleci oyuncu: devam eden insaatlari parayla bitirir
    if (aceleci) {
      for (const t of durum.tesisler) {
        if (t.insaatBitis === null) continue;
        const kalanDk = Math.ceil((t.insaatBitis - durum.zaman) / 60);
        const bedel = Math.max(dakikaBasinaKristal, kalanDk * dakikaBasinaKristal);
        if (durum.kristal >= bedel) {
          durum.kristal -= bedel;
          t.seviye++;
          t.insaatBitis = null;
          if (t.seviye === 10 || t.seviye === 25 || t.seviye === 50) {
            not(`${t.kod} seviye ${t.seviye} (parayla)`);
          }
        }
      }
    }

    // 4) Satin alma: karsilanabilen en yuksek degerli secenegi al, doyana kadar tekrarla
    let guvenlik = 0;
    while (guvenlik++ < 200) {
      const uygun = secenekler().filter((s) => s.maliyet <= durum.kristal);
      if (uygun.length === 0) break;

      // Deger olcutu: Kristal basina gelir artisi.
      // Gelistirmede insaat suresi de dikkate alinir — hemen gelmeyen gelir daha az degerlidir.
      const enIyi = uygun.reduce((a, b) => {
        const deger = (s) => (s.fark / s.maliyet) / (s.tur === 'gelistir' ? 1 + (s.dakika * 60) / 1800 : 1);
        return deger(b) > deger(a) ? b : a;
      });

      durum.kristal -= enIyi.maliyet;

      switch (enIyi.tur) {
        case 'gelistir':
          enIyi.tesis.insaatBitis = durum.zaman + enIyi.dakika * 60;
          break;
        case 'madenci':
          durum.madenciler[enIyi.anahtar] = (durum.madenciler[enIyi.anahtar] ?? 0) + 1;
          if ((durum.madenciler[enIyi.anahtar] ?? 0) === 1) {
            not(`ilk ${enIyi.ad} madencisi (${enIyi.tesis.kod})`);
          }
          break;
        case 'kazma':
          durum.acikKazmalar.add(enIyi.kazma.id);
          not(`${enIyi.kazma.kod} kazmasi acildi`);
          break;
        case 'tesis':
          durum.tesisler.push(enIyi.yeni);
          not(`${enIyi.tesisTuru.kod} satin alindi`);
          break;
        case 'guclendirme':
          durum.guclendirmeler[enIyi.guclendirme.id] =
            (durum.guclendirmeler[enIyi.guclendirme.id] ?? 0) + 1;
          break;
      }
    }
  }

  return { durum, gelirSn: gelirSn() };
}

// ============================================================================
// RAPOR
// ============================================================================

const sure = (sn) => {
  if (sn < 60) return sn + ' sn';
  if (sn < 3600) return Math.floor(sn / 60) + ' dk';
  const s = Math.floor(sn / 3600), d = Math.floor((sn % 3600) / 60);
  return s + ' sa' + (d ? ' ' + d + ' dk' : '');
};

const bicim = (n) => {
  if (n < 1000) return n.toFixed(0);
  if (n < 1e6) return (n / 1e3).toFixed(1) + 'B';
  if (n < 1e9) return (n / 1e6).toFixed(1) + 'M';
  if (n < 1e12) return (n / 1e9).toFixed(1) + 'Mr';
  return n.toExponential(2);
};

function rapor(baslik, sonuc, denge) {
  console.log('\n' + '='.repeat(66));
  console.log('  ' + baslik);
  console.log('='.repeat(66));

  console.log('\nKILOMETRE TASLARI');
  for (const k of sonuc.durum.kilometreTaslari) {
    console.log('  ' + sure(k.saniye).padStart(9) + '  ' + k.metin.padEnd(34) + ' gelir ' + bicim(k.gelir) + '/sn');
  }

  console.log('\nSON DURUM');
  for (const t of sonuc.durum.tesisler) {
    const md = denge.madenciler
      .map((m) => {
        const adet = sonuc.durum.madenciler[`${t.id}:${m.id}`] ?? 0;
        return adet ? m.kod + ':' + adet : null;
      })
      .filter(Boolean).join(' ');
    console.log('  ' + t.kod.padEnd(18) + ' sv ' + String(t.seviye).padStart(2) + '   ' + (md || '(madenci yok)'));
  }
  console.log('  Kristal          : ' + bicim(sonuc.durum.kristal));
  console.log('  Gelir            : ' + bicim(sonuc.gelirSn) + ' /sn');
  console.log('  Acik kazma turu  : ' + sonuc.durum.acikKazmalar.size + '/' + denge.kazmalar.length);
}

// ============================================================================
// GIRIS NOKTASI
// ============================================================================

const saat = Number(process.argv[2] ?? 24);
const mod = process.argv[3] ?? 'ikisi';

console.log('Denge verisi veritabanindan okunuyor...');
const denge = dengeyiYukle();
console.log(`Okundu: ${denge.tesisTurleri.length} tesis, ${denge.kazmalar.length} kazma, ` +
            `${denge.madenciler.length} madenci kademesi, ${denge.guclendirmeler.length} guclendirme`);
console.log(`Simulasyon suresi: ${saat} saat`);

if (mod === 'sabirli' || mod === 'ikisi') {
  rapor('SABIRLI OYUNCU (insaat surelerini bekler)', simule(denge, { saat, aceleci: false }), denge);
}
if (mod === 'aceleci' || mod === 'ikisi') {
  rapor('ACELECI OYUNCU (parayla bekleme atlar)', simule(denge, { saat, aceleci: true }), denge);
}
