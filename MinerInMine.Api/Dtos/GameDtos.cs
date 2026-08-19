using System.ComponentModel.DataAnnotations;

namespace MinerInMine.Api.Dtos;

// ============================================================================
// Oyun ekraninin ihtiyaci olan veri sozlesmeleri.
//
// DIKKAT: Istemciden gelen istekte KAZANC MIKTARI YOKTUR.
// Istemci yalnizca "hangi tesiste, hangi kazmayla" bilgisini gonderir;
// ne kazandigini sunucu hesaplar ve MineResultDto ile geri bildirir.
// Sunucu otoritesinin sozlesme seviyesindeki karsiligi budur.
// ============================================================================

/// <summary>POST /api/game/mine istegi — sadece NIYET bildirir.</summary>
public class MineRequest
{
    [Required]
    public int FacilityTypeId { get; set; }

    [Required]
    public int ClickTypeId { get; set; }
}

/// <summary>Kazma sonucu — tum degerler sunucuda hesaplanmistir.</summary>
public class MineResultDto
{
    public long Gained { get; set; }
    public long NewBalance { get; set; }
    public int ResourceTypeId { get; set; }

    /// <summary>Bu kazma turunun bu tesiste tekrar hazir olacagi an (UTC).</summary>
    public DateTime NextAvailableAt { get; set; }

    /// <summary>Sunucunun o anki UTC saati. Istemci geri sayimi buna gore duzeltir.</summary>
    public DateTime ServerTime { get; set; }
}

public class ResourceDto
{
    public int ResourceTypeId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public long Amount { get; set; }
    public int SellValue { get; set; }
    public bool IsCurrency { get; set; }
}

public class FacilityDto
{
    public int FacilityTypeId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public int MaxLevel { get; set; }
    public string ResourceCode { get; set; } = string.Empty;
    public string ResourceName { get; set; } = string.Empty;
    public int Level { get; set; }
    public long CurrentProduction { get; set; }

    /// <summary>Son seviyedeyse null.</summary>
    public long? NextLevelCost { get; set; }
    public int? NextLevelMinutes { get; set; }

    /// <summary>Bir sonraki seviyedeki uretim — "1 -> 2 demir" karsilastirmasi icin.</summary>
    public long? NextLevelProduction { get; set; }

    /// <summary>Devam eden gelistirmeyi aninda bitirmenin O ANKI bedeli; gelistirme yoksa null.</summary>
    public long? InstantFinishCost { get; set; }

    /// <summary>Devam eden bir gelistirme varsa bitis ani, yoksa null.</summary>
    public DateTime? UpgradeCompletesAt { get; set; }
    public DateTime LastCollectedAt { get; set; }

    /// <summary>Madencilerin bu tesiste saniyede urettigi miktar (guclendirmeler dahil).</summary>
    public decimal AutoPerSecond { get; set; }
}

public class ClickTypeDto
{
    public int ClickTypeId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public int CooldownSeconds { get; set; }
    public decimal YieldMultiplier { get; set; }
    public long UnlockCost { get; set; }
    public bool IsUnlocked { get; set; }
}

/// <summary>Tesis x kazma turu icin bekleme durumu (bekleme TESIS bazlidir).</summary>
public class FacilityClickDto
{
    public int FacilityTypeId { get; set; }
    public int ClickTypeId { get; set; }
    public DateTime? LastClickAt { get; set; }
    public DateTime NextAvailableAt { get; set; }
}

/// <summary>GET /api/game/state — oyun ekraninin tamami tek cagrida.</summary>
public class PlayerStateDto
{
    public List<ResourceDto> Resources { get; set; } = new();
    public List<FacilityDto> Facilities { get; set; } = new();
    public List<ClickTypeDto> ClickTypes { get; set; } = new();
    public List<FacilityClickDto> FacilityClicks { get; set; } = new();
    public DateTime ServerTime { get; set; }

    /// <summary>Bu istek sirasinda suresi dolup tamamlanan gelistirme sayisi (tembel tamamlama).</summary>
    public int CompletedUpgrades { get; set; }

    public List<MinerDto> Miners { get; set; } = new();
    public List<UpgradeDto> Upgrades { get; set; } = new();
    public List<PendingProductionDto> Pending { get; set; } = new();

    /// <summary>Sahip olunmayan ama satin alinabilecek tesisler.</summary>
    public List<PurchasableFacilityDto> Purchasable { get; set; } = new();
}

/// <summary>Gelistirme baslatma sonucu.</summary>
public class UpgradeStartedDto
{
    public int TargetLevel { get; set; }
    public long Cost { get; set; }
    public long NewBalance { get; set; }
    public int DurationMinutes { get; set; }
    public DateTime UpgradeCompletesAt { get; set; }
    public DateTime ServerTime { get; set; }
}

/// <summary>Aninda bitirme sonucu.</summary>
public class UpgradeFinishedDto
{
    public int NewLevel { get; set; }
    public long Cost { get; set; }
    public long NewBalance { get; set; }

    /// <summary>Odeme ile atlanan sure — "3 dakika kazandin" bildirimi icin.</summary>
    public int SkippedSeconds { get; set; }

    /// <summary>
    /// Bugun kalan hizlandirma hakki.
    ///
    /// Gunluk sinir var cunku tek para birimi kullaniyoruz: oyuncu atlamak icin
    /// odeyecegi Kristal'i kendisi uretiyor. Simulasyon, sinirsiz atlamada
    /// oyunun 7 dakikada bittigini olctu.
    /// </summary>
    public int RemainingSkips { get; set; }

    public DateTime ServerTime { get; set; }
}

// ============================================================================
// GUN 4: Otomasyon ve ekonomi
// ============================================================================

/// <summary>Bir tesiste bir madenci kademesinin durumu.</summary>
public class MinerDto
{
    public int FacilityTypeId { get; set; }
    public int MinerTypeId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public long HireCost { get; set; }
    public int MaxCount { get; set; }
    public string ClickCode { get; set; } = string.Empty;
    public string ClickName { get; set; } = string.Empty;
    public int Count { get; set; }

    /// <summary>Bu madencinin kullandigi kazma turu acilmis mi? Degilse ise alinamaz.</summary>
    public bool IsAvailable { get; set; }

    /// <summary>Tek bir madencinin saniyelik uretimi (mevcut tesis seviyesinde).</summary>
    public decimal PerSecondEach { get; set; }
}

public class UpgradeDto
{
    public int UpgradeTypeId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string EffectType { get; set; } = string.Empty;
    public decimal EffectValue { get; set; }
    public int MaxLevel { get; set; }
    public int Level { get; set; }
    public long? NextLevelCost { get; set; }
}

/// <summary>Henuz toplanmamis, madencilerin urettigi kaynak.</summary>
public class PendingProductionDto
{
    public int ResourceTypeId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public long Amount { get; set; }
}

public class CollectedResourceDto
{
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public long Amount { get; set; }
    public long NewBalance { get; set; }
}

public class HireMinerResultDto
{
    public int NewCount { get; set; }
    public long Cost { get; set; }
    public long NewBalance { get; set; }
    public DateTime ServerTime { get; set; }
}

/// <summary>Satis istegi. Miktar istemciden gelir ama sunucu bakiyeyi dogrular.</summary>
public class SellRequest
{
    [Required]
    public int ResourceTypeId { get; set; }

    [Required]
    [Range(1, long.MaxValue, ErrorMessage = "Satış miktarı en az 1 olmalıdır.")]
    public long Amount { get; set; }
}

public class SellResultDto
{
    public long SoldAmount { get; set; }
    public long Earned { get; set; }
    public long KristalBalance { get; set; }
    public long ResourceBalance { get; set; }
    public DateTime ServerTime { get; set; }
}

public class PurchaseResultDto
{
    public int NewLevel { get; set; }
    public long Cost { get; set; }
    public long NewBalance { get; set; }
    public DateTime ServerTime { get; set; }
}

public class UnlockResultDto
{
    public long Cost { get; set; }
    public long NewBalance { get; set; }
    public DateTime ServerTime { get; set; }
}

/// <summary>
/// Henuz sahip olunmayan, satin alinabilecek tesis.
///
/// Tesisler sadece parayla degil ILERLEMEYLE de kapilanir: onceki tesisin
/// belirli bir seviyeye ulasmasi gerekir. Bu sayede yeni tesis bir hedef olur.
/// </summary>
public class PurchasableFacilityDto
{
    public int FacilityTypeId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string ResourceCode { get; set; } = string.Empty;
    public string ResourceName { get; set; } = string.Empty;
    public long Cost { get; set; }
    public long StartProduction { get; set; }

    /// <summary>On kosul olan tesisin adi; baslangic tesisi icin null.</summary>
    public string? RequiredFacilityName { get; set; }
    public int RequiredLevel { get; set; }
    public int RequiredCurrentLevel { get; set; }

    /// <summary>On kosul saglandi mi? false ise arayuz kilitli gosterir.</summary>
    public bool IsUnlocked { get; set; }
}

public class BuyFacilityResultDto
{
    public string FacilityName { get; set; } = string.Empty;
    public long Cost { get; set; }
    public long NewBalance { get; set; }
    public DateTime ServerTime { get; set; }
}
