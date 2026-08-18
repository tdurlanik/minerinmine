import { HttpClient } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { Observable, tap } from 'rxjs';
import { environment } from '../../../environments/environment';
import {
  Facility,
  MineRequest,
  MineResult,
  PlayerState,
  UpgradeFinished,
  UpgradeStarted
} from '../models/game.models';

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
}
