import { Component, inject } from '@angular/core';
import { ToastService, ToastTuru } from '../../services/toast.service';

/**
 * TOAST YIGINI.
 *
 * app.html icinde tek bir kez duruyor (router-outlet'in disinda), boylece
 * sayfa degistiginde yok olup yeniden kurulmuyor.
 *
 * Kendi durumu yok: gorevinin tamami ToastService'teki listeyi cizmek ve
 * kapatma butonunu servise baglamak.
 */
@Component({
  selector: 'app-toast',
  templateUrl: './toast.html',
  styleUrl: './toast.css'
})
export class ToastComponent {
  protected readonly toast = inject(ToastService);

  ikon(tur: ToastTuru): string {
    return tur === 'basari' ? '✅' : tur === 'hata' ? '⚠️' : 'ℹ️';
  }
}
