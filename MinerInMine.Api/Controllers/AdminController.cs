using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MinerInMine.Api.Data;
using MinerInMine.Api.Dtos;
using MinerInMine.Api.Extensions;

namespace MinerInMine.Api.Controllers;

/// <summary>
/// Yonetim uclari.
///
/// Sinif seviyesindeki [Authorize(Roles = "Admin")] sayesinde bu controller'a
/// yalnizca Admin rolundeki kullanicilar erisebilir. Player rolundeki bir
/// oyuncu gecerli bir token ile gelse bile 403 alir.
///
/// Rol kontrolu SUNUCUDA yapilir. Arayuzde "Admin Paneli" baglantisini gizlemek
/// yalnizca gorsel bir tercihtir; korumayi saglayan sey bu attribute'tur.
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize(Roles = "Admin")]
[Produces("application/json")]
public class AdminController : ControllerBase
{
    private readonly IAdminRepository _repository;

    public AdminController(IAdminRepository repository) => _repository = repository;

    /// <summary>Oyuncu listesi (arama ve sayfalama ile).</summary>
    [HttpGet("players")]
    [ProducesResponseType(typeof(AdminPlayerListDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<IActionResult> GetPlayers(
        [FromQuery] string? search = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        return Ok(await _repository.GetPlayersAsync(search, page, pageSize));
    }

    /// <summary>Bir oyuncunun kaynagini artirir veya azaltir.</summary>
    /// <remarks>
    /// Her islem Transactions tablosuna ADMIN_ADJUST olarak, islemi yapan
    /// adminin kimligiyle birlikte yazilir (denetim izi). Bakiyeyi negatife
    /// dusurecek islemler reddedilir.
    /// </remarks>
    [HttpPost("adjust")]
    [ProducesResponseType(typeof(AdminAdjustResultDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Adjust([FromBody] AdminAdjustRequest request)
    {
        var adminId = User.GetUserId();
        if (adminId is null) return Unauthorized(new { message = "Geçersiz token." });

        var result = await _repository.AdjustResourceAsync(adminId.Value, request);

        return result.ReturnCode == 0 && result.Data is not null
            ? Ok(result.Data)
            : BadRequest(new { message = result.ErrorMessage ?? "İşlem yapılamadı." });
    }

    /// <summary>Kisa surede olagandisi kazanc elde eden oyuncular.</summary>
    /// <remarks>
    /// Hile kaniti degil, INCELEME LISTESIDIR: yuksek kazanc mesru da olabilir.
    /// Bu sorgu ancak Transactions gunlugunu en bastan tuttugumuz icin mumkun.
    /// </remarks>
    [HttpGet("suspicious")]
    [ProducesResponseType(typeof(List<SuspiciousEntryDto>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetSuspicious(
        [FromQuery] int minutes = 60,
        [FromQuery] long minGain = 100000)
    {
        return Ok(await _repository.GetSuspiciousAsync(minutes, minGain));
    }
}
