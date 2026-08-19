import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { PlayerStats, StatsBreakdown, StatsFacility } from '../../core/models/game.models';
import { AuthService } from '../../core/services/auth.service';
import { GameService } from '../../core/services/game.service';

/**
 * İSTATİSTİK EKRANI (/dashboard)
 *
 * Bu sayfa önce Gün 0'dan kalma bir "kimlik doğrulama kanıtı" paneliydi:
 * token'ın çalıştığını göstermek için /api/users/me sonucunu basıyordu.
 * O görev tamamlandığı için sayfa oyuncuya bir şey anlatan hâle getirildi.
 *
 * BURADAKİ ASIL DERS: bu ekranın verisi HİÇBİR YERDE HAZIR DURMUYOR.
 * "Kristal'i en çok neye harcadın?" sorusunun cevabı ne PlayerResources'ta
 * ne başka bir tabloda yazar — bakiye tabloları yalnızca SON durumu bilir.
 * Cevap, Transactions olay günlüğünü en baştan tuttuğumuz için hesaplanabiliyor.
 * Günlük tutulmasaydı bu özellik "bugünden itibaren" çalışabilirdi.
 */
@Component({
  selector: 'app-dashboard',
  imports: [RouterLink],
  templateUrl: './dashboard.html',
  styleUrl: './dashboard.css'
})
export class DashboardComponent implements OnInit {
  private readonly game = inject(GameService);
  private readonly router = inject(Router);
  protected readonly auth = inject(AuthService);

  readonly veri = signal<PlayerStats | null>(null);
  readonly yukleniyor = signal(true);
  readonly hataMesaji = signal<string | null>(null);

  /**
   * Harcama dağılımındaki EN BÜYÜK kalem.
   * Çubukların uzunluğu buna oranla hesaplanıyor: en büyük kalem %100 olur,
   * diğerleri ona göre kısalır. Böylece oyuncunun toplamı ne olursa olsun
   * grafik hep okunur kalır.
   */
  private readonly enBuyukHarcama = computed(() =>
    Math.max(1, ...this.veri()?.spending.map((h) => h.total) ?? [1])
  );

  private readonly enBuyukKazanc = computed(() =>
    Math.max(1, ...this.veri()?.earning.map((k) => k.total) ?? [1])
  );

  /**
   * EN COK URETEN TESIS.
   *
   * Sunucudan ayri bir alan olarak istemiyoruz: veri zaten tesis listesinde
   * geliyor, "en buyugu hangisi" sorusu tek gecislik bir kiyaslama. Sunucuya
   * ekstra sorgu yaptirmak bu is icin gereksiz olurdu.
   *
   * Hic uretim yoksa null doner; ekran o zaman karti hic gostermez ("0 ile
   * birinci" gibi anlamsiz bir sonuc cikmasin).
   */
  readonly enCokUreten = computed<StatsFacility | null>(() => {
    const tesisler = this.veri()?.facilities ?? [];
    let en: StatsFacility | null = null;

    for (const t of tesisler) {
      if (t.totalMined > 0 && (en === null || t.totalMined > en.totalMined)) {
        en = t;
      }
    }
    return en;
  });

  ngOnInit(): void {
    this.game.getStats().subscribe({
      next: (d) => {
        this.veri.set(d);
        this.yukleniyor.set(false);
      },
      error: (hata: HttpErrorResponse) => {
        this.yukleniyor.set(false);
        this.hataMesaji.set(
          hata.status === 0
            ? 'Sunucuya ulaşılamıyor. API çalışıyor mu? (http://localhost:5080)'
            : (hata.error?.message ?? 'İstatistikler alınamadı.')
        );
      }
    });
  }

  harcamaOrani(satir: StatsBreakdown): number {
    return (satir.total / this.enBuyukHarcama()) * 100;
  }

  kazancOrani(satir: StatsBreakdown): number {
    return (satir.total / this.enBuyukKazanc()) * 100;
  }

  /**
   * Transactions.Reason kodlarını okunur Türkçeye çevirir.
   *
   * Çeviriyi veritabanına değil arayüze koyuyoruz: Reason bir SİSTEM KODUDUR,
   * sorgular ona göre yazılır. Görüntüleme metni değişse bile kod sabit kalmalı.
   */
  sebepAdi(reason: string): string {
    const sozluk: Record<string, string> = {
      CLICK: 'Elle kazma',
      COLLECT: 'Madenci toplama',
      SELL: 'Maden satışı',
      FACILITY_UPGRADE: 'Tesis geliştirme',
      HIRE_MINER: 'Madenci alımı',
      BUY_UPGRADE: 'Kalıcı güçlendirme',
      UNLOCK_CLICK: 'Kazma türü açma',
      INSTANT_FINISH: 'Süre atlama',
      AD_REWARD: 'Reklam ödülü',
      ADMIN_ADJUST: 'Yönetici düzeltmesi'
    };
    return sozluk[reason] ?? reason;
  }

  sebepIkonu(reason: string): string {
    const sozluk: Record<string, string> = {
      CLICK: '⛏️',
      COLLECT: '📦',
      SELL: '💰',
      FACILITY_UPGRADE: '⬆️',
      HIRE_MINER: '👷',
      BUY_UPGRADE: '⚡',
      UNLOCK_CLICK: '🔓',
      INSTANT_FINISH: '⏩',
      AD_REWARD: '🎬',
      ADMIN_ADJUST: '🛡️'
    };
    return sozluk[reason] ?? '•';
  }

  bicimle(sayi: number): string {
    if (sayi < 1000) return String(sayi);
    if (sayi < 1000000) return (sayi / 1000).toFixed(1).replace('.', ',') + 'B';
    if (sayi < 1000000000) return (sayi / 1000000).toFixed(1).replace('.', ',') + 'M';
    return (sayi / 1000000000).toFixed(1).replace('.', ',') + 'Mr';
  }

  /** SQL'den gelen tarihler UTC'dir; sonunda Z yoksa tarayıcı yerel sanır. */
  tarih(iso: string | null): string {
    if (!iso) return '—';
    const d = new Date(iso.endsWith('Z') ? iso : iso + 'Z');
    return d.toLocaleString('tr-TR', { dateStyle: 'medium', timeStyle: 'short' });
  }

  /** "3 gün önce" gibi kısa bir kıdem metni. */
  kidem(iso: string | null): string {
    if (!iso) return '—';
    const d = new Date(iso.endsWith('Z') ? iso : iso + 'Z');
    const gun = Math.floor((Date.now() - d.getTime()) / 86400000);
    return gun <= 0 ? 'bugün katıldı' : gun + ' gündür madenci';
  }

  cikisYap(): void {
    this.auth.logout();
    this.router.navigateByUrl('/login');
  }
}
