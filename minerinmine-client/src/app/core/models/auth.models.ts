/**
 * API ile konuşurken kullanılan veri tipleri.
 *
 * Bu arayüzler (interface) backend'deki DTO sınıflarının birebir aynısıdır.
 * TypeScript'te interface'ler derleme sonrası JavaScript'te KAYBOLUR — çalışma
 * zamanında hiçbir maliyeti yoktur. Tek görevleri, yanlış alan adı yazdığımızda
 * editörün bizi uyarmasıdır.
 *
 * DİKKAT: Alan isimleri camelCase. Çünkü .NET, JSON'a çevirirken property
 * isimlerini varsayılan olarak camelCase yapar (Username -> username).
 */

/** POST /api/auth/register gövdesi */
export interface RegisterRequest {
  username: string;
  email: string;
  password: string;
}

/** POST /api/auth/login gövdesi */
export interface LoginRequest {
  /** Kullanıcı adı VEYA e-posta olabilir */
  loginInput: string;
  password: string;
}

/** register / login / refresh-token uçlarının ortak cevabı */
export interface AuthResponse {
  userId: number;
  username: string;
  email: string;
  roles: string[];
  accessToken: string;
  refreshToken: string;
  accessTokenExpiresAt: string;
}

/** GET /api/users/me cevabı */
export interface UserInfo {
  userId: number;
  username: string;
  email: string;
  roles: string[];
}

/** API'nin hata durumunda döndürdüğü gövde: { "message": "..." } */
export interface ApiError {
  message: string;
}
