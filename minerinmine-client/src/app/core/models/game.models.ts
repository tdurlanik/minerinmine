/**
 * Oyun ekraninin veri tipleri — backend'deki GameDtos.cs ile birebir aynidir.
 *
 * DIKKAT: MineRequest icinde "kazanc" alani YOKTUR ve olmayacaktir.
 * Istemci yalnizca niyet bildirir; ne kazandigini sunucu soyler.
 */

export interface Resource {
  resourceTypeId: number;
  code: string;
  name: string;
  amount: number;
  sellValue: number;
  isCurrency: boolean;
}

export interface Facility {
  facilityTypeId: number;
  code: string;
  name: string;
  maxLevel: number;
  resourceCode: string;
  resourceName: string;
  level: number;
  currentProduction: number;
  nextLevelCost: number | null;
  nextLevelMinutes: number | null;
  nextLevelProduction: number | null;

  /** Devam eden gelistirmeyi aninda bitirmenin O ANKI bedeli; gelistirme yoksa null. */
  instantFinishCost: number | null;
  upgradeCompletesAt: string | null;
  lastCollectedAt: string;
}

export interface ClickType {
  clickTypeId: number;
  code: string;
  name: string;
  cooldownSeconds: number;
  yieldMultiplier: number;
  unlockCost: number;
  isUnlocked: boolean;
}

export interface FacilityClick {
  facilityTypeId: number;
  clickTypeId: number;
  lastClickAt: string | null;
  nextAvailableAt: string;
}

export interface PlayerState {
  resources: Resource[];
  facilities: Facility[];
  clickTypes: ClickType[];
  facilityClicks: FacilityClick[];
  serverTime: string;

  /** Bu istek sirasinda suresi dolup tamamlanan gelistirme sayisi (tembel tamamlama). */
  completedUpgrades: number;
}

/** Sadece "nerede, neyle kazdim" — miktar yok. */
export interface MineRequest {
  facilityTypeId: number;
  clickTypeId: number;
}

export interface MineResult {
  gained: number;
  newBalance: number;
  resourceTypeId: number;
  nextAvailableAt: string;
  serverTime: string;
}

/** Gelistirme baslatma sonucu. */
export interface UpgradeStarted {
  targetLevel: number;
  cost: number;
  newBalance: number;
  durationMinutes: number;
  upgradeCompletesAt: string;
  serverTime: string;
}

/** Aninda bitirme sonucu. */
export interface UpgradeFinished {
  newLevel: number;
  cost: number;
  newBalance: number;
  skippedSeconds: number;
  serverTime: string;
}
