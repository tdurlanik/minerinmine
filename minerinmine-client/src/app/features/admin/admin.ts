import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import {
  AdminActionLog,
  AdminPlayer,
  EconomyReport,
  SuspiciousEntry
} from '../../core/models/meta.models';
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

  /** Aktif sekme: oyuncu listesi mi, ekonomi raporu mu? */
  readonly aktifSekme = signal<'oyuncular' | 'ekonomi' | 'gunluk'>('oyuncular');

  readonly ekonomi = signal<EconomyReport | null>(null);
  readonly ekonomiYukleniyor = signal(false);

  readonly gunlukKayitlar = signal<AdminActionLog[]>([]);
  readonly gunlukYukleniyor = signal(false);

  /** Rapor kac gunluk? Kullanici degistirebiliyor. */
  readonly gun = signal(7);

  private readonly sayfaBoyu = 20;

  /** Ekonomi sekmesindeki donem secenekleri. */
  readonly donemler = [1, 7, 30];

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

  /**
   * Sekme degistir. Ekonomi raporu ILK ACILISTA yukleniyor: panel her
   * acildiginda calistirmak, kimsenin bakmadigi bir raporu bosuna
   * hesaplatmak olurdu (sorgular butun Transactions tablosunu tariyor).
   */
  sekmeSec(sekme: 'oyuncular' | 'ekonomi' | 'gunluk'): void {
    this.aktifSekme.set(sekme);

    if (sekme === 'ekonomi' && this.ekonomi() === null) {
      this.ekonomiYukle();
    }

    if (sekme === 'gunluk' && this.gunlukKayitlar().length === 0) {
      this.gunlukYukle();
    }
  }

  gunlukYukle(): void {
    this.gunlukYukleniyor.set(true);

    this.service.getActionLog(50).subscribe({
      next: (d) => {
        this.gunlukKayitlar.set(d);
        this.gunlukYukleniyor.set(false);
      },
      error: (hata: HttpErrorResponse) => {
        this.gunlukYukleniyor.set(false);
        this.toast.hata(hata.error?.message ?? 'İşlem günlüğü alınamadı.');
      }
    });
  }

  /** Eylem kodunu okunur metne cevirir. */
  eylemAdi(action: string): string {
    const sozluk: Record<string, string> = {
      DEACTIVATE: 'Hesap donduruldu',
      ACTIVATE: 'Hesap açıldı',
      GRANT_ROLE: 'Rol verildi',
      REVOKE_ROLE: 'Rol alındı',
      REVOKE_SESSIONS: 'Oturumlar düşürüldü',
      ADJUST: 'Kaynak düzeltmesi'
    };
    return sozluk[action] ?? action;
  }

  eylemIkonu(action: string): string {
    const sozluk: Record<string, string> = {
      DEACTIVATE: '🚫',
      ACTIVATE: '✅',
      GRANT_ROLE: '🛡️',
      REVOKE_ROLE: '🛡️',
      REVOKE_SESSIONS: '🔑',
      ADJUST: '💠'
    };
    return sozluk[action] ?? '•';
  }

  ekonomiYukle(): void {
    this.ekonomiYukleniyor.set(true);

    this.service.getEconomy(this.gun()).subscribe({
      next: (d) => {
        this.ekonomi.set(d);
        this.ekonomiYukleniyor.set(false);
      },
      error: (hata: HttpErrorResponse) => {
        this.ekonomiYukleniyor.set(false);
        this.toast.hata(hata.error?.message ?? 'Ekonomi raporu alınamadı.');
      }
    });
  }

  gunDegisti(gun: number): void {
    this.gun.set(gun);
    this.ekonomiYukle();
  }

  // ==========================================================================
  // EKONOMI GORUNTULEME YARDIMCILARI
  // ==========================================================================

  /**
   * Gunluk akis cubuklarinin olcegi: donemdeki EN BUYUK gunluk hareket.
   * Faucet ve sink ayni olcegi paylasiyor, yoksa iki cubuk kiyaslanamazdi.
   */
  gunlukOlcek(): number {
    const g = this.ekonomi()?.daily ?? [];
    return Math.max(1, ...g.map((x) => Math.max(x.faucet, x.sink)));
  }

  sebepOlcek(): number {
    const r = this.ekonomi()?.reasons ?? [];
    return Math.max(1, ...r.map((x) => x.total));
  }

  /** Faucet/sink orani: 1'in uzeri para birikiyor, alti para yakiliyor demek. */
  akisOrani(): number {
    const o = this.ekonomi()?.summary;
    if (!o || o.periodSink === 0) return 0;
    return o.periodFaucet / o.periodSink;
  }

  yuzde(bolum: number, toplam: number): number {
    return toplam === 0 ? 0 : (bolum / toplam) * 100;
  }

  /**
   * Sayi bicimleyicileri.
   *
   * DecimalPipe ({{ x | number }}) yerine metot kullaniyoruz: pipe icin
   * bilesene CommonModule almak gerekirdi, oysa tek ihtiyacimiz iki basamak.
   */
  oran(deger: number): string {
    return deger.toFixed(2).replace('.', ',');
  }

  ondalik(deger: number): string {
    return deger.toFixed(1).replace('.', ',');
  }

  tamsayi(deger: number): string {
    return String(Math.round(deger));
  }

  sebepAdi(reason: string): string {
    const sozluk: Record<string, string> = {
      CLICK: 'Elle kazma',
      COLLECT: 'Madenci toplama',
      SELL: 'Maden satışı',
      FACILITY_UPGRADE: 'Tesis geliştirme',
      HIRE_MINER: 'Madenci alımı',
      BUY_UPGRADE: 'Güçlendirme',
      UNLOCK_CLICK: 'Kazma açma',
      INSTANT_FINISH: 'Süre atlama',
      AD_REWARD: 'Reklam ödülü',
      BUY_FACILITY: 'Tesis satın alma',
      ADMIN_ADJUST: 'Yönetici düzeltmesi'
    };
    return sozluk[reason] ?? reason;
  }

  /** Sadece gun/ay — gunluk akis tablosu icin kisa tarih. */
  kisaTarih(iso: string): string {
    const d = new Date(iso.endsWith('Z') ? iso : iso + 'Z');
    return d.toLocaleDateString('tr-TR', { day: '2-digit', month: 'short' });
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
