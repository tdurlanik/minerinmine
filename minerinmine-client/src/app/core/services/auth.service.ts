import { HttpClient } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { Observable, catchError, map, of, tap } from 'rxjs';
import { environment } from '../../../environments/environment';
import { AuthResponse, LoginRequest, RegisterRequest, UserInfo } from '../models/auth.models';

/**
 * UYGULAMANIN KİMLİK MERKEZİ.
 *
 * TOKEN SAKLAMA STRATEJİSİ — iki token, iki farklı yer:
 *
 *   Access token (15 dk)  -> sessionStorage
 *   Refresh token (7 gün) -> HttpOnly cookie (bu kod onu HİÇ GÖREMEZ)
 *
 * NEDEN?
 * XSS ile sayfaya sızan bir script sessionStorage'ı okuyabilir. Eskiden refresh
 * token da localStorage'daydı: saldırgan onu alınca 7 gün boyunca istediği zaman
 * yeni access token üretebiliyordu — yani KALICI hesap ele geçirme.
 *
 * Şimdi refresh token HttpOnly cookie'de. JavaScript onu okuyamaz; bu dosyada
 * bile bir "refreshToken" değişkeni yok. Saldırganın alabileceği en fazla şey
 * 15 dakikalık bir access token'dır ve onu yenileyemez.
 *
 * NEDEN sessionStorage, localStorage değil?
 *   - Sekme kapanınca silinir  -> paylaşılan bilgisayarda oturum kalmaz
 *   - F5'e dayanır             -> sayfa yenilemede yeniden giriş gerekmez
 *   - Zaten 15 dakikalık       -> uzun süre durması anlamsız
 *
 * Oturumun kalıcılığını cookie sağlıyor: yeni sekmede sessionStorage boş olur
 * ama cookie durduğu için restoreSession() sessizce yeni access token alır.
 */
@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly http = inject(HttpClient);
  private readonly apiUrl = `${environment.apiUrl}/auth`;

  private static readonly ACCESS_TOKEN_KEY = 'mim_access_token';
  private static readonly USER_KEY = 'mim_user';

  /**
   * withCredentials: true — tarayıcının HttpOnly cookie'yi bu isteklerle birlikte
   * göndermesini (ve Set-Cookie cevabını saklamasını) sağlar. Farklı port =
   * farklı origin olduğu için bu bayrak olmadan cookie hiç taşınmaz.
   *
   * Yalnızca /api/auth uçlarında gerekli; oyun uçları Authorization başlığı
   * kullanır ve cookie taşımaz (bu yüzden CSRF'e de bağışıktır).
   */
  private static readonly WITH_COOKIE = { withCredentials: true };

  private readonly _currentUser = signal<UserInfo | null>(this.readUserFromStorage());
  readonly currentUser = this._currentUser.asReadonly();

  readonly isLoggedIn = computed(() => this._currentUser() !== null);
  readonly username = computed(() => this._currentUser()?.username ?? '');
  readonly roles = computed(() => this._currentUser()?.roles ?? []);
  readonly isAdmin = computed(() => this.roles().includes('Admin'));

  // ==========================================================================
  // API ÇAĞRILARI
  // ==========================================================================

  register(request: RegisterRequest): Observable<AuthResponse> {
    return this.http
      .post<AuthResponse>(`${this.apiUrl}/register`, request, AuthService.WITH_COOKIE)
      .pipe(tap((response) => this.saveSession(response)));
  }

  login(request: LoginRequest): Observable<AuthResponse> {
    return this.http
      .post<AuthResponse>(`${this.apiUrl}/login`, request, AuthService.WITH_COOKIE)
      .pipe(tap((response) => this.saveSession(response)));
  }

  /**
   * Yeni access token alır.
   *
   * DİKKAT: İstek gövdesi BOŞ. Refresh token'ı göndermiyoruz çünkü elimizde yok —
   * tarayıcı onu cookie olarak kendisi ekliyor. Bu, tasarımın en güzel tarafı:
   * gönderemediğimiz bir şey çalınamaz da.
   */
  refreshToken(): Observable<AuthResponse> {
    return this.http
      .post<AuthResponse>(`${this.apiUrl}/refresh-token`, {}, AuthService.WITH_COOKIE)
      .pipe(tap((response) => this.saveSession(response)));
  }

  /**
   * SESSİZ OTURUM KURTARMA — uygulama açılırken bir kez çalışır.
   *
   * Yeni sekmede sessionStorage boştur ama cookie hâlâ duruyor olabilir.
   * O yüzden token yoksa sessizce yenilemeyi deniyoruz:
   *   - Başarılı  -> kullanıcı hiç fark etmeden giriş yapmış olur
   *   - Başarısız -> giriş ekranı (hata gösterilmez, bu normal bir durum)
   *
   * Hiçbir koşulda hata FIRLATMAZ; aksi halde uygulama açılışı bloke olurdu.
   */
  restoreSession(): Observable<boolean> {
    if (this.getAccessToken()) {
      return of(true);          // aynı sekmede F5: token zaten elimizde
    }

    return this.refreshToken().pipe(
      map(() => true),
      catchError(() => {
        this.clearSession();    // cookie yok ya da geçersiz: temiz başla
        return of(false);
      })
    );
  }

  /**
   * Çıkış yapar.
   *
   * Yerel durumu ÖNCE ve senkron temizliyoruz (yönlendirme hemen çalışsın diye),
   * sunucuya haber vermeyi sonra yapıyoruz. Sunucu hem veritabanındaki token'ı
   * iptal eder hem cookie'yi siler.
   */
  logout(): void {
    this.clearSession();

    this.http.post(`${this.apiUrl}/revoke-token`, {}, AuthService.WITH_COOKIE).subscribe({
      error: () => {
        /* sunucuya ulaşılamadı; yerel çıkış yine de geçerli */
      }
    });
  }

  // ==========================================================================
  // TOKEN SAKLAMA
  // ==========================================================================

  getAccessToken(): string | null {
    return sessionStorage.getItem(AuthService.ACCESS_TOKEN_KEY);
  }

  private saveSession(response: AuthResponse): void {
    const user: UserInfo = {
      userId: response.userId,
      username: response.username,
      email: response.email,
      roles: response.roles
    };

    // Refresh token BURADA YOK — cevabın gövdesinde hiç gelmiyor.
    sessionStorage.setItem(AuthService.ACCESS_TOKEN_KEY, response.accessToken);
    sessionStorage.setItem(AuthService.USER_KEY, JSON.stringify(user));

    this._currentUser.set(user);
  }

  private clearSession(): void {
    sessionStorage.removeItem(AuthService.ACCESS_TOKEN_KEY);
    sessionStorage.removeItem(AuthService.USER_KEY);
    this._currentUser.set(null);
  }

  /**
   * Sayfa yenilendiğinde (F5) aynı sekmede oturumu geri yükler.
   * Yeni bir sekmede burası boş döner; devreye restoreSession() girer.
   */
  private readUserFromStorage(): UserInfo | null {
    const raw = sessionStorage.getItem(AuthService.USER_KEY);
    const token = sessionStorage.getItem(AuthService.ACCESS_TOKEN_KEY);

    if (!raw || !token) {
      return null;
    }

    try {
      return JSON.parse(raw) as UserInfo;
    } catch {
      sessionStorage.removeItem(AuthService.USER_KEY);
      return null;
    }
  }
}
