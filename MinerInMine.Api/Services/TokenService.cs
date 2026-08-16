using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using MinerInMine.Api.Models;
using MinerInMine.Api.Options;

namespace MinerInMine.Api.Services;

public interface ITokenService
{
    (string Token, DateTime ExpiresAt) CreateAccessToken(User user, IEnumerable<Role> roles);
    (string Token, DateTime ExpiresAt) CreateRefreshToken();
}

/// <summary>
/// JWT (JSON Web Token) ÜRETİMİ
///
/// JWT NEDİR?
/// Nokta ile ayrılmış 3 parçadan oluşan bir metindir:  header.payload.signature
///   - header    : hangi algoritma kullanıldı (HS256)
///   - payload   : kullanıcı bilgileri = "claim"ler (id, kullanıcı adı, roller, bitiş zamanı)
///   - signature : header + payload'ın gizli anahtarla imzalanmış hali
///
/// ÖNEMLİ YANILGI: JWT'nin payload'ı ŞİFRELİ DEĞİLDİR, sadece Base64 ile kodlanmıştır.
/// jwt.io sitesine yapıştırıp herkes okuyabilir. Bu yüzden token'a şifre, kredi kartı gibi
/// gizli veri KOYULMAZ. Token'ın koruduğu şey gizlilik değil, BÜTÜNLÜKTÜR:
/// içerik değiştirilirse imza tutmaz ve sunucu token'ı reddeder.
///
/// NEDEN STATELESS?
/// Sunucu oturum bilgisini hafızada tutmaz. Gelen token'ın imzasını doğrular ve
/// içindeki claim'lere güvenir. Bu sayede API birden fazla sunucuya kolayca ölçeklenir.
/// </summary>
public class TokenService : ITokenService
{
    private readonly JwtSettings _settings;

    public TokenService(IOptions<JwtSettings> settings) => _settings = settings.Value;

    /// <summary>
    /// Kullanıcı ve rollerinden kısa ömürlü bir access token üretir.
    /// </summary>
    public (string Token, DateTime ExpiresAt) CreateAccessToken(User user, IEnumerable<Role> roles)
    {
        // 1) CLAIM'LER: Token'ın içine yazılacak "kullanıcı hakkındaki iddialar".
        //    Kısa isimler (sub, name, email, role) kullanıyoruz. Varsayılan .NET davranışı
        //    bunları uzun URI'lere çevirir (http://schemas.microsoft.com/...);
        //    Program.cs'te bu haritalamayı kapatıyoruz ki Angular tarafında token'ı
        //    decode ettiğimizde okunabilir, temiz bir payload görelim.
        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, user.Id.ToString()),      // "sub" = subject = kullanıcı kimliği
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()), // "jti" = token'ın benzersiz kimliği
            new("name", user.Username),
            new("email", user.Email)
        };

        // 2) Her rol AYRI bir claim olarak eklenir.
        //    [Authorize(Roles = "Admin")] attribute'u tam olarak bu claim'lere bakar.
        foreach (var role in roles)
        {
            claims.Add(new Claim("role", role.Name));
        }

        // 3) İMZALAMA ANAHTARI
        //    Simetrik anahtar: aynı gizli anahtar hem imzalar hem doğrular.
        //    Bu anahtar sızarsa saldırgan istediği kullanıcı adına token üretebilir!
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_settings.Key));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var expiresAt = DateTime.UtcNow.AddMinutes(_settings.AccessTokenMinutes);

        var token = new JwtSecurityToken(
            issuer: _settings.Issuer,
            audience: _settings.Audience,
            claims: claims,
            notBefore: DateTime.UtcNow,
            expires: expiresAt,
            signingCredentials: credentials);

        // WriteToken: nesneyi "xxxxx.yyyyy.zzzzz" metnine dönüştürür.
        return (new JwtSecurityTokenHandler().WriteToken(token), expiresAt);
    }

    /// <summary>
    /// Refresh token üretir.
    ///
    /// DİKKAT: Refresh token bir JWT DEĞİLDİR — içinde hiçbir bilgi taşımaz.
    /// Sadece tahmin edilemez, rastgele bir anahtardır. Anlamını veritabanındaki
    /// RefreshTokens satırından alır (kime ait, ne zaman biter, iptal edilmiş mi).
    ///
    /// Bu bilinçli bir tercihtir: access token stateless olduğu için iptal edilemez;
    /// refresh token ise veritabanında tutulduğu için istediğimiz an iptal edilebilir.
    /// Böylece "logout" gerçekten çalışır.
    ///
    /// RandomNumberGenerator kullanıyoruz, Random SINIFINI DEĞİL. Random tahmin
    /// edilebilir bir algoritma kullanır; kriptografik amaçla asla kullanılmaz.
    /// </summary>
    public (string Token, DateTime ExpiresAt) CreateRefreshToken()
    {
        var randomBytes = RandomNumberGenerator.GetBytes(64);      // 64 byte = 512 bit entropi
        var token = Convert.ToBase64String(randomBytes);           // 88 karakter -> NVARCHAR(200)'e sığar

        return (token, DateTime.UtcNow.AddDays(_settings.RefreshTokenDays));
    }
}
