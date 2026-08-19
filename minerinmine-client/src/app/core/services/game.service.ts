import { HttpClient } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { Observable, tap } from 'rxjs';
import { environment } from '../../../environments/environment';
import {
  BuyFacilityResult,
  CollectedResource,
  Facility,
  HireMinerResult,
  MineRequest,
  MineResult,
  PlayerState,
  PlayerStats,
  PurchaseResult,
  SellRequest,
  SellResult,
  UnlockResult,
  UpgradeFinished,
  UpgradeStarted
} from '../models/game.models';
import { AdRewardResult } from '../models/meta.models';

/**
 * Oyun durumunu tutan ve API ile konusan servis.
 *
 * SAAT FARKI DUZELTMESI (clock offset):
 * Kullanicinin bilgisayar saati yanlis olabilir — dakikalarca ileri ya da geri.
 * Geri sayimi ham `Date.now()` ile hesaplasaydik, saati 5 dakika geri olan
 * kullanicida buton hep "hazir degil" gorunurdu.
 *
 * Bu yuzden sunucu her cevapta kendi saatini de gonderiyor. Aradaki farki
 * bir kez olcup tum hesaplara ekliyoruz:
 *
 *     offset       = sunucuSaati - istemciSaati
 *     sunucuSimdi  = Date.now() + offset
 *
 * Sunucu saati her zaman TEK DOGRU referanstir.
 */
@Injectable({ providedIn: 'root' })
export class GameService {
  private readonly http = inject(HttpClient);
  private readonly apiUrl = `${environment.apiUrl}/game`;

  /** Sunucudan gelen en son oyun durumu. */
  private readonly _state = signal<PlayerState | null>(null);
  readonly state = this._state.asReadonly();

  /** Sunucu saati ile istemci saati arasindaki fark (milisaniye). */
  private readonly _clockOffset = signal(0);

  /**
   * Geri sayimlarin akmasi icin saniyede bir guncellenen "simdi" sinyali.
   * Sablonlar bunu okudugu icin, degeri her degistiginde ekran kendiliginden yenilenir.
   */
  private readonly _tick = signal(Date.now());

  /** Sunucu saatine gore duzeltilmis simdiki zaman. */
  readonly serverNow = computed(() => this._tick() + this._clockOffset());

  readonly resources = computed(() => this._state()?.resources ?? []);
  readonly facilities = computed(() => this._state()?.facilities ?? []);
  readonly clickTypes = computed(() => this._state()?.clickTypes ?? []);

  /** Yalnizca acilmis kazma turleri — butonlar bunlardan cizilir. */
  readonly unlockedClicks = computed(() => this.clickTypes().filter((c) => c.isUnlocked));

  readonly miners = computed(() => this._state()?.miners ?? []);
  readonly upgrades = computed(() => this._state()?.upgrades ?? []);
  readonly pending = computed(() => this._state()?.pending ?? []);
  readonly purchasable = computed(() => this._state()?.purchasable ?? []);

  /** Toplam saniyelik otomatik uretim — ust seritte gosterilir. */
  readonly totalPerSecond = computed(() =>
    this.facilities().reduce((toplam, f) => toplam + Number(f.autoPerSecond ?? 0), 0)
  );

  /**
   * BEKLEYEN URETIM TAHMINI (yalnizca goruntuleme icin).
   *
   * Sunucudan gelen `pending` degeri, durumun cekildigi ANA aittir; oyuncu
   * ekranda beklerken artmaz. Saniyede bir sunucuya sormak ise gereksiz trafik
   * olurdu. Bunun yerine ayni formulu istemcide calistirip sayacin akmasini
   * sagliyoruz:
   *
   *     tahmin = autoPerSecond x (simdi - lastCollectedAt)
   *
   * DIKKAT: Bu sayi HICBIR ZAMAN otorite degildir. "Topla" butonuna
   * basildiginda sunucu kendi hesabini yapar ve gercek miktari o belirler.
   * Istemci yalnizca butonu ne zaman aktif edecegini ve ekranda ne
   * gosterecegini bilmek icin tahmin yurutur.
   */
  readonly estimatedPending = computed(() => {
    const state = this._state();
    if (!state) {
      return [] as { code: string; name: string; amount: number }[];
    }

    // Sunucudaki OFFLINE_CAP_HOURS ayarinin ekran karsiligi.
    const tavanMs = 8 * 3600 * 1000;
    const toplam = new Map<string, { code: string; name: string; amount: number }>();

    for (const tesis of state.facilities) {
      const hiz = Number(tesis.autoPerSecond ?? 0);
      if (hiz <= 0) {
        continue;
      }

      let gecen = this.serverNow() - this.toEpoch(tesis.lastCollectedAt);
      if (gecen < 0) gecen = 0;
      if (gecen > tavanMs) gecen = tavanMs;

      const miktar = Math.floor((hiz * gecen) / 1000);
      if (miktar <= 0) {
        continue;
      }

      const mevcut = toplam.get(tesis.resourceCode);
      if (mevcut) {
        mevcut.amount += miktar;
      } else {
        toplam.set(tesis.resourceCode, {
          code: tesis.resourceCode,
          name: tesis.resourceName,
          amount: miktar
        });
      }
    }

    return [...toplam.values()];
  });

  /** Toplanmayi bekleyen bir sey var mi? (tahmine gore) */
  readonly hasPending = computed(() => this.estimatedPending().some((p) => p.amount > 0));

  /** Belirli bir tesise ait madenci kademeleri. */
  minersOf(facilityTypeId: number) {
    return this.miners().filter((m) => m.facilityTypeId === facilityTypeId);
  }

  constructor() {
    // Tek bir zamanlayici tum geri sayimlari besler.
    // Her buton kendi setInterval'ini kursaydi 12 tesis x 4 kazma = 48 zamanlayici olurdu.
    setInterval(() => this._tick.set(Date.now()), 250);
  }

  /** Oyun durumunu sunucudan ceker. */
  loadState(): Observable<PlayerState> {
    return this.http.get<PlayerState>(`${this.apiUrl}/state`).pipe(
      tap((state) => {
        this._state.set(state);
        this.syncClock(state.serverTime);
      })
    );
  }

  /**
   * Kazma yapar.
   *
   * Cevap gelince kaynak miktarini ve bekleme suresini SUNUCUNUN dondurdugu
   * degerlerle guncelliyoruz — kendi tahminimizle degil. Tum ekran tek dogru
   * kaynaga (sunucuya) bagli kalir.
   */
  mine(request: MineRequest): Observable<MineResult> {
    return this.http.post<MineResult>(`${this.apiUrl}/mine`, request).pipe(
      tap((result) => {
        this.syncClock(result.serverTime);
        this.applyMineResult(request, result);
      })
    );
  }

  /**
   * Belirli bir tesis + kazma turu icin kalan bekleme suresi (milisaniye).
   * 0 ise kazma hazirdir.
   */
  remainingMs(facilityTypeId: number, clickTypeId: number): number {
    const fc = this._state()?.facilityClicks.find(
      (x) => x.facilityTypeId === facilityTypeId && x.clickTypeId === clickTypeId
    );

    if (!fc) {
      return 0;
    }

    const kalan = this.toEpoch(fc.nextAvailableAt) - this.serverNow();
    return kalan > 0 ? kalan : 0;
  }

  isReady(facilityTypeId: number, clickTypeId: number): boolean {
    return this.remainingMs(facilityTypeId, clickTypeId) === 0;
  }

  // ==========================================================================
  // Yardimcilar
  // ==========================================================================

  /**
   * Backend tarihleri UTC uretir ama sonuna 'Z' eklemez ("2026-08-17T11:38:09").
   * JavaScript bu bicimi YEREL saat sanar. Sonu 'Z' ile bitmiyorsa ekliyoruz ki
   * dogru yorumlansin — aksi halde saat farki kadar kayma olurdu.
   */
  private toEpoch(utcText: string): number {
    const normalized = utcText.endsWith('Z') ? utcText : `${utcText}Z`;
    return new Date(normalized).getTime();
  }

  private syncClock(serverTime: string): void {
    this._clockOffset.set(this.toEpoch(serverTime) - Date.now());
  }

  /** Kazma sonucunu yerel duruma isler (yeniden istek atmadan). */
  private applyMineResult(request: MineRequest, result: MineResult): void {
    this._state.update((state) => {
      if (!state) {
        return state;
      }

      return {
        ...state,
        resources: state.resources.map((r) =>
          r.resourceTypeId === result.resourceTypeId ? { ...r, amount: result.newBalance } : r
        ),
        facilityClicks: state.facilityClicks.map((fc) =>
          fc.facilityTypeId === request.facilityTypeId && fc.clickTypeId === request.clickTypeId
            ? { ...fc, lastClickAt: result.serverTime, nextAvailableAt: result.nextAvailableAt }
            : fc
        )
      };
    });
  }

  // ==========================================================================
  // TESIS GELISTIRME
  // ==========================================================================

  /**
   * Gelistirme baslatir.
   *
   * Maliyet ve sure GONDERILMEZ; sunucu denge tablosundan okur. Istemcinin
   * ekranda gosterdigi fiyat sadece bilgilendirmedir, karar sunucunundur.
   */
  startUpgrade(facilityTypeId: number): Observable<UpgradeStarted> {
    return this.http
      .post<UpgradeStarted>(`${this.apiUrl}/facility/${facilityTypeId}/upgrade`, {})
      .pipe(tap((r) => this.syncClock(r.serverTime)));
  }

  /** Devam eden gelistirmeyi Kristal odeyerek aninda bitirir. */
  finishUpgradeNow(facilityTypeId: number): Observable<UpgradeFinished> {
    return this.http
      .post<UpgradeFinished>(`${this.apiUrl}/facility/${facilityTypeId}/finish-now`, {})
      .pipe(tap((r) => this.syncClock(r.serverTime)));
  }

  /**
   * Devam eden gelistirmenin kalan suresi (milisaniye). Gelistirme yoksa 0.
   *
   * Bu deger _tick sinyaline bagli oldugu icin saniyede dort kez yeniden
   * hesaplanir ve ekran kendiliginden akar.
   */
  upgradeRemainingMs(facility: Facility): number {
    if (!facility.upgradeCompletesAt) {
      return 0;
    }

    const kalan = this.toEpoch(facility.upgradeCompletesAt) - this.serverNow();
    return kalan > 0 ? kalan : 0;
  }

  /**
   * Gelistirme suresi doldu mu?
   *
   * DIKKAT: Bu yalnizca ARAYUZ tahminidir. Seviyenin gercekten artmasi icin
   * sunucuya istek atilmasi gerekir (tembel tamamlama) — bileşen bu deger
   * true olunca loadState() cagirir ve sunucu gelistirmeyi o an uygular.
   */
  isUpgradeDue(facility: Facility): boolean {
    return facility.upgradeCompletesAt !== null && this.upgradeRemainingMs(facility) === 0;
  }

  /** Gelistirmenin yuzde kaci tamamlandi (ilerleme cubugu icin). */
  upgradeProgress(facility: Facility): number {
    if (!facility.upgradeCompletesAt || !facility.nextLevelMinutes) {
      return 0;
    }

    const toplamMs = facility.nextLevelMinutes * 60 * 1000;
    const kalanMs = this.upgradeRemainingMs(facility);
    const yuzde = 100 - (kalanMs / toplamMs) * 100;

    return Math.max(0, Math.min(100, yuzde));
  }

  // ==========================================================================
  // OTOMASYON VE EKONOMI
  // ==========================================================================

  /**
   * Birikmis uretimi toplar.
   *
   * Miktar GONDERILMEZ; sunucu "simdi - son toplama" suresinden hesaplar.
   * Es zamanli iki istek gelse bile uretim yalnizca bir kez eklenir.
   */
  collect(): Observable<CollectedResource[]> {
    return this.http.post<CollectedResource[]>(`${this.apiUrl}/collect`, {});
  }

  hireMiner(facilityTypeId: number, minerTypeId: number): Observable<HireMinerResult> {
    return this.http
      .post<HireMinerResult>(`${this.apiUrl}/facility/${facilityTypeId}/miner/${minerTypeId}`, {})
      .pipe(tap((r) => this.syncClock(r.serverTime)));
  }

  sell(request: SellRequest): Observable<SellResult> {
    return this.http
      .post<SellResult>(`${this.apiUrl}/sell`, request)
      .pipe(tap((r) => this.syncClock(r.serverTime)));
  }

  buyUpgrade(upgradeTypeId: number): Observable<PurchaseResult> {
    return this.http
      .post<PurchaseResult>(`${this.apiUrl}/upgrade/${upgradeTypeId}`, {})
      .pipe(tap((r) => this.syncClock(r.serverTime)));
  }

  /**
   * Reklam izlemeyi simule eder (yalnizca gelistirme ortaminda calisir).
   *
   * GERCEK DUNYADA bu uc BULUNMAZ: reklam agi izleme bitince dogrudan
   * sunucumuza imzali bir bildirim gonderir ve istemci akisin icinde yer almaz.
   * Istemcinin "odul ver" diyebildigi bir uc, odulun taklit edilebilmesi demektir.
   */
  watchAd(): Observable<AdRewardResult> {
    return this.http.post<AdRewardResult>(`${environment.apiUrl}/ads/simulate-watch`, {});
  }

  /**
   * Yeni tesis satin alir.
   *
   * Fiyat GONDERILMEZ; sunucu denge tablosundan okur ve on kosulu kendisi
   * dogrular. Arayuzdeki kilit gostergesi yalnizca bilgilendirmedir.
   */
  buyFacility(facilityTypeId: number): Observable<BuyFacilityResult> {
    return this.http
      .post<BuyFacilityResult>(`${this.apiUrl}/facility/${facilityTypeId}/buy`, {})
      .pipe(tap((r) => this.syncClock(r.serverTime)));
  }

  unlockClick(clickTypeId: number): Observable<UnlockResult> {
    return this.http
      .post<UnlockResult>(`${this.apiUrl}/click/${clickTypeId}/unlock`, {})
      .pipe(tap((r) => this.syncClock(r.serverTime)));
  }

  /**
   * Oynanis istatistikleri (istatistik ekrani).
   *
   * Bu istegin sonucu _state sinyaline YAZILMAZ: rapor niteliginde, tek
   * seferlik bir veri. Oyun ekraninin akan durumuyla karistirmiyoruz.
   */
  getStats(): Observable<PlayerStats> {
    return this.http.get<PlayerStats>(`${this.apiUrl}/stats`);
  }
}
