import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { ClickType, Facility } from '../../core/models/game.models';
import { AuthService } from '../../core/services/auth.service';
import { GameService } from '../../core/services/game.service';

/**
 * MADEN EKRANI — oyunun ana dongusu.
 *
 * Akis: butona bas -> sunucuya "kazdim" de -> sunucu ne kazandigini soyler
 *       -> ekran sunucunun dondurdugu degerlerle guncellenir.
 *
 * Ekranda gordugun hicbir sayi tarayicida hesaplanmiyor.
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

  /** Son kazanc — butonun yaninda kisa sure gorunen "+1" balonu icin. */
  readonly sonKazanc = signal<{ facilityTypeId: number; miktar: number; anahtar: number } | null>(null);

  ngOnInit(): void {
    this.game.loadState().subscribe({
      next: () => this.yukleniyor.set(false),
      error: (hata: HttpErrorResponse) => {
        this.yukleniyor.set(false);
        this.hataMesaji.set(
          hata.status === 0
            ? 'Sunucuya ulaşılamıyor. API çalışıyor mu? (http://localhost:5080)'
            : (hata.error?.message ?? 'Oyun durumu alınamadı.')
        );
      }
    });
  }

  kaz(facility: Facility, click: ClickType): void {
    // Buton zaten devre disi ama cift tiklama / klavye ile tetiklenmeye karsi koruma.
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
            anahtar: Date.now()      // her kazancta degisir -> animasyon yeniden baslar
          });
        },
        error: (hata: HttpErrorResponse) => {
          // 400 = bekleme suresi dolmamis. Sunucu son sozu soyler; istemci
          // tahmini yanlissa durumu yeniden cekip senkron oluyoruz.
          this.hataMesaji.set(hata.error?.message ?? 'Kazma yapılamadı.');
          this.game.loadState().subscribe();
        }
      });
  }

  /** Geri sayimi "3,2 sn" bicimine cevirir. */
  kalanMetin(facilityTypeId: number, clickTypeId: number): string {
    const ms = this.game.remainingMs(facilityTypeId, clickTypeId);
    return ms === 0 ? '' : (ms / 1000).toFixed(1) + ' sn';
  }

  /** Bekleme suresinin yuzde kaci doldu (ilerleme cubugu icin). */
  ilerleme(facilityTypeId: number, clickTypeId: number, cooldownSeconds: number): number {
    const kalan = this.game.remainingMs(facilityTypeId, clickTypeId);
    if (kalan === 0) {
      return 100;
    }
    return 100 - (kalan / (cooldownSeconds * 1000)) * 100;
  }

  /**
   * Buyuk sayilari kisaltir: 47115 -> "47,1B"
   * Veri her zaman tam sayi kalir; bu yalnizca GORUNTULEME katmanidir.
   */
  bicimle(sayi: number): string {
    if (sayi < 1000) return String(sayi);
    if (sayi < 1_000_000) return (sayi / 1000).toFixed(1).replace('.', ',') + 'B';
    if (sayi < 1_000_000_000) return (sayi / 1_000_000).toFixed(1).replace('.', ',') + 'M';
    return (sayi / 1_000_000_000).toFixed(1).replace('.', ',') + 'Mr';
  }

  cikisYap(): void {
    this.auth.logout();
    this.router.navigateByUrl('/login');
  }
}
