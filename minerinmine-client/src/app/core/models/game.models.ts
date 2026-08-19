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

  /** Madencilerin bu tesiste saniyede urettigi miktar (guclendirmeler dahil). */
  autoPerSecond: number;
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

  miners: Miner[];
  upgrades: Upgrade[];

  /** Henuz toplanmamis, madencilerin urettigi kaynaklar. */
  pending: PendingProduction[];

  /** Sahip olunmayan ama satin alinabilecek tesisler. */
  purchasable: PurchasableFacility[];
}

/**
 * Satin alinabilir tesis.
 *
 * Tesisler sadece parayla degil ILERLEMEYLE de kapilanir: onceki tesisin
 * belirli bir seviyeye ulasmasi gerekir. isUnlocked false ise kilitli gosterilir.
 */
export interface PurchasableFacility {
  facilityTypeId: number;
  code: string;
  name: string;
  resourceCode: string;
  resourceName: string;
  cost: number;
  startProduction: number;
  requiredFacilityName: string | null;
  requiredLevel: number;
  requiredCurrentLevel: number;
  isUnlocked: boolean;
}

export interface BuyFacilityResult {
  facilityName: string;
  cost: number;
  newBalance: number;
  serverTime: string;
}

export interface Miner {
  facilityTypeId: number;
  minerTypeId: number;
  code: string;
  name: string;
  hireCost: number;
  maxCount: number;
  clickCode: string;
  clickName: string;
  count: number;

  /** Kullandigi kazma turu acilmamissa ise alinamaz. */
  isAvailable: boolean;
  perSecondEach: number;
}

export interface Upgrade {
  upgradeTypeId: number;
  code: string;
  name: string;
  description: string | null;
  effectType: string;
  effectValue: number;
  maxLevel: number;
  level: number;
  nextLevelCost: number | null;
}

export interface PendingProduction {
  resourceTypeId: number;
  code: string;
  name: string;
  amount: number;
}

export interface CollectedResource {
  code: string;
  name: string;
  amount: number;
  newBalance: number;
}

export interface HireMinerResult {
  newCount: number;
  cost: number;
  newBalance: number;
  serverTime: string;
}

export interface SellRequest {
  resourceTypeId: number;
  amount: number;
}

export interface SellResult {
  soldAmount: number;
  earned: number;
  kristalBalance: number;
  resourceBalance: number;
  serverTime: string;
}

export interface PurchaseResult {
  newLevel: number;
  cost: number;
  newBalance: number;
  serverTime: string;
}

export interface UnlockResult {
  cost: number;
  newBalance: number;
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

  /** Bugun kalan hizlandirma hakki (gunluk sinir). */
  remainingSkips: number;
  serverTime: string;
}
