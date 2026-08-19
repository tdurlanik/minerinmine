import { provideHttpClient, withInterceptors } from '@angular/common/http';
import {
  ApplicationConfig,
  inject,
  provideAppInitializer,
  provideBrowserGlobalErrorListeners
} from '@angular/core';
import { provideRouter, withComponentInputBinding } from '@angular/router';
import { jwtInterceptor } from './core/interceptors/jwt.interceptor';
import { AuthService } from './core/services/auth.service';
import { routes } from './app.routes';

/**
 * UYGULAMA YAPILANDIRMASI
 *
 * Angular'ın eski sürümlerinde bu iş app.module.ts içinde NgModule ile yapılırdı.
 * Angular 15+ ile "standalone" mimariye geçildi: modül yok, her bileşen kendi
 * bağımlılığını kendisi bildiriyor. Uygulama geneli servisler ise burada
 * "provider" olarak tanımlanıyor.
 *
 * Bu dosya .NET tarafındaki Program.cs'in karşılığıdır: ikisi de "uygulama
 * ayağa kalkarken hangi servisler kayıtlı olsun?" sorusunu cevaplar.
 */
export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),

    // HttpClient'ı kullanılabilir yapar VE giden isteklere jwtInterceptor'ı takar.
    // Dizideki sıra önemlidir: interceptor'lar yazıldıkları sırayla çalışır.
    provideHttpClient(withInterceptors([jwtInterceptor])),

    // Router'ı kurar. withComponentInputBinding(): rota parametrelerini doğrudan
    // bileşen @Input'larına bağlamayı sağlar (ileride oyun sayfalarında işimize yarayacak).
    provideRouter(routes, withComponentInputBinding()),

    /**
     * SESSİZ OTURUM KURTARMA
     *
     * Uygulama ekrana çizilmeden ÖNCE bir kez çalışır.
     *
     * Access token sessionStorage'da tutuluyor; yeni bir sekmede orası boştur.
     * Ama refresh token HttpOnly cookie'de duruyor olabilir. Bu yüzden açılışta
     * sessizce yenilemeyi deniyoruz — başarılıysa kullanıcı hiç fark etmeden
     * giriş yapmış olur, değilse giriş ekranına düşer.
     *
     * Bu adım olmasaydı her yeni sekme yeniden şifre isterdi ve 7 günlük
     * refresh token'ın hiçbir anlamı kalmazdı.
     *
     * restoreSession() hiçbir koşulda hata fırlatmaz; aksi halde uygulama
     * açılışı bloke olurdu.
     */
    provideAppInitializer(() => inject(AuthService).restoreSession())
  ]
};
