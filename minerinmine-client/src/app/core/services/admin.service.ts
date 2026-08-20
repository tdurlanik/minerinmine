import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';
import {
  AdminActionLog,
  AdminAdjustResult,
  AdminPlayerDetail,
  AdminPlayerList,
  AdminRevokeSessionsResult,
  AdminSetActiveResult,
  AdminSetRoleResult,
  EconomyReport,
  SuspiciousEntry
} from '../models/meta.models';

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

  getPlayerDetail(userId: number): Observable<AdminPlayerDetail> {
    return this.http.get<AdminPlayerDetail>(`${this.apiUrl}/players/${userId}`);
  }

  adjust(targetUserId: number, resourceTypeId: number, delta: number): Observable<AdminAdjustResult> {
    return this.http.post<AdminAdjustResult>(`${this.apiUrl}/adjust`, {
      targetUserId,
      resourceTypeId,
      delta
    });
  }

  setActive(userId: number, isActive: boolean): Observable<AdminSetActiveResult> {
    return this.http.post<AdminSetActiveResult>(`${this.apiUrl}/players/${userId}/active`, {
      isActive
    });
  }

  setRole(userId: number, roleName: string, grant: boolean): Observable<AdminSetRoleResult> {
    return this.http.post<AdminSetRoleResult>(`${this.apiUrl}/players/${userId}/role`, {
      roleName,
      grant
    });
  }

  revokeSessions(userId: number): Observable<AdminRevokeSessionsResult> {
    return this.http.post<AdminRevokeSessionsResult>(
      `${this.apiUrl}/players/${userId}/revoke-sessions`,
      {}
    );
  }

  /**
   * Ekonomi sagligi raporu.
   *
   * Faucet/sink dengesi, mekanik kullanimi ve ilerleme dagilimi — hepsi
   * Transactions gunlugunden turetiliyor.
   */
  getEconomy(days = 7): Observable<EconomyReport> {
    return this.http.get<EconomyReport>(`${this.apiUrl}/economy?days=${days}`);
  }

  /** Son yonetici mudahaleleri (denetim izi). */
  getActionLog(top = 50): Observable<AdminActionLog[]> {
    return this.http.get<AdminActionLog[]>(`${this.apiUrl}/actions?top=${top}`);
  }

  getSuspicious(minutes = 60, minGain = 100000): Observable<SuspiciousEntry[]> {
    return this.http.get<SuspiciousEntry[]>(
      `${this.apiUrl}/suspicious?minutes=${minutes}&minGain=${minGain}`
    );
  }
}
