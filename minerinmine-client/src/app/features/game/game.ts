import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnDestroy, OnInit, computed, effect, inject, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import {
  ClickType,
  Facility,
  Miner,
  PurchasableFacility,
  Upgrade
} from '../../core/models/game.models';
import { AuthService } from '../../core/services/auth.service';
import { GameService } from '../../core/services/game.service';
import { ChatService } from '../../core/services/chat.service';
import { ToastService } from '../../core/services/toast.service';

/**
 * MADEN EKRANI — oyunun ana dongusu.
 *
 * Ekranda gordugun hicbir sayi tarayicida hesaplanmiyor; hepsi sunucudan geliyor.
 * Tarayicinin tek isi geri sayimi akitmak ve butonlari dogru anda acmak.
 */
@Component({
  selector: 'app-game',
  imports: [RouterLink],
  templateUrl: './game.html',
  styleUrl: './game.css'
})
export class GameComponent implements OnInit, OnDestroy {
  protected readonly game = inject(GameService);
  protected readonly auth = inject(AuthService);
  protected readonly toast = inject(ToastService);
  protected readonly chat = inject(ChatService);
  private readonly router = inject(Router);

  readonly yukleniyor = signal(true);

  /**
   * SADECE olumcul durum icin: oyun durumu hic yuklenemedi, ekranda cizecek
   * bir sey yok. Gecici mesajlarin tamami artik ToastService'e gidiyor.
   */
  readonly hataMesaji = signal<string | null>(null);

  /** Islem devam ederken butonlari kilitlemek icin (cift tiklama korumasi). */
  readonly islemdeki = signal<number | null>(null);

  /**
   * SEKME DURUMU.
   *
   * Deger = gosterilen tesisin facilityTypeId'si, 0 ise Dukkan, -1 ise Sohbet.
   * (Kimlikler 1'den basladigi icin 0 ve -1 "tesis degil" anlaminda serbest.)
   *
   * NEDEN SEKME? Once butun tesisler ve dort dukkan bolumu alt alta
   * diziliyordu; iki tesiste bile ekran kaydirmadan hicbir sey gorunmuyordu.
   * Ayni anda tek bir is birimi gostermek, sayfayi ekrana sigdiriyor.
   */
  readonly aktifSekme = signal(0);

  /** Sekmede gosterilecek tesis (Dukkan sekmesindeysek null). */
  readonly aktifTesis = computed(
    () => this.game.facilities().find((t) => t.facilityTypeId === this.aktifSekme()) ?? null
  );

  /** Katlanabilir madenci listesi: tesis kimligi -> acik mi? (varsayilan acik) */
  readonly madencilerKapali = signal<Record<number, boolean>>({});

  /** Ust seritteki gezinme menusu acik mi? */
  readonly menuAcik = signal(false);

  /** Sohbet kutusuna yazilan metin. */
  readonly sohbetMetni = signal('');

  /** Sohbet sekmesi degeri — sablonda sabit sayi yazmamak icin. */
  readonly SOHBET = -1;

  /**
   * Dukkan sekmesinde su an KAC sey satin alinabilir?
   *
   * Sekmenin uzerindeki rozette gosteriliyor: oyuncu dukkani acmadan da
   * parasının yettigi bir sey oldugunu gorsun diye.
   */
  readonly dukkanFirsati = computed(() => {
    const kristal = this.kristal();
    let sayi = 0;

    for (const t of this.game.purchasable()) {
      if (t.isUnlocked && kristal >= t.cost) sayi++;
    }
    for (const g of this.game.upgrades()) {
      if (g.nextLevelCost !== null && kristal >= g.nextLevelCost) sayi++;
    }
    for (const k of this.game.clickTypes()) {
      if (!k.isUnlocked && kristal >= k.unlockCost) sayi++;
    }
    return sayi;
  });

  /** Satis panelinde secili kaynak ve miktar. */
  readonly satisMiktari = signal<Record<number, number>>({});

  /** Son kazanc — tesisin yaninda kisa sure gorunen kazanc balonu icin. */
  readonly sonKazanc = signal<{ facilityTypeId: number; miktar: number; anahtar: number } | null>(null);

  /**
   * Suresi dolup da henuz sunucuya sorulmamis tesisler icin tekrar tekrar
   * istek atmayi engelleyen kayit. Yenileme istegi gonderilen tesis buraya girer.
   */
  private readonly yenilemeIstendi = new Set<number>();

  constructor() {
    /**
     * TEMBEL TAMAMLAMANIN ARAYUZ AYAGI.
     *
     * Sunucuda arka planda calisan bir servis yok; seviye ancak bir istek
     * geldiginde artiyor. Bu yuzden geri sayim sifira dustugunde durumu
     * biz yeniliyoruz — sunucu o istegi alinca gelistirmeyi uyguluyor.
     *
     * effect(): icinde okunan sinyaller degistiginde otomatik calisir.
     * game.serverNow() saniyede dort kez degistigi icin bu kontrol surekli
     * yapilmis oluyor; ayri bir zamanlayici gerekmiyor.
     */
    effect(() => {
      for (const tesis of this.game.facilities()) {
        if (this.game.isUpgradeDue(tesis) && !this.yenilemeIstendi.has(tesis.facilityTypeId)) {
          this.yenilemeIstendi.add(tesis.facilityTypeId);
          this.durumuYenile();
        }
      }
    });
  }

  ngOnInit(): void {
    this.durumuYenile(true);
  }

  /**
   * Oyun ekranindan cikilinca WebSocket baglantisini kapatiyoruz.
   *
   * Kapatmasaydik kullanici siralama/istatistik sayfalarina gectiginde
   * baglanti acik kalir, sunucuda bosuna kaynak tutardi. Bilesen yok
   * olurken temizlik yapmak, abonelik ve baglanti tutan her yerde kuraldir.
   */
  ngOnDestroy(): void {
    void this.chat.kapat();
  }

  private durumuYenile(ilk = false): void {
    this.game.loadState().subscribe({
      next: (durum) => {
        this.yukleniyor.set(false);

        // Sunucu bu istekte kac gelistirme tamamladigini soyluyor.
        if (durum.completedUpgrades > 0) {
          this.toast.basari(
            durum.completedUpgrades === 1
              ? 'Geliştirme tamamlandı!'
              : durum.completedUpgrades + ' geliştirme tamamlandı!'
          );
        }

        // Ilk yuklemede sekme henuz secilmemistir: ilk tesisi ac.
        if (ilk && durum.facilities.length > 0) {
          this.aktifSekme.set(durum.facilities[0].facilityTypeId);
        }

        // Tamamlanan tesisler icin kaydi temizle ki yeni gelistirmede tekrar calissin.
        for (const tesis of durum.facilities) {
          if (!tesis.upgradeCompletesAt) {
            this.yenilemeIstendi.delete(tesis.facilityTypeId);
          }
        }
      },
      error: (hata: HttpErrorResponse) => {
        this.yukleniyor.set(false);
        const mesaj = this.hatayiCozumle(hata, 'Oyun durumu alınamadı.');
        if (ilk) {
          this.hataMesaji.set(mesaj);   // ekranda cizecek hicbir sey yok
        } else {
          this.toast.hata(mesaj);
        }
      }
    });
  }

  kaz(facility: Facility, click: ClickType): void {
    if (!this.game.isReady(facility.facilityTypeId, click.clickTypeId)) {
      return;
    }

    this.game
      .mine({ facilityTypeId: facility.facilityTypeId, clickTypeId: click.clickTypeId })
      .subscribe({
        next: (sonuc) => {
          this.sonKazanc.set({
            facilityTypeId: facility.facilityTypeId,
            miktar: sonuc.gained,
            anahtar: Date.now()
          });
        },
        error: (hata: HttpErrorResponse) => {
          this.toast.hata(this.hatayiCozumle(hata, 'Kazma yapılamadı.'));
          this.durumuYenile();
        }
      });
  }

  // ==========================================================================
  // GELISTIRME
  // ==========================================================================

  gelistir(facility: Facility): void {
    this.islemdeki.set(facility.facilityTypeId);
    this.game.startUpgrade(facility.facilityTypeId).subscribe({
      next: (sonuc) => {
        this.islemdeki.set(null);
        this.toast.bilgi(
          facility.name + ' seviye ' + sonuc.targetLevel + ' çalışması başladı (' +
          sonuc.durationMinutes + ' dk).'
        );
        this.durumuYenile();
      },
      error: (hata: HttpErrorResponse) => {
        this.islemdeki.set(null);
        this.toast.hata(this.hatayiCozumle(hata, 'Geliştirme başlatılamadı.'));
        this.durumuYenile();
      }
    });
  }

  hemenBitir(facility: Facility): void {
    this.islemdeki.set(facility.facilityTypeId);
    this.game.finishUpgradeNow(facility.facilityTypeId).subscribe({
      next: (sonuc) => {
        this.islemdeki.set(null);
        const dakika = Math.max(1, Math.round(sonuc.skippedSeconds / 60));
        this.toast.basari(
          facility.name + ' seviye ' + sonuc.newLevel + ' oldu. ' +
          dakika + ' dakika beklemekten kurtuldun. ' +
          'Bugün kalan hızlandırma hakkın: ' + sonuc.remainingSkips
        );
        this.durumuYenile();
      },
      error: (hata: HttpErrorResponse) => {
        this.islemdeki.set(null);
        this.toast.hata(this.hatayiCozumle(hata, 'İşlem tamamlanamadı.'));
        this.durumuYenile();
      }
    });
  }

  // ==========================================================================
  // GORUNTULEME YARDIMCILARI
  // ==========================================================================

  /** Kazma bekleme suresi: "0.9 sn" */
  kalanMetin(facilityTypeId: number, clickTypeId: number): string {
    const ms = this.game.remainingMs(facilityTypeId, clickTypeId);
    return ms === 0 ? '' : (ms / 1000).toFixed(1) + ' sn';
  }

  ilerleme(facilityTypeId: number, clickTypeId: number, cooldownSeconds: number): number {
    const kalan = this.game.remainingMs(facilityTypeId, clickTypeId);
    if (kalan === 0) {
      return 100;
    }
    return 100 - (kalan / (cooldownSeconds * 1000)) * 100;
  }

  /** Gelistirme geri sayimi: "04:12" ya da "1:02:30" */
  gelistirmeKalan(facility: Facility): string {
    const toplamSaniye = Math.ceil(this.game.upgradeRemainingMs(facility) / 1000);
    if (toplamSaniye <= 0) {
      return 'tamamlanıyor...';
    }

    const saat = Math.floor(toplamSaniye / 3600);
    const dakika = Math.floor((toplamSaniye % 3600) / 60);
    const saniye = toplamSaniye % 60;
    const ikiHane = (n: number) => String(n).padStart(2, '0');

    return saat > 0
      ? saat + ':' + ikiHane(dakika) + ':' + ikiHane(saniye)
      : ikiHane(dakika) + ':' + ikiHane(saniye);
  }

  /** Bu tesis icin gelistirme butonu aktif olmali mi? */
  gelistirilebilir(facility: Facility): boolean {
    if (facility.upgradeCompletesAt || facility.nextLevelCost === null) {
      return false;   // zaten gelistiriliyor ya da son seviye
    }
    return this.kristal() >= facility.nextLevelCost;
  }

  sekmeSec(deger: number): void {
    this.aktifSekme.set(deger);

    if (deger === this.SOHBET) {
      // Baglanti SADECE sohbet sekmesi ilk acildiginda kuruluyor.
      // Herkesi oyuna girer girmez baglamak, sohbeti hic acmayacak
      // oyuncular icin bosuna acik bir WebSocket demek olurdu.
      void this.chat.baglan();
      this.chat.ekraniAc();
    } else {
      // Baska sekmeye gecildi: baglanti duruyor ama gelen mesajlar artik
      // okunmamis sayiliyor ve sekme rozetinde birikiyor.
      this.chat.ekraniKapat();
    }
  }

  sohbetMetniDegisti(olay: Event): void {
    this.sohbetMetni.set((olay.target as HTMLInputElement).value);
  }

  async sohbetGonder(): Promise<void> {
    const metin = this.sohbetMetni();
    if (!metin.trim()) {
      return;
    }

    this.sohbetMetni.set('');
    await this.chat.gonder(metin);
  }

  /** Mesaj bana mi ait? (arayuz kendi mesajlarimi farkli hizalar) */
  benimMesajim(userId: number): boolean {
    return this.auth.userId() === userId;
  }

  /** Sohbet saati: "14:32" */
  mesajSaati(iso: string): string {
    const d = new Date(iso.endsWith('Z') ? iso : iso + 'Z');
    return d.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });
  }

  menuyuAcKapat(): void {
    this.menuAcik.update((a) => !a);
  }

  menuyuKapat(): void {
    this.menuAcik.set(false);
  }

  madencileriKatla(facilityTypeId: number): void {
    this.madencilerKapali.update((m) => ({ ...m, [facilityTypeId]: !m[facilityTypeId] }));
  }

  madencilerAcikMi(facilityTypeId: number): boolean {
    return !this.madencilerKapali()[facilityTypeId];
  }

  /** Bu tesiste su an ise alinabilecek madenci var mi? (katliyken bile bilinsin) */
  madenciFirsati(facilityTypeId: number): number {
    const kristal = this.kristal();
    return this.game
      .minersOf(facilityTypeId)
      .filter((m) => m.isAvailable && m.count < m.maxCount && kristal >= m.hireCost).length;
  }

  kristal(): number {
    return this.game.resources().find((r) => r.code === 'KRISTAL')?.amount ?? 0;
  }

  /** 47115 -> "47,1B". Veri hep tam sayi kalir; bu yalnizca goruntuleme katmani. */
  bicimle(sayi: number): string {
    if (sayi < 1000) return String(sayi);
    if (sayi < 1000000) return (sayi / 1000).toFixed(1).replace('.', ',') + 'B';
    if (sayi < 1000000000) return (sayi / 1000000).toFixed(1).replace('.', ',') + 'M';
    return (sayi / 1000000000).toFixed(1).replace('.', ',') + 'Mr';
  }

  private hatayiCozumle(hata: HttpErrorResponse, varsayilan: string): string {
    if (hata.status === 0) {
      return 'Sunucuya ulaşılamıyor. API çalışıyor mu? (http://localhost:5080)';
    }
    return hata.error?.message ?? varsayilan;
  }

  cikisYap(): void {
    this.auth.logout();
    this.router.navigateByUrl('/login');
  }

  // ==========================================================================
  // OTOMASYON VE EKONOMI
  // ==========================================================================

  topla(): void {
    this.game.collect().subscribe({
      next: (kaynaklar) => {
        if (kaynaklar.length === 0) {
          this.toast.bilgi('Toplanacak bir şey yok. Madenci alarak üretimi otomatikleştirebilirsin.');
        } else {
          this.toast.basari(
            'Toplandı: ' + kaynaklar.map((k) => '+' + this.bicimle(k.amount) + ' ' + k.name).join(', ')
          );
        }
        this.durumuYenile();
      },
      error: (hata: HttpErrorResponse) => {
        this.toast.hata(this.hatayiCozumle(hata, 'Toplama başarısız.'));
      }
    });
  }

  madenciAl(madenci: Miner): void {
    this.islemdeki.set(madenci.minerTypeId);
    this.game.hireMiner(madenci.facilityTypeId, madenci.minerTypeId).subscribe({
      next: (sonuc) => {
        this.islemdeki.set(null);
        this.toast.basari(madenci.name + ' işe alındı. Toplam: ' + sonuc.newCount);
        this.durumuYenile();
      },
      error: (hata: HttpErrorResponse) => {
        this.islemdeki.set(null);
        this.toast.hata(this.hatayiCozumle(hata, 'Madenci işe alınamadı.'));
        this.durumuYenile();
      }
    });
  }

  kazmaAc(kazma: ClickType): void {
    this.islemdeki.set(kazma.clickTypeId);
    this.game.unlockClick(kazma.clickTypeId).subscribe({
      next: () => {
        this.islemdeki.set(null);
        this.toast.basari(kazma.name + ' açıldı! Artık madencisini de işe alabilirsin.');
        this.durumuYenile();
      },
      error: (hata: HttpErrorResponse) => {
        this.islemdeki.set(null);
        this.toast.hata(this.hatayiCozumle(hata, 'Kazma türü açılamadı.'));
        this.durumuYenile();
      }
    });
  }

  guclendirmeAl(guclendirme: Upgrade): void {
    this.islemdeki.set(guclendirme.upgradeTypeId);
    this.game.buyUpgrade(guclendirme.upgradeTypeId).subscribe({
      next: (sonuc) => {
        this.islemdeki.set(null);
        this.toast.basari(guclendirme.name + ' seviye ' + sonuc.newLevel + ' oldu.');
        this.durumuYenile();
      },
      error: (hata: HttpErrorResponse) => {
        this.islemdeki.set(null);
        this.toast.hata(this.hatayiCozumle(hata, 'Güçlendirme alınamadı.'));
        this.durumuYenile();
      }
    });
  }

  sat(resourceTypeId: number, tumu: number): void {
    const miktar = this.satisMiktari()[resourceTypeId] ?? tumu;
    if (miktar <= 0) {
      return;
    }

    this.islemdeki.set(resourceTypeId);
    this.game.sell({ resourceTypeId, amount: miktar }).subscribe({
      next: (sonuc) => {
        this.islemdeki.set(null);
        this.toast.basari(
          this.bicimle(sonuc.soldAmount) + ' satıldı, +' + this.bicimle(sonuc.earned) + ' Kristal.'
        );
        this.satisMiktari.set({});
        this.durumuYenile();
      },
      error: (hata: HttpErrorResponse) => {
        this.islemdeki.set(null);
        this.toast.hata(this.hatayiCozumle(hata, 'Satış yapılamadı.'));
        this.durumuYenile();
      }
    });
  }

  miktarDegisti(resourceTypeId: number, olay: Event): void {
    const deger = Number((olay.target as HTMLInputElement).value);
    this.satisMiktari.update((m) => ({ ...m, [resourceTypeId]: deger }));
  }

  /**
   * Reklam izleyip Kristal kazanir (gelistirme ortaminda simule edilir).
   *
   * Sunucu ayni bildirimi ikinci kez islemez (idempotency); o durumda
   * alreadyProcessed=true doner ve odul tekrar verilmez.
   */
  reklamIzle(): void {
    this.islemdeki.set(-1);
    this.game.watchAd().subscribe({
      next: (sonuc) => {
        this.islemdeki.set(null);
        if (sonuc.alreadyProcessed) {
          this.toast.bilgi('Bu ödül zaten verilmiş.');
        } else {
          this.toast.basari('+' + this.bicimle(sonuc.amount) + ' Kristal kazandın!');
        }
        this.durumuYenile();
      },
      error: (hata: HttpErrorResponse) => {
        this.islemdeki.set(null);
        this.toast.hata(this.hatayiCozumle(hata, 'Ödül alınamadı.'));
      }
    });
  }

  /**
   * Yeni tesis satin alir.
   *
   * Buton yalnizca on kosul saglandiginda ve Kristal yettiginde aktif olur;
   * ama asil dogrulama sunucuda yapilir.
   */
  tesisAl(tesis: PurchasableFacility): void {
    // Negatif deger kullaniyoruz ki madenci/guclendirme kimlikleriyle cakismasin.
    this.islemdeki.set(-tesis.facilityTypeId);
    this.game.buyFacility(tesis.facilityTypeId).subscribe({
      next: (sonuc) => {
        this.islemdeki.set(null);
        this.toast.basari(
          sonuc.facilityName + ' açıldı! Artık ' + tesis.resourceName + ' de çıkarabilirsin.'
        );
        this.aktifSekme.set(tesis.facilityTypeId);   // yeni tesisi hemen goster
        this.durumuYenile();
      },
      error: (hata: HttpErrorResponse) => {
        this.islemdeki.set(null);
        this.toast.hata(this.hatayiCozumle(hata, 'Tesis satın alınamadı.'));
        this.durumuYenile();
      }
    });
  }

  /** Tesis satin alma butonu aktif olmali mi? */
  tesisAlinabilir(tesis: PurchasableFacility): boolean {
    return tesis.isUnlocked && this.kristal() >= tesis.cost;
  }

  /** Satilabilir kaynaklar: para birimi olmayan ve elde bulunanlar. */
  satilabilirler() {
    return this.game.resources().filter((r) => !r.isCurrency && r.amount > 0);
  }

  /**
   * Bekleyen uretimi ozet metne cevirir.
   *
   * Sunucudan gelen anlik degeri degil, istemcide akan TAHMINI kullaniyoruz ki
   * sayac ekranda dursun degil aksin. Gercek miktar toplama aninda sunucudan gelir.
   */
  bekleyenMetin(): string {
    return this.game.estimatedPending()
      .filter((p) => p.amount > 0)
      .map((p) => this.bicimle(p.amount) + ' ' + p.name)
      .join(' · ');
  }
}
