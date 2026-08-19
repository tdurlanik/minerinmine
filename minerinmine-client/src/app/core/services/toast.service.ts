import { Injectable, signal } from '@angular/core';

/** Bildirim turu — renk ve ikon bunun uzerinden secilir. */
export type ToastTuru = 'basari' | 'hata' | 'bilgi';

export interface Toast {
  /** Listede takip (track) icin benzersiz numara. */
  id: number;
  tur: ToastTuru;
  mesaj: string;
}

/**
 * TOAST (gecici bildirim) SERVISI.
 *
 * ONCEDEN: her ekran kendi `bilgiMesaji` / `hataMesaji` sinyalini tutuyor ve
 * mesaji sayfanin ustune sabit bir bant olarak basiyordu. Bant yeni bir olay
 * olana kadar ekranda kaliyordu; ust uste iki islem yapildiginda ikincisi
 * birinciyi eziyordu.
 *
 * SIMDI: mesajlar tek bir listede toplaniyor, ekranin kosesinde yigin halinde
 * gorunuyor ve suresi dolunca kendiliginden siliniyor.
 *
 * NEDEN SERVIS?
 *  - `providedIn: 'root'` sayesinde uygulamada TEK bir ornek olusur. Oyun
 *    ekrani, siralama ve yonetim paneli ayni listeye yazar.
 *  - Bildirimi CIZEN bilesen (ToastComponent) app.html'de bir kez durur;
 *    sayfa degistiginde yeniden kurulmaz, bu yuzden gecis sirasinda gonderilen
 *    bildirim de kaybolmaz.
 */
@Injectable({ providedIn: 'root' })
export class ToastService {
  /** Ekranda duran bildirimler. Bilesen bunu okuyup ciziyor. */
  private readonly liste = signal<Toast[]>([]);
  readonly toasts = this.liste.asReadonly();

  /** Her bildirime benzersiz id vermek icin artan sayac. */
  private sonrakiId = 1;

  /** Ayni anda en fazla kac bildirim gorunsun (eskiler dusurulur). */
  private readonly ENCOK = 4;

  private readonly SURE_MS: Record<ToastTuru, number> = {
    basari: 3500,
    bilgi: 4000,
    hata: 6000   // hatayi okumak daha uzun surer
  };

  basari(mesaj: string): void {
    this.ekle('basari', mesaj);
  }

  bilgi(mesaj: string): void {
    this.ekle('bilgi', mesaj);
  }

  hata(mesaj: string): void {
    this.ekle('hata', mesaj);
  }

  kapat(id: number): void {
    this.liste.update((mevcut) => mevcut.filter((t) => t.id !== id));
  }

  temizle(): void {
    this.liste.set([]);
  }

  private ekle(tur: ToastTuru, mesaj: string): void {
    const id = this.sonrakiId++;

    this.liste.update((mevcut) => {
      const yeni = [...mevcut, { id, tur, mesaj }];
      // Yigin buyumesin: en eskileri at.
      return yeni.length > this.ENCOK ? yeni.slice(yeni.length - this.ENCOK) : yeni;
    });

    // Kendiliginden kapanma. Kullanici erken kapatirsa kapat() zaten listeden
    // sildigi icin bu zamanlayicinin gec calismasi zararsizdir.
    setTimeout(() => this.kapat(id), this.SURE_MS[tur]);
  }
}
