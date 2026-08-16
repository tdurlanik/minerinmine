import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { catchError, throwError } from 'rxjs';
import { AuthService } from '../services/auth.service';

/**
 * JWT INTERCEPTOR (İstek Yakalayıcı)
 *
 * NE İŞE YARAR?
 * Uygulamadan çıkan HER HTTP isteği, sunucuya gitmeden önce buradan geçer.
 * Biz de araya girip `Authorization: Bearer <token>` başlığını ekliyoruz.
 *
 * NEDEN GEREKLİ?
 * Olmasaydı, her servis metodunda token'ı elle eklemek zorunda kalırdık:
 *   this.http.get(url, { headers: { Authorization: 'Bearer ' + token } })
 * 50 farklı istekte 50 kez tekrar... Biri unutulursa sessizce 401 alırdık.
 * Interceptor bu sorumluluğu tek bir yere toplar.
 *
 * NOT: Angular 15+ ile interceptor'lar artık sınıf değil FONKSİYONDUR
 * (HttpInterceptorFn). app.config.ts içinde withInterceptors([...]) ile kaydedilir.
 */
export const jwtInterceptor: HttpInterceptorFn = (req, next) => {
  // inject(): fonksiyonun içinde constructor olmadan servis almanın yolu.
  const authService = inject(AuthService);
  const router = inject(Router);

  const token = authService.getAccessToken();

  // Auth uçlarına (login, register, refresh) token eklemeyiz — zaten token almak
  // için oraya gidiyoruz. Eski/geçersiz bir token göndermek gereksiz risktir.
  const isAuthEndpoint = req.url.includes('/auth/');

  // ÖNEMLİ: HttpRequest nesneleri DEĞİŞMEZDİR (immutable).
  // req.headers.set(...) diyerek doğrudan değiştiremeyiz; req.clone() ile
  // değiştirilmiş bir KOPYA üretip onu zincire veririz.
  const request =
    token && !isAuthEndpoint
      ? req.clone({ setHeaders: { Authorization: `Bearer ${token}` } })
      : req;

  // next(request): isteği zincirdeki bir sonraki adıma (sonunda sunucuya) gönderir.
  return next(request).pipe(
    catchError((error: HttpErrorResponse) => {
      // 401 = token yok, geçersiz veya süresi dolmuş.
      // Kullanıcıyı sessizce bekletmek yerine oturumu temizleyip login'e alıyoruz.
      // (Auth uçlarındaki 401 normaldir — "şifre yanlış" demektir — dokunmuyoruz.)
      if (error.status === 401 && !isAuthEndpoint) {
        authService.logout();
        router.navigate(['/login'], { queryParams: { expired: true } });
      }

      // Hatayı yutmuyoruz: bileşen de görebilsin diye akışa geri fırlatıyoruz.
      return throwError(() => error);
    })
  );
};
