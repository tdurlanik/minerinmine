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

    /// <summary>Devam eden bir gelistirme varsa bitis ani, yoksa null.</summary>
    public DateTime? UpgradeCompletesAt { get; set; }
    public DateTime LastCollectedAt { get; set; }
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
}
