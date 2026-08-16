namespace MinerInMine.Api.Models;

/// <summary>
/// RefreshTokens tablosunun C# karşılığı.
/// sp_GetRefreshToken, token bilgisine ek olarak sahibi olan kullanıcının
/// Username/Email/IsActive bilgilerini de JOIN ile getirir; o yüzden bu üç alan
/// da burada yer alıyor (tek sorguda hem token hem kullanıcı doğrulaması).
/// </summary>
public class RefreshToken
{
    public int Id { get; set; }
    public int UserId { get; set; }
    public string Token { get; set; } = string.Empty;
    public DateTime ExpiresAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? RevokedAt { get; set; }
    public string? ReplacedByToken { get; set; }

    // sp_GetRefreshToken içindeki JOIN'den gelen kullanıcı bilgileri
    public string Username { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public bool IsActive { get; set; }

    /// <summary>Token'ın süresi dolmuş mu? (Saatler UTC olarak karşılaştırılır)</summary>
    public bool IsExpired => DateTime.UtcNow >= ExpiresAt;

    /// <summary>Token iptal edilmiş mi? (logout veya rotation sonrası dolar)</summary>
    public bool IsRevoked => RevokedAt != null;

    /// <summary>Token hâlâ kullanılabilir mi?</summary>
    public bool IsActiveToken => !IsRevoked && !IsExpired;
}
