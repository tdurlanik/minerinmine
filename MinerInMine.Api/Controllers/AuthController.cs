using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MinerInMine.Api.Dtos;
using MinerInMine.Api.Services;

namespace MinerInMine.Api.Controllers;

/// <summary>
/// Kimlik doğrulama uçları.
///
/// TOKEN SAKLAMA STRATEJİSİ — iki token, iki farklı yer:
///
///   Access token (15 dk)  -> cevap gövdesinde döner, istemci sessionStorage'da tutar
///   Refresh token (7 gün) -> HttpOnly cookie; JavaScript ASLA göremez
///
/// Neden böyle? XSS ile sayfaya sızan bir script sessionStorage'ı okuyabilir ama
/// HttpOnly cookie'yi OKUYAMAZ. Uzun ömürlü kimlik bilgisini cookie'ye taşıyarak
/// XSS'i "kalıcı hesap ele geçirme"den "en fazla 15 dakikalık geçici erişim"e
/// indiriyoruz. Saldırgan yenileme yapamaz; sekme kapanınca erişim biter.
///
/// Karşılığında CSRF gündeme gelir (cookie'ler otomatik gönderilir); bunu
/// SameSite=Strict ile kapatıyoruz. Oyun uçları ise cookie değil Authorization
/// başlığı kullandığı için zaten CSRF'e bağışık.
/// </summary>
[ApiController]
[Route("api/[controller]")]   // -> /api/auth
[AllowAnonymous]
[Produces("application/json")]
public class AuthController : ControllerBase
{
    /// <summary>Cookie adı. İstemci bunu okuyamaz; yalnızca tarayıcı taşır.</summary>
    private const string RefreshCookieName = "mim_refresh";

    /// <summary>
    /// Cookie'nin gönderileceği yol. Yalnızca /api/auth/* isteklerinde taşınır;
    /// oyun uçlarına hiç gitmez. Gereksiz yere ağa çıkan her kopya bir risktir.
    /// </summary>
    private const string RefreshCookiePath = "/api/auth";

    private readonly IAuthService _authService;
    private readonly IWebHostEnvironment _environment;

    public AuthController(IAuthService authService, IWebHostEnvironment environment)
    {
        _authService = authService;
        _environment = environment;
    }

    /// <summary>Yeni kullanıcı kaydı oluşturur ve otomatik giriş yaptırır.</summary>
    [HttpPost("register")]
    [ProducesResponseType(typeof(AuthResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Register([FromBody] RegisterRequest request)
    {
        var result = await _authService.RegisterAsync(request);

        if (!result.Success || result.Data is null)
        {
            return BadRequest(new { message = result.ErrorMessage });
        }

        SetRefreshCookie(result.Data);
        return Ok(result.Data);
    }

    /// <summary>Kullanıcı adı veya e-posta + şifre ile giriş yapar.</summary>
    [HttpPost("login")]
    [ProducesResponseType(typeof(AuthResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> Login([FromBody] LoginRequest request)
    {
        var result = await _authService.LoginAsync(request);

        if (!result.Success || result.Data is null)
        {
            return Unauthorized(new { message = result.ErrorMessage });
        }

        SetRefreshCookie(result.Data);
        return Ok(result.Data);
    }

    /// <summary>Süresi dolan access token'ı yeniler.</summary>
    /// <remarks>
    /// İSTEK GÖVDESİ YOKTUR: refresh token cookie'den okunur. İstemci onu zaten
    /// göremediği için gönderemez de — güvenliğin kaynağı tam olarak budur.
    ///
    /// Başarılı olduğunda kullanılan token iptal edilir ve cookie yenisiyle
    /// değiştirilir (token rotation).
    /// </remarks>
    [HttpPost("refresh-token")]
    [ProducesResponseType(typeof(AuthResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> RefreshToken()
    {
        var refreshToken = Request.Cookies[RefreshCookieName];

        if (string.IsNullOrWhiteSpace(refreshToken))
        {
            return Unauthorized(new { message = "Oturum bulunamadı." });
        }

        var result = await _authService.RefreshAsync(refreshToken);

        if (!result.Success || result.Data is null)
        {
            // Token geçersiz/iptal/süresi dolmuş: cookie'yi de temizleyelim ki
            // tarayıcı her açılışta boşuna denemesin.
            ClearRefreshCookie();
            return Unauthorized(new { message = result.ErrorMessage });
        }

        SetRefreshCookie(result.Data);
        return Ok(result.Data);
    }

    /// <summary>Çıkış yapar: refresh token'ı veritabanında iptal eder ve cookie'yi siler.</summary>
    [HttpPost("revoke-token")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> RevokeToken()
    {
        var refreshToken = Request.Cookies[RefreshCookieName];

        if (!string.IsNullOrWhiteSpace(refreshToken))
        {
            await _authService.RevokeAsync(refreshToken);
        }

        // Sunucudaki iptal başarısız olsa bile cookie mutlaka silinir:
        // kullanıcı "çıkış" dediyse çıkmış olmalıdır.
        ClearRefreshCookie();

        return Ok(new { message = "Çıkış yapıldı." });
    }

    // ========================================================================
    // COOKIE YARDIMCILARI
    // ========================================================================

    private void SetRefreshCookie(AuthResponse response)
    {
        Response.Cookies.Append(
            RefreshCookieName,
            response.RefreshToken,
            BuildCookieOptions(response.RefreshTokenExpiresAt));
    }

    private void ClearRefreshCookie()
    {
        // Cookie silmek = aynı ada, AYNI bayraklarla geçmiş tarihli yazmak.
        // Path veya SameSite farklı olursa tarayıcı bunu BAŞKA bir cookie sanar
        // ve eskisi silinmez — sessizce çalışmayan bir "çıkış" oluşur.
        Response.Cookies.Append(
            RefreshCookieName,
            string.Empty,
            BuildCookieOptions(DateTime.UtcNow.AddDays(-1)));
    }

    /// <summary>
    /// Cookie bayrakları ve anlamları:
    ///
    ///   HttpOnly = true   -> JavaScript document.cookie ile OKUYAMAZ (XSS koruması)
    ///   Secure            -> yalnızca HTTPS üzerinden gönderilir
    ///   SameSite = Strict -> başka sitelerden gelen isteklerde GÖNDERİLMEZ (CSRF koruması)
    ///   Path = /api/auth  -> yalnızca auth uçlarına taşınır, oyun uçlarına gitmez
    ///   Expires           -> refresh token'ın gerçek bitiş zamanıyla aynı
    /// </summary>
    private CookieOptions BuildCookieOptions(DateTime expiresUtc) => new()
    {
        HttpOnly = true,

        // Geliştirmede http://localhost kullandığımız için Secure kapalı;
        // açık olsaydı tarayıcı cookie'yi hiç saklamazdı. Üretimde HTTPS zorunlu.
        Secure = !_environment.IsDevelopment(),

        SameSite = SameSiteMode.Strict,
        Path = RefreshCookiePath,
        Expires = new DateTimeOffset(expiresUtc, TimeSpan.Zero),
        IsEssential = true
    };
}
