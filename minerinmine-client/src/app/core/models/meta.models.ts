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

// ============================================================================
// YONETIM PANELI — OYUNCU DETAYI (GET /api/admin/players/{id})
// ============================================================================

export interface AdminPlayerInfo {
  userId: number;
  username: string;
  email: string;
  isActive: boolean;
  createdAt: string;
  lastLoginAt: string | null;
  roles: string | null;
  totalWealth: number;
  /** Iptal edilmemis ve suresi dolmamis refresh token sayisi. */
  activeSessions: number;
  transactionCount: number;
}

export interface AdminResource {
  resourceTypeId: number;
  code: string;
  name: string;
  amount: number;
  isCurrency: boolean;
  sellValue: number;
}

export interface AdminFacility {
  facilityTypeId: number;
  facilityName: string;
  level: number;
  maxLevel: number;
  resourceName: string;
  upgradeCompletesAt: string | null;
  minerCount: number;
}

export interface AdminMiner {
  minerTypeId: number;
  minerName: string;
  facilityName: string;
  count: number;
}

export interface AdminTransaction {
  id: number;
  resourceName: string;
  amount: number;
  balanceAfter: number;
  reason: string;
  referenceId: number | null;
  createdAt: string;
}

export interface AdminPlayerDetail {
  player: AdminPlayerInfo | null;
  resources: AdminResource[];
  facilities: AdminFacility[];
  miners: AdminMiner[];
  transactions: AdminTransaction[];
}

export interface AdminSetActiveResult {
  isActive: boolean;
  revokedSessions: number;
  serverTime: string;
}

export interface AdminSetRoleResult {
  roleName: string;
  isGranted: boolean;
  serverTime: string;
}

export interface AdminRevokeSessionsResult {
  revokedSessions: number;
  serverTime: string;
}

export interface AdminAdjustResult {
  newBalance: number;
  delta: number;
  serverTime: string;
}

// ============================================================================
// EKONOMI SAGLIGI (GET /api/admin/economy)
// ============================================================================

export interface EconomySummary {
  totalPlayers: number;
  activeToday: number;
  activeInPeriod: number;
  newPlayers: number;
  /** Oyuncularin elinde duran toplam Kristal. */
  circulatingKristal: number;
  totalWealth: number;
  /** Donemde ekonomiye GIREN Kristal. */
  periodFaucet: number;
  /** Donemde ekonomiden CIKAN Kristal. */
  periodSink: number;
  days: number;
}

export interface EconomyDaily {
  gun: string;
  faucet: number;
  sink: number;
  net: number;
  activePlayers: number;
}

export interface EconomyReason {
  reason: string;
  /** +1 kaynak (faucet), -1 gider (sink). */
  direction: number;
  total: number;
  times: number;
  playerCount: number;
}

export interface EconomyFacility {
  facilityTypeId: number;
  facilityName: string;
  ownerCount: number;
  avgLevel: number;
  maxLevel: number;
  capLevel: number;
}

export interface EconomyClick {
  clickTypeId: number;
  clickName: string;
  unlockCost: number;
  unlockedBy: number;
  totalPlayers: number;
}

export interface EconomyReport {
  summary: EconomySummary;
  daily: EconomyDaily[];
  reasons: EconomyReason[];
  facilities: EconomyFacility[];
  clicks: EconomyClick[];
}

/**
 * Yonetici islem gunlugu satiri.
 *
 * Iki kaynaktan birlesir: AdminActions (dondurma/rol/oturum) ve
 * Transactions'taki ADMIN_ADJUST kayitlari (kaynak duzeltmeleri).
 */
export interface AdminActionLog {
  createdAt: string;
  adminUsername: string;
  targetUserId: number;
  targetUsername: string;
  action: string;
  detail: string | null;
}
