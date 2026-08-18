import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';
import { AdminPlayerList, SuspiciousEntry } from '../models/meta.models';

/**
 * Yonetim islemleri.
 *
 * DIKKAT: Bu servisin varligi yetki VERMEZ. Uclar sunucuda
 * [Authorize(Roles = "Admin")] ile korunuyor; Player rolundeki bir kullanici
 * bu metotlari cagirsa 403 alir. Arayuzdeki gizleme yalnizca gorsel bir tercih.
 */
@Injectable({ providedIn: 'root' })
export class AdminService {
  private readonly http = inject(HttpClient);
  private readonly apiUrl = `${environment.apiUrl}/admin`;

  getPlayers(search: string, page: number, pageSize = 20): Observable<AdminPlayerList> {
    const q = new URLSearchParams({ page: String(page), pageSize: String(pageSize) });
    if (search) {
      q.set('search', search);
    }
    return this.http.get<AdminPlayerList>(`${this.apiUrl}/players?${q}`);
  }

  adjust(targetUserId: number, resourceTypeId: number, delta: number): Observable<unknown> {
    return this.http.post(`${this.apiUrl}/adjust`, { targetUserId, resourceTypeId, delta });
  }

  getSuspicious(minutes = 60, minGain = 100000): Observable<SuspiciousEntry[]> {
    return this.http.get<SuspiciousEntry[]>(
      `${this.apiUrl}/suspicious?minutes=${minutes}&minGain=${minGain}`
    );
  }
}
