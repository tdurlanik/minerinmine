using System.IdentityModel.Tokens.Jwt;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MinerInMine.Api.Dtos;

namespace MinerInMine.Api.Controllers;

/// <summary>
/// KORUMALI UÇLAR — JWT'nin gerçekten işe yaradığını kanıtlayan controller.
///
/// Sınıf seviyesindeki [Authorize]: bu controller'daki TÜM metotlar geçerli bir
/// token ister. Token yoksa/geçersizse ASP.NET metodu hiç çalıştırmadan 401 döner.
/// </summary>
[ApiController]
[Route("api/[controller]")]   // -> /api/users
[Authorize]
[Produces("application/json")]
public class UsersController : ControllerBase
{
    /// <summary>
    /// Giriş yapmış kullanıcının kendi bilgilerini döner.
    ///
    /// DİKKAT: Burada veritabanına HİÇ GİTMİYORUZ. Tüm bilgi token'ın içindeki
    /// claim'lerden okunuyor. JWT'nin "stateless" olmasının pratik faydası budur:
    /// her istekte kullanıcıyı DB'den sorgulamak gerekmez.
    /// </summary>
    [HttpGet("me")]
    [ProducesResponseType(typeof(UserInfoDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public IActionResult GetCurrentUser()
    {
        // User.Claims: ASP.NET'in token'ı doğruladıktan sonra doldurduğu kimlik bilgisi.
        // "sub" claim'ini biz TokenService'te kullanıcı Id'si olarak yazmıştık.
        var userIdClaim = User.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;

        if (!int.TryParse(userIdClaim, out var userId))
        {
            return Unauthorized(new { message = "Token içinde geçerli bir kullanıcı kimliği bulunamadı." });
        }

        var info = new UserInfoDto
        {
            UserId = userId,
            Username = User.FindFirst("name")?.Value ?? string.Empty,
            Email = User.FindFirst("email")?.Value ?? string.Empty,
            Roles = User.FindAll("role").Select(c => c.Value).ToList()
        };

        return Ok(info);
    }

    /// <summary>
    /// Sadece Admin rolündeki kullanıcıların erişebildiği örnek uç.
    ///
    /// Kayıt olan herkes varsayılan olarak 'Player' rolü aldığı için normal bir
    /// kullanıcı burada 403 Forbidden alır. Bu BEKLENEN ve DOĞRU davranıştır:
    /// 401 = "kimsin bilmiyorum", 403 = "kim olduğunu biliyorum ama yetkin yok".
    ///
    /// Test etmek için: veritabanında UserRoles tablosuna elle Admin rolü ekleyip
    /// TEKRAR login olun (roller token üretilirken okunduğu için eski token değişmez).
    /// </summary>
    [HttpGet("admin-only")]
    [Authorize(Roles = "Admin")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public IActionResult AdminOnly()
    {
        return Ok(new
        {
            message = "Tebrikler! Bu uca sadece Admin rolündeki kullanıcılar erişebilir.",
            username = User.FindFirst("name")?.Value
        });
    }
}
