import { Routes } from '@angular/router';
import { authGuard, guestGuard } from './core/guards/auth.guard';

/**
 * ROTA TABLOSU — hangi adres hangi bileşeni açar?
 *
 * loadComponent + import(): "lazy loading" (tembel yükleme).
 * Bileşenin kodu uygulama açılırken DEĞİL, kullanıcı o sayfaya gittiğinde
 * indirilir. Böylece ilk açılış hızlanır. Login sayfasını açan kullanıcı
 * dashboard'un kodunu boşuna indirmemiş olur.
 *
 * Rota sırası ÖNEMLİDİR: Angular yukarıdan aşağı ilk eşleşeni seçer.
 * Bu yüzden '**' (hiçbiriyle eşleşmeyen) her zaman EN SONDA olmalıdır.
 */
export const routes: Routes = [
  {
    path: '',
    redirectTo: 'login',
    pathMatch: 'full' // 'full' olmazsa BOŞ olmayan tüm yollar da buraya düşerdi
  },
  {
    path: 'login',
    title: 'Giriş Yap · MinerInMine',
    canActivate: [guestGuard], // zaten giriş yapmışsa dashboard'a gönder
    loadComponent: () => import('./features/auth/login/login').then((m) => m.LoginComponent)
  },
  {
    path: 'register',
    title: 'Kayıt Ol · MinerInMine',
    canActivate: [guestGuard],
    loadComponent: () =>
      import('./features/auth/register/register').then((m) => m.RegisterComponent)
  },
  {
    path: 'dashboard',
    title: 'Maden Merkezi · MinerInMine',
    canActivate: [authGuard], // giriş yapmamışsa login'e gönder
    loadComponent: () =>
      import('./features/dashboard/dashboard').then((m) => m.DashboardComponent)
  },
  {
    path: '**', // yukarıdakilerin hiçbiriyle eşleşmeyen her adres
    redirectTo: 'login'
  }
];
