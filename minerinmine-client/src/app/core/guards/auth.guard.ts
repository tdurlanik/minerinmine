import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from '../services/auth.service';

/**
 * AUTH GUARD (Rota Bekçisi)
 *
 * Bir rotaya gidilmeden ÖNCE çalışır ve "bu kullanıcı buraya girebilir mi?"
 * sorusunu cevaplar. true dönerse sayfa açılır, false dönerse açılmaz.
 *
 * ÇOK ÖNEMLİ GÜVENLİK NOTU:
 * Guard bir GÜVENLİK duvarı DEĞİL, bir KULLANICI DENEYİMİ aracıdır!
 * Tüm kontrol tarayıcıda çalışır; kullanıcı DevTools ile localStorage'a sahte
 * bir kayıt yazıp guard'ı kandırabilir. Ama sayfa açılsa bile API'den veri
 * ÇEKEMEZ, çünkü asıl kontrol sunucudaki [Authorize] attribute'undadır.
 * Kural: Frontend kontrolü kolaylık içindir, GERÇEK güvenlik her zaman backend'dedir.
 */
export const authGuard: CanActivateFn = (route, state) => {
  const authService = inject(AuthService);
  const router = inject(Router);

  if (authService.isLoggedIn()) {
    return true;
  }

  // Giriş yapılmamış: login'e yönlendir.
  // returnUrl: kullanıcı /dashboard'a gitmek isterken engellendiyse, giriş
  // yaptıktan sonra ana sayfaya değil TAM İSTEDİĞİ SAYFAYA götürelim.
  router.navigate(['/login'], { queryParams: { returnUrl: state.url } });
  return false;
};

/**
 * Zaten giriş yapmış kullanıcının login/register sayfalarını görmesini engeller.
 * Oturumu açıkken /login'e gitmeye çalışırsa doğrudan dashboard'a alınır.
 */
export const guestGuard: CanActivateFn = () => {
  const authService = inject(AuthService);
  const router = inject(Router);

  if (!authService.isLoggedIn()) {
    return true;
  }

  router.navigate(['/dashboard']);
  return false;
};
