import { HttpClient } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { HttpTransportType, HubConnection, HubConnectionBuilder, LogLevel } from '@microsoft/signalr';
import { firstValueFrom } from 'rxjs';
import { environment } from '../../../environments/environment';
import { AuthService } from './auth.service';
import { ToastService } from './toast.service';

/** Sohbet mesaji — sunucudaki ChatMessageDto ile ayni sekil. */
export interface ChatMessage {
  id: number;
  userId: number;
  username: string;
  body: string;
  createdAt: string;
}

/** Baglanti durumu — arayuz kullaniciya bunu gosteriyor. */
export type SohbetDurumu = 'kapali' | 'baglaniyor' | 'bagli';

/**
 * MADEN SOHBETI SERVISI.
 *
 * IKI FARKLI KANAL KULLANIYOR, cunku iki farkli is var:
 *   - GECMIS  -> siradan HTTP istegi. Bir kez sorulur, cevap gelir, biter.
 *   - CANLI   -> SignalR (WebSocket). Baglanti acik kalir, sunucu istedigi
 *                anda "yeni mesaj var" diyebilir.
 *
 * Siradan HTTP ile canli sohbet yapmak icin istemcinin surekli sorması
 * (polling) gerekirdi: hem gec kalir hem bosuna yuzlerce istek uretir.
 */
@Injectable({ providedIn: 'root' })
export class ChatService {
  private readonly http = inject(HttpClient);
  private readonly auth = inject(AuthService);
  private readonly toast = inject(ToastService);

  private readonly apiUrl = `${environment.apiUrl}/chat`;

  private connection: HubConnection | null = null;

  private readonly _mesajlar = signal<ChatMessage[]>([]);
  readonly mesajlar = this._mesajlar.asReadonly();

  private readonly _durum = signal<SohbetDurumu>('kapali');
  readonly durum = this._durum.asReadonly();

  /** Sohbet ekrani kapaliyken gelen mesaj sayisi (sekme rozeti icin). */
  private readonly _okunmamis = signal(0);
  readonly okunmamis = this._okunmamis.asReadonly();

  /**
   * Sohbet ekrani su an gorunuyor mu?
   *
   * Bunu bilmeden okunmamis sayaci dogru calismaz: ekran acikken gelen mesaj
   * zaten okunmus sayilir. Bilgiyi bilesen bildiriyor cunku "hangi sekme
   * acik" servisin degil arayuzun sorusu.
   */
  private readonly _acik = signal(false);

  readonly bagliMi = computed(() => this._durum() === 'bagli');

  /**
   * Baglantiyi kurar ve gecmisi yukler.
   *
   * Ayni anda iki kez cagrilirsa ikincisi yok sayilir: kullanici sekmeler
   * arasinda hizlica gidip gelirse iki baglanti acilmasin.
   */
  async baglan(): Promise<void> {
    if (this.connection || this._durum() === 'baglaniyor') {
      return;
    }

    this._durum.set('baglaniyor');

    try {
      const gecmis = await firstValueFrom(
        this.http.get<ChatMessage[]>(`${this.apiUrl}/history`)
      );
      this._mesajlar.set(gecmis);
    } catch {
      // Gecmis alinamasa da canli baglantiyi denemeye devam ediyoruz.
      this.toast.bilgi('Sohbet geçmişi alınamadı.');
    }

    /**
     * accessTokenFactory: SignalR baglanirken token'i BURADAN ister.
     *
     * Neden ozel bir yol? Tarayicinin WebSocket API'si istek basligi
     * gonderemez; token "Authorization" basligiyla tasinamaz. SignalR bu
     * yuzden token'i adres satirina koyar (?access_token=...) ve sunucu
     * tarafinda JwtBearerEvents.OnMessageReceived onu oradan okur.
     *
     * Fabrika (factory) olmasi da onemli: her yeniden baglanmada TAZE token
     * alinir. Sabit bir metin verseydik, token yenilendikten sonra yeniden
     * baglanma 401 alirdi.
     */
    this.connection = new HubConnectionBuilder()
      .withUrl(`${environment.hubUrl}/chat`, {
        accessTokenFactory: () => this.auth.getAccessToken() ?? '',
        transport: HttpTransportType.WebSockets
      })
      // Baglanti koparsa kendiliginden yeniden dener (artan bekleme sureleriyle).
      .withAutomaticReconnect()
      .configureLogging(LogLevel.Warning)
      .build();

    // Sunucunun cagirdigi metotlar:
    this.connection.on('YeniMesaj', (mesaj: ChatMessage) => this.mesajEklendi(mesaj));
    this.connection.on('Hata', (mesaj: string) => this.toast.hata(mesaj));

    this.connection.onreconnecting(() => this._durum.set('baglaniyor'));
    this.connection.onreconnected(() => this._durum.set('bagli'));
    this.connection.onclose(() => this._durum.set('kapali'));

    try {
      await this.connection.start();
      this._durum.set('bagli');
    } catch {
      this._durum.set('kapali');
      this.connection = null;
      this.toast.hata('Sohbete bağlanılamadı.');
    }
  }

  /**
   * Mesaj gonderir.
   *
   * Gonderilen tek sey METIN. Kullanici adi ve kimlik gonderilmiyor; sunucu
   * onlari token'dan okuyor. Oyunun geri kalanindaki kuralin aynisi.
   */
  async gonder(metin: string): Promise<void> {
    const temiz = metin.trim();

    if (!temiz || !this.connection || this._durum() !== 'bagli') {
      return;
    }

    try {
      await this.connection.invoke('MesajGonder', temiz);
    } catch {
      this.toast.hata('Mesaj gönderilemedi.');
    }
  }

  async kapat(): Promise<void> {
    this._acik.set(false);

    if (this.connection) {
      await this.connection.stop();
      this.connection = null;
    }
    this._durum.set('kapali');
  }

  /** Sohbet ekrani acildi: sayaci sifirla ve bundan sonra gelenleri okunmus say. */
  ekraniAc(): void {
    this._acik.set(true);
    this._okunmamis.set(0);
  }

  /** Sohbet ekrani kapandi: gelen mesajlar artik sayilsin. */
  ekraniKapat(): void {
    this._acik.set(false);
  }

  private mesajEklendi(mesaj: ChatMessage): void {
    this._mesajlar.update((m) => {
      const yeni = [...m, mesaj];
      // Bellekte sinirsiz mesaj biriktirmiyoruz; ekranda son 200 yeter.
      return yeni.length > 200 ? yeni.slice(yeni.length - 200) : yeni;
    });

    // Ekran acikken gelen mesaj okunmus sayilir; sayac yalnizca kapaliyken artar.
    if (!this._acik()) {
      this._okunmamis.update((s) => s + 1);
    }
  }
}
