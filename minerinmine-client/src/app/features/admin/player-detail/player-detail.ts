import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { AdminPlayerDetail, AdminResource } from '../../../core/models/meta.models';
import { AdminService } from '../../../core/services/admin.service';
import { AuthService } from '../../../core/services/auth.service';
import { ToastService } from '../../../core/services/toast.service';

/**
 * OYUNCU DETAY EKRANI (/admin/player/:id)
 *
 * Yonetim paneli su ana kadar yalnizca BAKIYORDU. Bu ekran onu "yapan" hale
 * getiriyor: kaynak duzeltme, hesap dondurma, rol degistirme, oturum dusurme.
 *
 * ONEMLI: Buradaki butonlarin hicbiri yetki VERMEZ. Her uc sunucuda
 * [Authorize(Roles = "Admin")] ile korunuyor ve asil kurallar (admin kendi
 * hesabini donduramaz, son adminin rolu alinamaz, bakiye negatife dusemez)
 * SP icinde yaziyor. Arayuz yalnizca bunlari gorunur kiliyor.
 */
@Component({
  selector: 'app-admin-player-detail',
  imports: [RouterLink],
  templateUrl: './player-detail.html',
  styleUrl: './player-detail.css'
})
export class PlayerDetailComponent implements OnInit {
  private readonly service = inject(AdminService);
  private readonly route = inject(ActivatedRoute);
  private readonly toast = inject(ToastService);
  protected readonly auth = inject(AuthService);

  readonly veri = signal<AdminPlayerDetail | null>(null);
  readonly yukleniyor = signal(true);
  readonly hataMesaji = signal<string | null>(null);

  /** Islem surerken butonlari kilitler (cift tiklama korumasi). */
  readonly islemde = signal(false);

  /** Kaynak duzeltme formu: hangi kaynak, ne kadar. */
  readonly secilenKaynak = signal<number | null>(null);
  readonly miktar = signal(0);

  private userId = 0;

  /**
   * Rota parametresini SNAPSHOT ile degil AKIS olarak dinliyoruz.
   *
   * Angular ayni rotada yalnizca parametre degistiginde (ornegin
   * /admin/player/20 -> /admin/player/23) bileseni YENIDEN KURMAZ; ngOnInit
   * ikinci kez calismaz. Snapshot okusaydik adres degisir, ekranda eski
   * oyuncu kalirdi. paramMap'e abone olunca her degisimde yeniden yukluyoruz.
   */
  ngOnInit(): void {
    this.route.paramMap.subscribe((p) => {
      this.userId = Number(p.get('id'));   // rota parametresi her zaman METIN gelir
      this.yukleniyor.set(true);
      this.hataMesaji.set(null);
      this.secilenKaynak.set(null);        // yeni oyuncunun kaynaklari secilsin
      this.yukle();
    });
  }

  private yukle(): void {
    this.service.getPlayerDetail(this.userId).subscribe({
      next: (d) => {
        this.veri.set(d);
        this.yukleniyor.set(false);

        if (this.secilenKaynak() === null && d.resources.length > 0) {
          this.secilenKaynak.set(d.resources[0].resourceTypeId);
        }
      },
      error: (hata: HttpErrorResponse) => {
        this.yukleniyor.set(false);
        this.hataMesaji.set(
          hata.status === 404
            ? 'Oyuncu bulunamadı.'
            : (hata.error?.message ?? 'Oyuncu bilgileri alınamadı.')
        );
      }
    });
  }

  // ==========================================================================
  // YONETIM EYLEMLERI
  // ==========================================================================

  durumDegistir(): void {
    const oyuncu = this.veri()?.player;
    if (!oyuncu) {
      return;
    }

    const yeniDurum = !oyuncu.isActive;
    const soru = yeniDurum
      ? oyuncu.username + ' hesabı yeniden açılsın mı?'
      : oyuncu.username + ' hesabı dondurulsun mu? Açık oturumları da düşürülecek.';

    if (!confirm(soru)) {
      return;
    }

    this.islemde.set(true);

    this.service.setActive(this.userId, yeniDurum).subscribe({
      next: (s) => {
        this.islemde.set(false);
        this.toast.basari(
          s.isActive
            ? 'Hesap yeniden açıldı.'
            : 'Hesap donduruldu, ' + s.revokedSessions + ' oturum düşürüldü.'
        );
        this.yukle();
      },
      error: (hata: HttpErrorResponse) => this.eylemHatasi(hata, 'Hesap durumu değiştirilemedi.')
    });
  }

  rolDegistir(rol: string, ver: boolean): void {
    this.islemde.set(true);

    this.service.setRole(this.userId, rol, ver).subscribe({
      next: (s) => {
        this.islemde.set(false);
        this.toast.basari(s.roleName + ' rolü ' + (s.isGranted ? 'verildi.' : 'alındı.'));
        this.yukle();
      },
      error: (hata: HttpErrorResponse) => this.eylemHatasi(hata, 'Rol değiştirilemedi.')
    });
  }

  oturumlariDusur(): void {
    if (!confirm('Bu oyuncunun tüm oturumları düşürülsün mü?')) {
      return;
    }

    this.islemde.set(true);

    this.service.revokeSessions(this.userId).subscribe({
      next: (s) => {
        this.islemde.set(false);
        this.toast.basari(s.revokedSessions + ' oturum düşürüldü.');
        this.yukle();
      },
      error: (hata: HttpErrorResponse) => this.eylemHatasi(hata, 'Oturumlar düşürülemedi.')
    });
  }

  kaynakDuzelt(): void {
    const kaynakId = this.secilenKaynak();
    const delta = this.miktar();

    if (kaynakId === null || delta === 0) {
      this.toast.bilgi('Kaynak seç ve sıfırdan farklı bir miktar gir.');
      return;
    }

    this.islemde.set(true);

    this.service.adjust(this.userId, kaynakId, delta).subscribe({
      next: (s) => {
        this.islemde.set(false);
        this.miktar.set(0);
        this.toast.basari(
          (s.delta > 0 ? '+' : '') + s.delta + ' uygulandı. Yeni bakiye: ' + s.newBalance
        );
        this.yukle();
      },
      error: (hata: HttpErrorResponse) => this.eylemHatasi(hata, 'Kaynak düzeltilemedi.')
    });
  }

  /**
   * Sunucudaki kural ihlalleri (son admin, kendi hesabi, negatif bakiye)
   * buraya 400 olarak duser ve mesaji SP'nin kendisi yazmistir.
   */
  private eylemHatasi(hata: HttpErrorResponse, varsayilan: string): void {
    this.islemde.set(false);
    this.toast.hata(hata.error?.message ?? varsayilan);
  }

  // ==========================================================================
  // FORM VE GORUNTULEME YARDIMCILARI
  // ==========================================================================

  kaynakSecildi(olay: Event): void {
    this.secilenKaynak.set(Number((olay.target as HTMLSelectElement).value));
  }

  miktarDegisti(olay: Event): void {
    this.miktar.set(Number((olay.target as HTMLInputElement).value));
  }

  rolVarMi(rol: string): boolean {
    return (this.veri()?.player?.roles ?? '')
      .split(',')
      .map((r) => r.trim())
      .includes(rol);
  }

  /** Kendi hesabimiz mi? Oyleyse tehlikeli butonlar gosterilmez. */
  kendisiMi(): boolean {
    return this.auth.userId() === this.userId;
  }

  kaynakAdi(k: AdminResource): string {
    return k.isCurrency ? k.name + ' (para birimi)' : k.name;
  }

  /** Transactions.Reason sistem kodunu okunur metne cevirir. */
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

  bicimle(sayi: number): string {
    const mutlak = Math.abs(sayi);
    if (mutlak < 1000) return String(sayi);
    if (mutlak < 1000000) return (sayi / 1000).toFixed(1).replace('.', ',') + 'B';
    return (sayi / 1000000).toFixed(1).replace('.', ',') + 'M';
  }

  /** SQL'den gelen tarihler UTC'dir; sonunda Z yoksa tarayıcı yerel sanır. */
  tarih(iso: string | null): string {
    if (!iso) {
      return '—';
    }
    const d = new Date(iso.endsWith('Z') ? iso : iso + 'Z');
    return d.toLocaleString('tr-TR', { dateStyle: 'short', timeStyle: 'short' });
  }
}
