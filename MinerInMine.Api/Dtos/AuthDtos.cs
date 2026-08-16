using System.ComponentModel.DataAnnotations;

namespace MinerInMine.Api.Dtos;

// ============================================================================
// DTO = Data Transfer Object (Veri Taşıma Nesnesi)
//
// NEDEN DTO KULLANIYORUZ?
// 1. GÜVENLİK: Models/User.cs içinde PasswordHash ve PasswordSalt var. Eğer
//    controller'dan doğrudan User döndürseydik, şifre hash'i JSON olarak
//    tarayıcıya giderdi. DTO ile sadece göstermek istediğimiz alanları veririz.
// 2. SÖZLEŞME (contract): Veritabanı şeması değişse bile API'nin dış dünyaya
//    verdiği JSON yapısı sabit kalabilir. Frontend kırılmaz.
// 3. DOĞRULAMA: [Required], [EmailAddress] gibi attribute'lar sayesinde ASP.NET
//    isteği daha controller'a girmeden doğrular (ModelState).
// ============================================================================

/// <summary>Kayıt olma isteğinin gövdesi (POST /api/auth/register)</summary>
public class RegisterRequest
{
    [Required(ErrorMessage = "Kullanıcı adı zorunludur.")]
    [StringLength(50, MinimumLength = 3, ErrorMessage = "Kullanıcı adı 3-50 karakter olmalıdır.")]
    public string Username { get; set; } = string.Empty;

    [Required(ErrorMessage = "E-posta zorunludur.")]
    [EmailAddress(ErrorMessage = "Geçerli bir e-posta adresi giriniz.")]
    [StringLength(100)]
    public string Email { get; set; } = string.Empty;

    [Required(ErrorMessage = "Şifre zorunludur.")]
    [StringLength(100, MinimumLength = 6, ErrorMessage = "Şifre en az 6 karakter olmalıdır.")]
    public string Password { get; set; } = string.Empty;
}

/// <summary>Giriş isteğinin gövdesi (POST /api/auth/login)</summary>
public class LoginRequest
{
    /// <summary>Kullanıcı adı VEYA e-posta olabilir; sp_GetUserByLogin ikisini de arar.</summary>
    [Required(ErrorMessage = "Kullanıcı adı veya e-posta zorunludur.")]
    public string LoginInput { get; set; } = string.Empty;

    [Required(ErrorMessage = "Şifre zorunludur.")]
    public string Password { get; set; } = string.Empty;
}

/// <summary>Refresh / revoke isteklerinin gövdesi</summary>
public class RefreshTokenRequest
{
    [Required]
    public string RefreshToken { get; set; } = string.Empty;
}

/// <summary>
/// Başarılı register/login/refresh sonrası dönen cevap.
/// Frontend bu cevabı alıp accessToken'ı her istekte Authorization header'ına koyar.
/// </summary>
public class AuthResponse
{
    public int UserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public List<string> Roles { get; set; } = new();

    /// <summary>Kısa ömürlü (15 dk) JWT. Her istekte gönderilir.</summary>
    public string AccessToken { get; set; } = string.Empty;

    /// <summary>Uzun ömürlü (7 gün) rastgele anahtar. Sadece yeni access token almak için kullanılır.</summary>
    public string RefreshToken { get; set; } = string.Empty;

    /// <summary>Access token'ın bitiş zamanı (UTC). Frontend süreyi buradan takip edebilir.</summary>
    public DateTime AccessTokenExpiresAt { get; set; }
}

/// <summary>GET /api/users/me cevabı — token içindeki claim'lerden üretilir.</summary>
public class UserInfoDto
{
    public int UserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public List<string> Roles { get; set; } = new();
}

/// <summary>
/// Servis katmanının controller'a "başarılı mı, değilse neden" bilgisini
/// exception fırlatmadan taşıması için kullanılan basit sonuç sarmalayıcısı.
/// Beklenen iş kuralı hataları (kullanıcı adı dolu, şifre yanlış) için exception
/// kullanmak pahalıdır ve akışı okumayı zorlaştırır.
/// </summary>
public class ServiceResult<T>
{
    public bool Success { get; private set; }
    public string? ErrorMessage { get; private set; }
    public T? Data { get; private set; }

    public static ServiceResult<T> Ok(T data) => new() { Success = true, Data = data };
    public static ServiceResult<T> Fail(string message) => new() { Success = false, ErrorMessage = message };
}
