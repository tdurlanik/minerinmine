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
