import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';
import { Leaderboard } from '../models/meta.models';

/** Oyuncu siralamasi. */
@Injectable({ providedIn: 'root' })
export class LeaderboardService {
  private readonly http = inject(HttpClient);

  getTop(top = 25): Observable<Leaderboard> {
    return this.http.get<Leaderboard>(`${environment.apiUrl}/leaderboard?top=${top}`);
  }
}
