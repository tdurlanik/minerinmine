import { Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { ToastComponent } from './core/components/toast/toast';

/**
 * KÖK BİLEŞEN (Root Component).
 *
 * index.html içindeki <app-root> etiketinin yerine geçer.
 * İçeriği neredeyse boştur: router-outlet sunar ve tüm uygulamada ortak
 * kalması gereken tek görsel parçayı — bildirim yığınını — barındırır.
 */
@Component({
  selector: 'app-root',
  imports: [RouterOutlet, ToastComponent],
  templateUrl: './app.html',
  styleUrl: './app.css'
})
export class App {}
