import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, effect, inject, signal } from '@angular/core';
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
export class GameComponent implements OnInit {
  protected readonly game = inject(GameService);
  protected readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  readonly yukleniyor = signal(true);
  readonly hataMesaji = signal<string | null>(null);
  readonly bilgiMesaji = signal<string | null>(null);

  /** Islem devam ederken butonlari kilitlemek icin (cift tiklama korumasi). */
  readonly islemdeki = signal<number | null>(null);

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

  private durumuYenile(ilk = false): void {
    this.game.loadState().subscribe({
      next: (durum) => {
        this.yukleniyor.set(false);

        // Sunucu bu istekte kac gelistirme tamamladigini soyluyor.
        if (durum.completedUpgrades > 0) {
          this.bilgiMesaji.set(
            durum.completedUpgrades === 1
              ? 'Geliştirme tamamlandı!'
              : durum.completedUpgrades + ' geliştirme tamamlandı!'
          );
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
        if (ilk) {
          this.hataMesaji.set(this.hatayiCozumle(hata, 'Oyun durumu alınamadı.'));
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
          this.hataMesaji.set(null);
          this.sonKazanc.set({
            facilityTypeId: facility.facilityTypeId,
            miktar: sonuc.gained,
            anahtar: Date.now()
          });
        },
        error: (hata: HttpErrorResponse) => {
          this.hataMesaji.set(this.hatayiCozumle(hata, 'Kazma yapılamadı.'));
          this.durumuYenile();
        }
      });
  }

  // ==========================================================================
  // GELISTIRME
  // ==========================================================================

  gelistir(facility: Facility): void {
    this.islemdeki.set(facility.facilityTypeId);
    this.hataMesaji.set(null);
    this.bilgiMesaji.set(null);

    this.game.startUpgrade(facility.facilityTypeId).subscribe({
      next: (sonuc) => {
        this.islemdeki.set(null);
        this.bilgiMesaji.set(
          facility.name + ' seviye ' + sonuc.targetLevel + ' calismasi basladi (' +
          sonuc.durationMinutes + ' dk).'
        );
        this.durumuYenile();
      },
      error: (hata: HttpErrorResponse) => {
        this.islemdeki.set(null);
        this.hataMesaji.set(this.hatayiCozumle(hata, 'Geliştirme başlatılamadı.'));
        this.durumuYenile();
      }
    });
  }

  hemenBitir(facility: Facility): void {
    this.islemdeki.set(facility.facilityTypeId);
    this.hataMesaji.set(null);
    this.bilgiMesaji.set(null);

    this.game.finishUpgradeNow(facility.facilityTypeId).subscribe({
      next: (sonuc) => {
        this.islemdeki.set(null);
        const dakika = Math.max(1, Math.round(sonuc.skippedSeconds / 60));
        this.bilgiMesaji.set(
          facility.name + ' seviye ' + sonuc.newLevel + ' oldu. ' +
          dakika + ' dakika beklemekten kurtuldun. ' +
          'Bugün kalan hızlandırma hakkın: ' + sonuc.remainingSkips
        );
        this.durumuYenile();
      },
      error: (hata: HttpErrorResponse) => {
        this.islemdeki.set(null);
        this.hataMesaji.set(this.hatayiCozumle(hata, 'İşlem tamamlanamadı.'));
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
    this.hataMesaji.set(null);

    this.game.collect().subscribe({
      next: (kaynaklar) => {
        if (kaynaklar.length === 0) {
          this.bilgiMesaji.set('Toplanacak bir şey yok. Madenci alarak üretimi otomatikleştirebilirsin.');
        } else {
          this.bilgiMesaji.set(
            'Toplandı: ' + kaynaklar.map((k) => '+' + this.bicimle(k.amount) + ' ' + k.name).join(', ')
          );
        }
        this.durumuYenile();
      },
      error: (hata: HttpErrorResponse) => {
        this.hataMesaji.set(this.hatayiCozumle(hata, 'Toplama başarısız.'));
      }
    });
  }

  madenciAl(madenci: Miner): void {
    this.islemdeki.set(madenci.minerTypeId);
    this.hataMesaji.set(null);
    this.bilgiMesaji.set(null);

    this.game.hireMiner(madenci.facilityTypeId, madenci.minerTypeId).subscribe({
      next: (sonuc) => {
        this.islemdeki.set(null);
        this.bilgiMesaji.set(madenci.name + ' işe alındı. Toplam: ' + sonuc.newCount);
        this.durumuYenile();
      },
      error: (hata: HttpErrorResponse) => {
        this.islemdeki.set(null);
        this.hataMesaji.set(this.hatayiCozumle(hata, 'Madenci işe alınamadı.'));
        this.durumuYenile();
      }
    });
  }

  kazmaAc(kazma: ClickType): void {
    this.islemdeki.set(kazma.clickTypeId);
    this.hataMesaji.set(null);
    this.bilgiMesaji.set(null);

    this.game.unlockClick(kazma.clickTypeId).subscribe({
      next: () => {
        this.islemdeki.set(null);
        this.bilgiMesaji.set(kazma.name + ' açıldı! Artık madencisini de işe alabilirsin.');
        this.durumuYenile();
      },
      error: (hata: HttpErrorResponse) => {
        this.islemdeki.set(null);
        this.hataMesaji.set(this.hatayiCozumle(hata, 'Kazma türü açılamadı.'));
        this.durumuYenile();
      }
    });
  }

  guclendirmeAl(guclendirme: Upgrade): void {
    this.islemdeki.set(guclendirme.upgradeTypeId);
    this.hataMesaji.set(null);
    this.bilgiMesaji.set(null);

    this.game.buyUpgrade(guclendirme.upgradeTypeId).subscribe({
      next: (sonuc) => {
        this.islemdeki.set(null);
        this.bilgiMesaji.set(guclendirme.name + ' seviye ' + sonuc.newLevel + ' oldu.');
        this.durumuYenile();
      },
      error: (hata: HttpErrorResponse) => {
        this.islemdeki.set(null);
        this.hataMesaji.set(this.hatayiCozumle(hata, 'Güçlendirme alınamadı.'));
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
    this.hataMesaji.set(null);
    this.bilgiMesaji.set(null);

    this.game.sell({ resourceTypeId, amount: miktar }).subscribe({
      next: (sonuc) => {
        this.islemdeki.set(null);
        this.bilgiMesaji.set(
          this.bicimle(sonuc.soldAmount) + ' satıldı, +' + this.bicimle(sonuc.earned) + ' Kristal.'
        );
        this.satisMiktari.set({});
        this.durumuYenile();
      },
      error: (hata: HttpErrorResponse) => {
        this.islemdeki.set(null);
        this.hataMesaji.set(this.hatayiCozumle(hata, 'Satış yapılamadı.'));
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
    this.hataMesaji.set(null);
    this.bilgiMesaji.set(null);

    this.game.watchAd().subscribe({
      next: (sonuc) => {
        this.islemdeki.set(null);
        this.bilgiMesaji.set(
          sonuc.alreadyProcessed
            ? 'Bu ödül zaten verilmiş.'
            : '+' + this.bicimle(sonuc.amount) + ' Kristal kazandın!'
        );
        this.durumuYenile();
      },
      error: (hata: HttpErrorResponse) => {
        this.islemdeki.set(null);
        this.hataMesaji.set(this.hatayiCozumle(hata, 'Ödül alınamadı.'));
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
    this.hataMesaji.set(null);
    this.bilgiMesaji.set(null);

    this.game.buyFacility(tesis.facilityTypeId).subscribe({
      next: (sonuc) => {
        this.islemdeki.set(null);
        this.bilgiMesaji.set(
          sonuc.facilityName + ' açıldı! Artık ' + tesis.resourceName + ' de çıkarabilirsin.'
        );
        this.durumuYenile();
      },
      error: (hata: HttpErrorResponse) => {
        this.islemdeki.set(null);
        this.hataMesaji.set(this.hatayiCozumle(hata, 'Tesis satın alınamadı.'));
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
