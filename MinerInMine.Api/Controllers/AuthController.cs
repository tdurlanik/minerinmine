using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MinerInMine.Api.Dtos;
using MinerInMine.Api.Services;

namespace MinerInMine.Api.Controllers;

/// <summary>
/// Kimlik doğrulama uçları. Tamamı [AllowAnonymous] çünkü kullanıcı bu noktada
/// henüz token'a sahip değil — token'ı almak için buraya geliyor.
///
/// [ApiController] attribute'unun bize kazandırdıkları:
///  - DTO'daki [Required]/[EmailAddress] kuralları OTOMATİK kontrol edilir;
///    kural ihlali varsa metot hiç çalışmadan 400 Bad Request döner.
///  - [FromBody] yazmaya gerek kalmaz, karmaşık tipler gövdeden okunur.
/// </summary>
[ApiController]
[Route("api/[controller]")]   // -> /api/auth
[AllowAnonymous]
[Produces("application/json")]
public class AuthController : ControllerBase
{
    private readonly IAuthService _authService;

    public AuthController(IAuthService authService) => _authService = authService;

    /// <summary>Yeni kullanıcı kaydı oluşturur ve otomatik giriş yaptırır.</summary>
    /// <remarks>
    /// Başarılı olduğunda Users + UserRoles + PlayerProfiles kayıtları tek bir
    /// transaction içinde birlikte oluşur (sp_RegisterUser).
    /// </remarks>
    [HttpPost("register")]
    [ProducesResponseType(typeof(AuthResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Register([FromBody] RegisterRequest request)
    {
        var result = await _authService.RegisterAsync(request);

        // 400 Bad Request: istemcinin gönderdiği veride sorun var (kullanıcı adı dolu vb.)
        if (!result.Success)
        {
            return BadRequest(new { message = result.ErrorMessage });
        }

        return Ok(result.Data);
    }

    /// <summary>Kullanıcı adı veya e-posta + şifre ile giriş yapar.</summary>
    [HttpPost("login")]
    [ProducesResponseType(typeof(AuthResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> Login([FromBody] LoginRequest request)
    {
        var result = await _authService.LoginAsync(request);

        // 401 Unauthorized: "kimliğini kanıtlayamadın".
        // (Karıştırılmasın: 403 Forbidden = "kim olduğunu biliyorum ama yetkin yok".)
        if (!result.Success)
        {
            return Unauthorized(new { message = result.ErrorMessage });
        }

        return Ok(result.Data);
    }

    /// <summary>Süresi dolan access token'ı, geçerli bir refresh token ile yeniler.</summary>
    /// <remarks>Başarılı olduğunda kullanılan refresh token iptal edilir ve yenisi verilir (token rotation).</remarks>
    [HttpPost("refresh-token")]
    [ProducesResponseType(typeof(AuthResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> RefreshToken([FromBody] RefreshTokenRequest request)
    {
        var result = await _authService.RefreshAsync(request.RefreshToken);

        if (!result.Success)
        {
            return Unauthorized(new { message = result.ErrorMessage });
        }

        return Ok(result.Data);
    }

    /// <summary>Çıkış yapar: refresh token'ı veritabanında iptal eder.</summary>
    [HttpPost("revoke-token")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> RevokeToken([FromBody] RefreshTokenRequest request)
    {
        var result = await _authService.RevokeAsync(request.RefreshToken);

        if (!result.Success)
        {
            return BadRequest(new { message = result.ErrorMessage });
        }

        return Ok(new { message = "Çıkış yapıldı. Refresh token iptal edildi." });
    }
}
