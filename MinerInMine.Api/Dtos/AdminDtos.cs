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
