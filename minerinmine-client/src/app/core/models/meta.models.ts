/** Gun 5: siralama, yonetim ve reklam odulu tipleri. */

export interface LeaderboardEntry {
  position: number;
  username: string;
  totalWealth: number;
  totalLevels: number;
  totalMiners: number;
  /** Bu satir bana mi ait? (arayuz vurgular) */
  isMe: boolean;
}

export interface MyRank {
  position: number;
  username: string;
  totalWealth: number;
  totalPlayers: number;
}

export interface Leaderboard {
  top: LeaderboardEntry[];
  /** Ilk N'de olmasam bile kendi siram. */
  me: MyRank | null;
}

export interface AdminPlayer {
  userId: number;
  username: string;
  email: string;
  isActive: boolean;
  createdAt: string;
  lastLoginAt: string | null;
  totalWealth: number;
  kristal: number;
  totalLevels: number;
  totalMiners: number;
  roles: string | null;
}

export interface AdminPlayerList {
  players: AdminPlayer[];
  totalCount: number;
  page: number;
  pageSize: number;
}

export interface SuspiciousEntry {
  userId: number;
  username: string;
  resourceCode: string;
  gain: number;
  transactionCount: number;
  firstAt: string;
  lastAt: string;
}

export interface AdRewardResult {
  /** Bu bildirim daha once islendiyse true; odul tekrar verilmez. */
  alreadyProcessed: boolean;
  amount: number;
  newBalance: number;
  serverTime: string;
}
