import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { ApplicationConfig, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideRouter, withComponentInputBinding } from '@angular/router';
import { jwtInterceptor } from './core/interceptors/jwt.interceptor';
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
    provideRouter(routes, withComponentInputBinding())
  ]
};
