import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AdminPlayer, SuspiciousEntry } from '../../core/models/meta.models';
import { AdminService } from '../../core/services/admin.service';
import { ToastService } from '../../core/services/toast.service';

/**
 * YONETIM PANELI
 *
 * Bu ekrana yalnizca Admin rolu erisebilir. Ama asil korumayi saglayan sey
 * arayuz degil, sunucudaki [Authorize(Roles = "Admin")] attribute'udur:
 * kullanici localStorage'i kurcalayip bu sayfayi acsa bile tek bir veri goremez.
 *
 * "Supheli kazanc" listesi ancak Transactions gunlugunu en bastan tuttugumuz
 * icin mumkun — sonradan eklenebilecek bir ozellik degil.
 */
@Component({
  selector: 'app-admin',
  imports: [RouterLink],
  templateUrl: './admin.html',
  styleUrl: './admin.css'
})
export class AdminComponent implements OnInit {
  private readonly service = inject(AdminService);
  private readonly toast = inject(ToastService);

  readonly oyuncular = signal<AdminPlayer[]>([]);
  readonly toplam = signal(0);
  readonly sayfa = signal(1);
  readonly arama = signal('');
  readonly supheliler = signal<SuspiciousEntry[]>([]);
  readonly yukleniyor = signal(true);
  readonly hataMesaji = signal<string | null>(null);

  private readonly sayfaBoyu = 20;

  /** Ilk yukleme mi? Ilk hata sayfada kalir, sonrakiler toast olarak gecer. */
  private ilkYukleme = true;

  ngOnInit(): void {
    this.yukle();
    this.supheliYukle();
  }

  yukle(): void {
    this.yukleniyor.set(true);

    this.service.getPlayers(this.arama(), this.sayfa(), this.sayfaBoyu).subscribe({
      next: (d) => {
        this.oyuncular.set(d.players);
        this.toplam.set(d.totalCount);
        this.yukleniyor.set(false);
        this.ilkYukleme = false;
      },
      error: (hata: HttpErrorResponse) => {
        this.yukleniyor.set(false);

        const mesaj =
          hata.status === 403
            ? 'Bu sayfa için Admin yetkisi gerekiyor.'
            : (hata.error?.message ?? 'Oyuncu listesi alınamadı.');

        // Ilk yuklemede ekranda gosterilecek baska bir sey olmadigi icin hata
        // sayfada kalir. Arama/sayfa degistirmede ise liste zaten duruyor;
        // orada kalici bant yerine gecici bildirim daha dogru.
        if (this.ilkYukleme) {
          this.hataMesaji.set(mesaj);
        } else {
          this.toast.hata(mesaj);
        }
      }
    });
  }

  supheliYukle(): void {
    this.service.getSuspicious(60, 100000).subscribe({
      next: (d) => this.supheliler.set(d),
      error: () => {
        this.supheliler.set([]);
        this.toast.bilgi('Şüpheli kazanç listesi alınamadı.');
      }
    });
  }

  aramaDegisti(olay: Event): void {
    this.arama.set((olay.target as HTMLInputElement).value);
    this.sayfa.set(1);
    this.yukle();
  }

  sayfaDegistir(yon: number): void {
    const yeni = this.sayfa() + yon;
    if (yeni < 1 || yeni > this.sonSayfa) {
      return;
    }
    this.sayfa.set(yeni);
    this.yukle();
  }

  get sonSayfa(): number {
    return Math.max(1, Math.ceil(this.toplam() / this.sayfaBoyu));
  }

  bicimle(sayi: number): string {
    if (sayi < 1000) return String(sayi);
    if (sayi < 1000000) return (sayi / 1000).toFixed(1).replace('.', ',') + 'B';
    return (sayi / 1000000).toFixed(1).replace('.', ',') + 'M';
  }

  tarih(iso: string | null): string {
    if (!iso) return '—';
    const d = new Date(iso.endsWith('Z') ? iso : iso + 'Z');
    return d.toLocaleString('tr-TR', { dateStyle: 'short', timeStyle: 'short' });
  }
}
