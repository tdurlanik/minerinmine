namespace MinerInMine.Api.Dtos;

// ============================================================================
// GUN 5: Leaderboard, admin paneli ve reklam odulu
// ============================================================================

public class LeaderboardEntryDto
{
    public int Position { get; set; }
    public string Username { get; set; } = string.Empty;
    public long TotalWealth { get; set; }
    public int TotalLevels { get; set; }
    public int TotalMiners { get; set; }

    /// <summary>Bu satir istekte bulunan oyuncuya mi ait? (arayuz vurgular)</summary>
    public bool IsMe { get; set; }
}

public class MyRankDto
{
    public int Position { get; set; }
    public string Username { get; set; } = string.Empty;
    public long TotalWealth { get; set; }
    public int TotalPlayers { get; set; }
}

public class LeaderboardDto
{
    public List<LeaderboardEntryDto> Top { get; set; } = new();

    /// <summary>Oyuncu ilk N'de degilse bile kendi sirasini gorebilsin diye.</summary>
    public MyRankDto? Me { get; set; }
}

public class AdminPlayerDto
{
    public int UserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? LastLoginAt { get; set; }
    public long TotalWealth { get; set; }
    public long Kristal { get; set; }
    public int TotalLevels { get; set; }
    public int TotalMiners { get; set; }
    public string? Roles { get; set; }
}

public class AdminPlayerListDto
{
    public List<AdminPlayerDto> Players { get; set; } = new();
    public int TotalCount { get; set; }
    public int Page { get; set; }
    public int PageSize { get; set; }
}

public class AdminAdjustRequest
{
    public int TargetUserId { get; set; }
    public int ResourceTypeId { get; set; }

    /// <summary>Pozitif ekler, negatif eksiltir. Sifir kabul edilmez.</summary>
    public long Delta { get; set; }
}

public class AdminAdjustResultDto
{
    public long NewBalance { get; set; }
    public long Delta { get; set; }
    public DateTime ServerTime { get; set; }
}

public class SuspiciousEntryDto
{
    public int UserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public string ResourceCode { get; set; } = string.Empty;
    public long Gain { get; set; }
    public int TransactionCount { get; set; }
    public DateTime FirstAt { get; set; }
    public DateTime LastAt { get; set; }
}

/// <summary>
/// Reklam agindan gelen bildirim (Server-Side Verification).
///
/// Bu veriyi ISTEMCI GONDERMEZ; reklam agi dogrudan sunucumuza gonderir.
/// Signature, ag ile aramizdaki gizli anahtarla uretilmis imzadir.
/// </summary>
public class AdCallbackRequest
{
    public int UserId { get; set; }
    public string TransactionId { get; set; } = string.Empty;
    public string Signature { get; set; } = string.Empty;
}

public class AdRewardResultDto
{
    /// <summary>Bu bildirim daha once islendiyse true; odul tekrar verilmez.</summary>
    public bool AlreadyProcessed { get; set; }
    public long Amount { get; set; }
    public long NewBalance { get; set; }
    public DateTime ServerTime { get; set; }
}

// ============================================================================
// OYUNCU DETAYI VE YONETIM EYLEMLERI (sp_AdminGetPlayerDetail + eylem SP'leri)
// ============================================================================

/// <summary>Detay ekranindaki kimlik ve ozet blogu.</summary>
public class AdminPlayerInfoDto
{
    public int UserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? LastLoginAt { get; set; }
    public string? Roles { get; set; }
    public long TotalWealth { get; set; }

    /// <summary>Iptal edilmemis ve suresi dolmamis refresh token sayisi.</summary>
    public int ActiveSessions { get; set; }
    public int TransactionCount { get; set; }
}

public class AdminResourceDto
{
    public int ResourceTypeId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public long Amount { get; set; }
    public bool IsCurrency { get; set; }
    public int SellValue { get; set; }
}

public class AdminFacilityDto
{
    public int FacilityTypeId { get; set; }
    public string FacilityName { get; set; } = string.Empty;
    public int Level { get; set; }
    public int MaxLevel { get; set; }
    public string ResourceName { get; set; } = string.Empty;
    public DateTime? UpgradeCompletesAt { get; set; }
    public int MinerCount { get; set; }
}

public class AdminMinerDto
{
    public int MinerTypeId { get; set; }
    public string MinerName { get; set; } = string.Empty;
    public string FacilityName { get; set; } = string.Empty;
    public int Count { get; set; }
}

/// <summary>Islem gunlugu satiri — "kaynaklarin nereye gitti" sorusunun cevabi.</summary>
public class AdminTransactionDto
{
    public long Id { get; set; }
    public string ResourceName { get; set; } = string.Empty;
    public long Amount { get; set; }
    public long BalanceAfter { get; set; }
    public string Reason { get; set; } = string.Empty;
    public int? ReferenceId { get; set; }
    public DateTime CreatedAt { get; set; }
}

/// <summary>Oyuncu detay ekraninin tamami — SP'nin bes sonuc kumesi.</summary>
public class AdminPlayerDetailDto
{
    public AdminPlayerInfoDto? Player { get; set; }
    public List<AdminResourceDto> Resources { get; set; } = new();
    public List<AdminFacilityDto> Facilities { get; set; } = new();
    public List<AdminMinerDto> Miners { get; set; } = new();
    public List<AdminTransactionDto> Transactions { get; set; } = new();
}

public class AdminSetActiveRequest
{
    public bool IsActive { get; set; }
}

public class AdminSetActiveResultDto
{
    public bool IsActive { get; set; }

    /// <summary>Dondurma sirasinda dusurulen oturum sayisi.</summary>
    public int RevokedSessions { get; set; }
    public DateTime ServerTime { get; set; }
}

public class AdminSetRoleRequest
{
    public string RoleName { get; set; } = string.Empty;

    /// <summary>true ise rolu ver, false ise al.</summary>
    public bool Grant { get; set; }
}

public class AdminSetRoleResultDto
{
    public string RoleName { get; set; } = string.Empty;
    public bool IsGranted { get; set; }
    public DateTime ServerTime { get; set; }
}

public class AdminRevokeSessionsResultDto
{
    public int RevokedSessions { get; set; }
    public DateTime ServerTime { get; set; }
}

// ============================================================================
// EKONOMI SAGLIGI (sp_AdminGetEconomy)
//
// Denge simulasyonu oyunun nasil oynanabilecegini TAHMIN eder; bu rapor
// oyuncularin gercekte ne yaptigini OLCER.
// ============================================================================

public class EconomySummaryDto
{
    public int TotalPlayers { get; set; }
    public int ActiveToday { get; set; }
    public int ActiveInPeriod { get; set; }
    public int NewPlayers { get; set; }

    /// <summary>Oyuncularin elinde duran toplam Kristal. Surekli buyuyorsa enflasyon.</summary>
    public long CirculatingKristal { get; set; }
    public long TotalWealth { get; set; }

    /// <summary>Donemde ekonomiye GIREN Kristal (satis, reklam odulu).</summary>
    public long PeriodFaucet { get; set; }

    /// <summary>Donemde ekonomiden CIKAN Kristal (gelistirme, madenci, atlama).</summary>
    public long PeriodSink { get; set; }
    public int Days { get; set; }
}

public class EconomyDailyDto
{
    public DateTime Gun { get; set; }
    public long Faucet { get; set; }
    public long Sink { get; set; }
    public long Net { get; set; }
    public int ActivePlayers { get; set; }
}

public class EconomyReasonDto
{
    public string Reason { get; set; } = string.Empty;

    /// <summary>+1 kaynak (faucet), -1 gider (sink).</summary>
    public int Direction { get; set; }
    public long Total { get; set; }
    public int Times { get; set; }

    /// <summary>Kac farkli oyuncu. 1 ise bu genel egilim degil, tek kisinin davranisidir.</summary>
    public int PlayerCount { get; set; }
}

public class EconomyFacilityDto
{
    public int FacilityTypeId { get; set; }
    public string FacilityName { get; set; } = string.Empty;
    public int OwnerCount { get; set; }
    public double AvgLevel { get; set; }
    public int MaxLevel { get; set; }
    public int CapLevel { get; set; }
}

public class EconomyClickDto
{
    public int ClickTypeId { get; set; }
    public string ClickName { get; set; } = string.Empty;
    public long UnlockCost { get; set; }
    public int UnlockedBy { get; set; }
    public int TotalPlayers { get; set; }
}

public class EconomyReportDto
{
    public EconomySummaryDto Summary { get; set; } = new();
    public List<EconomyDailyDto> Daily { get; set; } = new();
    public List<EconomyReasonDto> Reasons { get; set; } = new();
    public List<EconomyFacilityDto> Facilities { get; set; } = new();
    public List<EconomyClickDto> Clicks { get; set; } = new();
}

/// <summary>
/// Yonetici islem gunlugu satiri.
///
/// Iki kaynaktan birlesir: AdminActions (dondurma/rol/oturum) ve
/// Transactions'taki ADMIN_ADJUST kayitlari (kaynak duzeltmeleri).
/// </summary>
public class AdminActionLogDto
{
    public DateTime CreatedAt { get; set; }
    public string AdminUsername { get; set; } = string.Empty;
    public int TargetUserId { get; set; }
    public string TargetUsername { get; set; } = string.Empty;
    public string Action { get; set; } = string.Empty;
    public string? Detail { get; set; }
}
