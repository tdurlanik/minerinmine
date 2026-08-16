import { HttpClient } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { Observable, tap } from 'rxjs';
import { environment } from '../../../environments/environment';
import { AuthResponse, LoginRequest, RegisterRequest, UserInfo } from '../models/auth.models';

/**
 * UYGULAMANIN KİMLİK MERKEZİ.
 *
 * Sorumlulukları:
 *  1. API'nin auth uçlarıyla konuşmak (register / login / refresh / revoke)
 *  2. Token'ları saklamak ve okumak (localStorage)
 *  3. "Şu an kim giriş yapmış?" sorusunu tüm uygulamaya signal ile duyurmak
 *
 * providedIn: 'root' -> Angular bu servisten uygulama boyunca TEK BİR TANE üretir
 * (singleton). Login sayfasının yazdığı bilgiyi Dashboard aynı nesneden okur.
 */
@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly http = inject(HttpClient);
  private readonly apiUrl = `${environment.apiUrl}/auth`;

  // localStorage anahtarları tek yerde tanımlı olsun ki yazım hatası olmasın.
  private static readonly ACCESS_TOKEN_KEY = 'mim_access_token';
  private static readonly REFRESH_TOKEN_KEY = 'mim_refresh_token';
  private static readonly USER_KEY = 'mim_user';

  /**
   * SIGNAL NEDİR?
   * Değeri değiştiğinde, o değeri kullanan her yeri (şablonlar dahil) otomatik
   * güncelleyen reaktif bir kutu. Angular 21 varsayılan olarak "zoneless" çalışır;
   * yani değişiklikleri zone.js ile tahmin etmez, signal'lar ile KESİN olarak bilir.
   *
   * private _currentUser -> dışarıdan değiştirilemesin diye gizli.
   * currentUser          -> dışarıya salt-okunur (readonly) olarak açılır.
   */
  private readonly _currentUser = signal<UserInfo | null>(this.readUserFromStorage());
  readonly currentUser = this._currentUser.asReadonly();

  /**
   * computed = başka signal'lardan TÜRETİLEN signal.
   * currentUser değiştiğinde bu da otomatik yeniden hesaplanır.
   */
  readonly isLoggedIn = computed(() => this._currentUser() !== null);
  readonly username = computed(() => this._currentUser()?.username ?? '');
  readonly roles = computed(() => this._currentUser()?.roles ?? []);
  readonly isAdmin = computed(() => this.roles().includes('Admin'));

  // ==========================================================================
  // API ÇAĞRILARI
  // ==========================================================================

  /**
   * Kayıt olur. Backend kayıt sonrası otomatik giriş yaptırıp token döndürür.
   *
   * tap(): RxJS operatörü. Akıştaki veriyi DEĞİŞTİRMEDEN "yan etki" yapmamızı
   * sağlar — burada gelen token'ları kaydediyoruz. Bileşen sadece subscribe eder,
   * token saklama detayıyla hiç ilgilenmez.
   */
  register(request: RegisterRequest): Observable<AuthResponse> {
    return this.http
      .post<AuthResponse>(`${this.apiUrl}/register`, request)
      .pipe(tap((response) => this.saveSession(response)));
  }

  /** Giriş yapar ve oturumu kaydeder. */
  login(request: LoginRequest): Observable<AuthResponse> {
    return this.http
      .post<AuthResponse>(`${this.apiUrl}/login`, request)
      .pipe(tap((response) => this.saveSession(response)));
  }

  /** Süresi dolan access token'ı yeniler (backend eskisini iptal edip yenisini verir). */
  refreshToken(): Observable<AuthResponse> {
    return this.http
      .post<AuthResponse>(`${this.apiUrl}/refresh-token`, { refreshToken: this.getRefreshToken() })
      .pipe(tap((response) => this.saveSession(response)));
  }

  /**
   * Çıkış yapar.
   *
   * SIRALAMA BURADA KRİTİKTİR — bu projede bir hataya sebep oldu:
   * Önce yerel oturumu SENKRON olarak temizliyoruz, sunucuya haber vermeyi
   * SONRA yapıyoruz.
   *
   * Neden? Bileşen çıkış butonunda şunu yapıyor:
   *     authService.logout();
   *     router.navigateByUrl('/login');
   * Temizlik HTTP cevabını bekleseydi, navigateByUrl çalıştığı anda isLoggedIn()
   * hâlâ true olurdu; /login rotasındaki guestGuard "zaten giriş yapmış" deyip
   * kullanıcıyı dashboard'a geri gönderirdi. Cevap sonradan gelir, token silinir
   * ama kullanıcı ekranda takılı kalırdı.
   *
   * Ayrıca bu sıralama daha doğrudur: kullanıcı "çıkış" dediyse, sunucu kapalı
   * olsa bile çıkmış olmalıdır.
   */
  logout(): void {
    const refreshToken = this.getRefreshToken();

    // 1) Yerel oturumu ANINDA sil -> isLoggedIn() artık false.
    this.clearSession();

    // 2) Sunucuya refresh token'ı iptal ettir (arka planda).
    //    subscribe() çağırmazsak istek HİÇ gönderilmez: HttpClient'ın döndürdüğü
    //    Observable "soğuktur" (cold), yani abone olunana kadar çalışmaz.
    //    Hata olsa da umursamıyoruz; yerel oturum zaten kapandı.
    if (refreshToken) {
      this.http.post(`${this.apiUrl}/revoke-token`, { refreshToken }).subscribe({
        error: () => {
          /* sunucuya ulaşılamadı; yerel çıkış yine de geçerli */
        }
      });
    }
  }

  // ==========================================================================
  // TOKEN SAKLAMA
  //
  // GÜVENLİK NOTU (staj sunumunda sorulabilir):
  // Token'ı localStorage'da tutmak en kolay yöntemdir ama XSS saldırısına açıktır:
  // sayfaya kötü niyetli bir script sızarsa token'ı okuyabilir.
  // Daha güvenli alternatif: refresh token'ı sunucunun HttpOnly + Secure cookie
  // olarak yazması (JavaScript o cookie'yi okuyamaz). Öğrenme amaçlı olduğu için
  // burada localStorage tercih edildi.
  // ==========================================================================

  getAccessToken(): string | null {
    return localStorage.getItem(AuthService.ACCESS_TOKEN_KEY);
  }

  getRefreshToken(): string | null {
    return localStorage.getItem(AuthService.REFRESH_TOKEN_KEY);
  }

  /** Başarılı bir auth cevabını localStorage'a ve signal'a yazar. */
  private saveSession(response: AuthResponse): void {
    const user: UserInfo = {
      userId: response.userId,
      username: response.username,
      email: response.email,
      roles: response.roles
    };

    localStorage.setItem(AuthService.ACCESS_TOKEN_KEY, response.accessToken);
    localStorage.setItem(AuthService.REFRESH_TOKEN_KEY, response.refreshToken);
    localStorage.setItem(AuthService.USER_KEY, JSON.stringify(user));

    // Signal'ı güncelle -> bu değeri kullanan tüm şablonlar anında yenilenir.
    this._currentUser.set(user);
  }

  /** Tüm oturum izlerini siler. */
  private clearSession(): void {
    localStorage.removeItem(AuthService.ACCESS_TOKEN_KEY);
    localStorage.removeItem(AuthService.REFRESH_TOKEN_KEY);
    localStorage.removeItem(AuthService.USER_KEY);
    this._currentUser.set(null);
  }

  /**
   * Sayfa yenilendiğinde (F5) uygulama sıfırdan yüklenir ve hafızadaki her şey
   * kaybolur. Bu metot, servis ilk oluşturulurken localStorage'a bakıp oturumu
   * geri yükler — kullanıcı her F5'te login'e atılmasın diye.
   */
  private readUserFromStorage(): UserInfo | null {
    const raw = localStorage.getItem(AuthService.USER_KEY);
    const token = localStorage.getItem(AuthService.ACCESS_TOKEN_KEY);

    // Kullanıcı bilgisi var ama token yoksa (ya da tersi) veri tutarsızdır: güvenme.
    if (!raw || !token) {
      return null;
    }

    try {
      return JSON.parse(raw) as UserInfo;
    } catch {
      // localStorage elle kurcalanmış olabilir; bozuk veriye güvenmeyip temizliyoruz.
      localStorage.removeItem(AuthService.USER_KEY);
      return null;
    }
  }
}
