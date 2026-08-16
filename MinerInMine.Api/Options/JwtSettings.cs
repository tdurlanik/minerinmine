namespace MinerInMine.Api.Options;

/// <summary>
/// appsettings.json içindeki "Jwt" bölümünün C# karşılığı.
///
/// NEDEN AYRI SINIF? (Options Pattern)
/// Her yerde configuration["Jwt:Key"] yazmak yerine tipli bir nesne kullanırız.
/// Avantajı: yazım hatası derleme zamanında yakalanır, IntelliSense çalışır,
/// ve ayarlar tek bir yerde belgelenmiş olur.
/// </summary>
public class JwtSettings
{
    public const string SectionName = "Jwt";

    /// <summary>Token'ı imzalamak için kullanılan gizli anahtar. HS256 için en az 32 karakter olmalı.</summary>
    public string Key { get; set; } = string.Empty;

    /// <summary>Token'ı kim üretti? (issuer)</summary>
    public string Issuer { get; set; } = string.Empty;

    /// <summary>Token kimin için üretildi? (audience)</summary>
    public string Audience { get; set; } = string.Empty;

    /// <summary>Access token ömrü (dakika). Kısa tutulur: çalınırsa zararı sınırlı olsun.</summary>
    public int AccessTokenMinutes { get; set; } = 15;

    /// <summary>Refresh token ömrü (gün). Uzun tutulur: kullanıcı her 15 dakikada şifre girmesin.</summary>
    public int RefreshTokenDays { get; set; } = 7;
}
