import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { UserInfo } from '../../core/models/auth.models';
import { AuthService } from '../../core/services/auth.service';
import { UserService } from '../../core/services/user.service';

/**
 * MADEN MERKEZİ (Dashboard)
 *
 * Giriş yaptıktan sonra açılan karşılama paneli. İleride madencilik/clicker
 * oyununun ana ekranı burası olacak; şimdilik kimlik doğrulama altyapısının
 * uçtan uca çalıştığını KANITLAMA görevi görüyor.
 *
 * Sayfa açılır açılmaz korumalı /api/users/me ucuna istek atıyoruz. Veri
 * geliyorsa şu zincirin tamamı çalışıyor demektir:
 *   localStorage'daki token -> jwtInterceptor -> Authorization header
 *   -> ASP.NET JWT doğrulaması -> [Authorize] -> controller -> cevap
 */
@Component({
  selector: 'app-dashboard',
  imports: [],
  templateUrl: './dashboard.html',
  styleUrl: './dashboard.css'
})
export class DashboardComponent implements OnInit {
  private readonly userService = inject(UserService);
  private readonly router = inject(Router);
  protected readonly authService = inject(AuthService); // şablon da kullanacak

  /** Sunucudan (token'dan değil) gelen doğrulanmış kullanıcı bilgisi. */
  readonly sunucuKullanici = signal<UserInfo | null>(null);
  readonly yukleniyor = signal(true);
  readonly hataMesaji = signal<string | null>(null);

  /** Admin ucu deneme sonucu — rol bazlı yetkilendirmeyi canlı göstermek için. */
  readonly adminSonuc = signal<string | null>(null);
  readonly adminHata = signal<string | null>(null);

  /**
   * ngOnInit: Angular bileşeni oluşturup girdilerini bağladıktan HEMEN SONRA
   * bir kez çalışır. Veri çekme işlemleri için doğru yer burasıdır
   * (constructor'da yapılmaz: constructor nesne kurulumu içindir, yan etki için değil).
   */
  ngOnInit(): void {
    this.userService.getMe().subscribe({
      next: (kullanici) => {
        this.sunucuKullanici.set(kullanici);
        this.yukleniyor.set(false);
      },
      error: (hata: HttpErrorResponse) => {
        this.yukleniyor.set(false);

        // 401 durumunu interceptor zaten yakalayıp login'e yönlendiriyor;
        // buraya düşen genellikle sunucuya ulaşılamama (status 0) durumudur.
        this.hataMesaji.set(
          hata.status === 0
            ? 'Sunucuya ulaşılamıyor. API çalışıyor mu? (http://localhost:5080)'
            : (hata.error?.message ?? 'Kullanıcı bilgileri alınamadı.')
        );
      }
    });
  }

  /** Sadece Admin'in erişebildiği ucu dener — 200 mü 403 mü görelim. */
  adminUcunuDene(): void {
    this.adminSonuc.set(null);
    this.adminHata.set(null);

    this.userService.getAdminOnly().subscribe({
      next: (cevap) => this.adminSonuc.set(cevap.message),
      error: (hata: HttpErrorResponse) => {
        this.adminHata.set(
          hata.status === 403
            ? '403 Forbidden — Kimliğin doğrulandı ama Admin rolün yok. Bu BEKLENEN sonuçtur.'
            : (hata.error?.message ?? `İstek başarısız (HTTP ${hata.status}).`)
        );
      }
    });
  }

  cikisYap(): void {
    this.authService.logout();
    this.router.navigateByUrl('/login');
  }
}
