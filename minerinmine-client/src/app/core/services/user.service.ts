import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';
import { UserInfo } from '../models/auth.models';

/**
 * Korumalı kullanıcı uçlarıyla konuşan servis.
 *
 * DİKKAT: Burada HİÇBİR YERDE token eklemiyoruz!
 * `Authorization: Bearer ...` başlığını jwtInterceptor otomatik ekliyor.
 * Interceptor'ın değeri tam olarak budur: iş yapan kod token'dan habersiz kalır.
 */
@Injectable({ providedIn: 'root' })
export class UserService {
  private readonly http = inject(HttpClient);
  private readonly apiUrl = `${environment.apiUrl}/users`;

  /** GET /api/users/me — token geçerliyse 200, değilse 401 döner. */
  getMe(): Observable<UserInfo> {
    return this.http.get<UserInfo>(`${this.apiUrl}/me`);
  }

  /** GET /api/users/admin-only — sadece Admin rolü 200 alır, Player 403 alır. */
  getAdminOnly(): Observable<{ message: string; username: string }> {
    return this.http.get<{ message: string; username: string }>(`${this.apiUrl}/admin-only`);
  }
}
