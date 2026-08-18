import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { Leaderboard } from '../../core/models/meta.models';
import { LeaderboardService } from '../../core/services/leaderboard.service';

/**
 * SIRALAMA EKRANI
 *
 * Servet = Kristal + (her madenin miktari x birim degeri). Bu sayede madenini
 * satmamis oyuncu da hak ettigi yerde gorunur.
 *
 * Sira numaralari sunucuda RANK() pencere fonksiyonuyla hesaplanir; istemci
 * yalnizca gelen listeyi cizer.
 */
@Component({
  selector: 'app-leaderboard',
  imports: [RouterLink],
  templateUrl: './leaderboard.html',
  styleUrl: './leaderboard.css'
})
export class LeaderboardComponent implements OnInit {
  private readonly service = inject(LeaderboardService);

  readonly veri = signal<Leaderboard | null>(null);
  readonly yukleniyor = signal(true);
  readonly hataMesaji = signal<string | null>(null);

  ngOnInit(): void {
    this.service.getTop(25).subscribe({
      next: (d) => {
        this.veri.set(d);
        this.yukleniyor.set(false);
      },
      error: (hata: HttpErrorResponse) => {
        this.yukleniyor.set(false);
        this.hataMesaji.set(
          hata.status === 0 ? 'Sunucuya ulaşılamıyor.' : (hata.error?.message ?? 'Sıralama alınamadı.')
        );
      }
    });
  }

  /** İlk üç için madalya, sonrası için numara. */
  madalya(sira: number): string {
    return sira === 1 ? '🥇' : sira === 2 ? '🥈' : sira === 3 ? '🥉' : '#' + sira;
  }

  bicimle(sayi: number): string {
    if (sayi < 1000) return String(sayi);
    if (sayi < 1000000) return (sayi / 1000).toFixed(1).replace('.', ',') + 'B';
    if (sayi < 1000000000) return (sayi / 1000000).toFixed(1).replace('.', ',') + 'M';
    return (sayi / 1000000000).toFixed(1).replace('.', ',') + 'Mr';
  }
}
