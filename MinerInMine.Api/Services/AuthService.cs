using MinerInMine.Api.Data;
using MinerInMine.Api.Dtos;
using MinerInMine.Api.Models;

namespace MinerInMine.Api.Services;

public interface IAuthService
{
    Task<ServiceResult<AuthResponse>> RegisterAsync(RegisterRequest request);
    Task<ServiceResult<AuthResponse>> LoginAsync(LoginRequest request);
    Task<ServiceResult<AuthResponse>> RefreshAsync(string refreshToken);
    Task<ServiceResult<bool>> RevokeAsync(string refreshToken);
}

/// <summary>
/// İŞ MANTIĞI (business logic) KATMANI.
///
/// Katman ayrımının mantığı:
///   Controller  -> HTTP ile ilgilenir (status kod, route, model doğrulama)
///   AuthService -> KURALLARLA ilgilenir (şifre doğru mu, hesap aktif mi, token üret)
///   Repository  -> VERİTABANI ile ilgilenir (hangi SP çağrılacak)
///
/// Bu ayrım sayesinde iş kurallarını değiştirmek için controller'a,
/// veritabanını değiştirmek için iş mantığına dokunmak gerekmez.
/// </summary>
public class AuthService : IAuthService
{
    private readonly IUserRepository _repository;
    private readonly IPasswordHasher _passwordHasher;
    private readonly ITokenService _tokenService;
    private readonly ILogger<AuthService> _logger;

    public AuthService(
        IUserRepository repository,
        IPasswordHasher passwordHasher,
        ITokenService tokenService,
        ILogger<AuthService> logger)
    {
        _repository = repository;
        _passwordHasher = passwordHasher;
        _tokenService = tokenService;
        _logger = logger;
    }

    // ========================================================================
    // KAYIT OLMA
    // Akış: şifreyi hashle -> sp_RegisterUser -> RETURN koduna bak -> token üret
    // ========================================================================
    public async Task<ServiceResult<AuthResponse>> RegisterAsync(RegisterRequest request)
    {
        // 1) Şifreyi hash'le. Açık şifre bu satırdan sonra hiçbir yere yazılmaz.
        var (hash, salt) = _passwordHasher.Create(request.Password);

        // 2) SP çağır. SP kendi içinde transaction ile kullanıcıyı, rolünü ve
        //    oyun başlangıç durumunu (kaynaklar, ilk tesis, ilk kazma türü) birlikte yazar.
        var dbResult = await _repository.RegisterAsync(
            request.Username.Trim(),
            request.Email.Trim().ToLowerInvariant(),   // e-postayı normalize ediyoruz
            hash,
            salt);

        // 3) SP'nin RETURN kodunu yorumla.
        //    Kontrolü C# tarafında değil SP içinde yapmamızın sebebi: iki kullanıcı aynı anda
        //    kayıt olmaya çalışırsa "önce kontrol et sonra ekle" mantığı C#'ta yarış durumuna
        //    (race condition) düşer. SP + UNIQUE constraint bunu veritabanı seviyesinde garantiler.
        switch (dbResult.ReturnCode)
        {
            case 0:
                break; // başarılı, devam
            case -1:
            case -2:
                return ServiceResult<AuthResponse>.Fail(dbResult.ErrorMessage ?? "Kayıt başarısız.");
            default:
                _logger.LogError("sp_RegisterUser beklenmeyen hata verdi: {Error}", dbResult.ErrorMessage);
                return ServiceResult<AuthResponse>.Fail("Kayıt sırasında beklenmeyen bir hata oluştu.");
        }

        // 4) Kayıt başarılı → kullanıcıyı ve rollerini oku, token üret (otomatik giriş).
        var user = await _repository.GetByLoginAsync(request.Username.Trim());
        if (user is null)
        {
            return ServiceResult<AuthResponse>.Fail("Kullanıcı oluşturuldu ancak okunamadı.");
        }

        var response = await BuildAuthResponseAsync(user);
        return ServiceResult<AuthResponse>.Ok(response);
    }

    // ========================================================================
    // GİRİŞ YAPMA
    // ========================================================================
    public async Task<ServiceResult<AuthResponse>> LoginAsync(LoginRequest request)
    {
        // GÜVENLİK NOTU: Aşağıdaki iki farklı durumda da AYNI mesajı döndürüyoruz.
        // "Böyle bir kullanıcı yok" deseydik, saldırgan hangi kullanıcı adlarının
        // sistemde kayıtlı olduğunu tek tek deneyerek öğrenebilirdi (user enumeration).
        const string genericError = "Kullanıcı adı/e-posta veya şifre hatalı.";

        var user = await _repository.GetByLoginAsync(request.LoginInput.Trim());
        if (user is null)
        {
            return ServiceResult<AuthResponse>.Fail(genericError);
        }

        if (!_passwordHasher.Verify(request.Password, user.PasswordHash, user.PasswordSalt))
        {
            return ServiceResult<AuthResponse>.Fail(genericError);
        }

        // Hesap askıya alınmışsa bu farklı bir durumdur; kullanıcı kimliğini zaten
        // doğruladık, bu yüzden net bilgi vermek sakıncalı değil.
        if (!user.IsActive)
        {
            return ServiceResult<AuthResponse>.Fail("Hesabınız devre dışı bırakılmış. Yönetici ile iletişime geçin.");
        }

        var response = await BuildAuthResponseAsync(user);

        // Son giriş zamanını güncelle (istatistik / güvenlik takibi için).
        await _repository.UpdateLastLoginAsync(user.Id);

        return ServiceResult<AuthResponse>.Ok(response);
    }

    // ========================================================================
    // TOKEN YENİLEME (Refresh)
    // Access token 15 dakikada ölür. Kullanıcıyı tekrar şifre girmeye zorlamamak
    // için elindeki refresh token ile yeni bir access token veririz.
    // ========================================================================
    public async Task<ServiceResult<AuthResponse>> RefreshAsync(string refreshToken)
    {
        var stored = await _repository.GetRefreshTokenAsync(refreshToken);

        if (stored is null)
        {
            return ServiceResult<AuthResponse>.Fail("Geçersiz refresh token.");
        }

        if (stored.IsRevoked)
        {
            // Bu ciddi bir sinyaldir: iptal edilmiş bir token kullanılmaya çalışılıyor.
            // Gerçek projelerde burada kullanıcının TÜM token'ları iptal edilir.
            _logger.LogWarning("İptal edilmiş refresh token kullanılmaya çalışıldı. UserId: {UserId}", stored.UserId);
            return ServiceResult<AuthResponse>.Fail("Bu refresh token iptal edilmiş.");
        }

        if (stored.IsExpired)
        {
            return ServiceResult<AuthResponse>.Fail("Refresh token süresi dolmuş. Lütfen tekrar giriş yapın.");
        }

        if (!stored.IsActive)
        {
            return ServiceResult<AuthResponse>.Fail("Hesabınız devre dışı bırakılmış.");
        }

        var user = await _repository.GetByLoginAsync(stored.Username);
        if (user is null)
        {
            return ServiceResult<AuthResponse>.Fail("Kullanıcı bulunamadı.");
        }

        // TOKEN ROTATION: Yeni token verirken eskisini iptal ediyoruz.
        // Böylece her refresh token yalnızca BİR KEZ kullanılabilir. Eğer bir token
        // ikinci kez kullanılmaya çalışılırsa, çalınmış olduğunu anlarız.
        var response = await BuildAuthResponseAsync(user);
        await _repository.RevokeRefreshTokenAsync(refreshToken, response.RefreshToken);

        return ServiceResult<AuthResponse>.Ok(response);
    }

    // ========================================================================
    // ÇIKIŞ (Logout) — refresh token'ı iptal et
    //
    // NOT: Access token stateless olduğu için sunucu tarafında "iptal" edilemez;
    // süresi dolana kadar (en fazla 15 dk) geçerli kalır. Bu yüzden access token
    // ömrünü kısa tutuyoruz. Frontend de token'ı localStorage'dan siler.
    // ========================================================================
    public async Task<ServiceResult<bool>> RevokeAsync(string refreshToken)
    {
        var stored = await _repository.GetRefreshTokenAsync(refreshToken);
        if (stored is null)
        {
            return ServiceResult<bool>.Fail("Geçersiz refresh token.");
        }

        await _repository.RevokeRefreshTokenAsync(refreshToken);
        return ServiceResult<bool>.Ok(true);
    }

    // ========================================================================
    // ORTAK YARDIMCI: Kullanıcıdan AuthResponse üretir.
    // Register, Login ve Refresh akışlarının üçü de aynı cevabı döndürdüğü için
    // bu mantığı tek bir yerde topluyoruz (DRY - Don't Repeat Yourself).
    // ========================================================================
    private async Task<AuthResponse> BuildAuthResponseAsync(User user)
    {
        var roles = await _repository.GetRolesAsync(user.Id);

        var (accessToken, accessExpires) = _tokenService.CreateAccessToken(user, roles);
        var (refreshToken, refreshExpires) = _tokenService.CreateRefreshToken();

        // Yeni refresh token'ı veritabanına yaz — doğrulaması buradan yapılacak.
        await _repository.SaveRefreshTokenAsync(user.Id, refreshToken, refreshExpires);

        return new AuthResponse
        {
            UserId = user.Id,
            Username = user.Username,
            Email = user.Email,
            Roles = roles.Select(r => r.Name).ToList(),
            AccessToken = accessToken,
            RefreshToken = refreshToken,
            AccessTokenExpiresAt = accessExpires
        };
    }
}
