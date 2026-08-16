import { Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';

/**
 * KÖK BİLEŞEN (Root Component).
 *
 * index.html içindeki <app-root> etiketinin yerine geçer.
 * İçeriği neredeyse boştur: tek görevi <router-outlet> sunmak.
 * Router, adrese göre hangi bileşeni açacağına karar verir ve onu
 * router-outlet'in bulunduğu yere yerleştirir.
 */
@Component({
  selector: 'app-root',
  imports: [RouterOutlet],
  templateUrl: './app.html',
  styleUrl: './app.css'
})
export class App {}
