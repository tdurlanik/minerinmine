using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MinerInMine.Api.Dtos;
using MinerInMine.Api.Extensions;
using MinerInMine.Api.Services;

namespace MinerInMine.Api.Controllers;

/// <summary>
/// Oyun mekanigi uclari. Tamami [Authorize] — oyun oynamak icin giris sart.
///
/// Dikkat edilecek nokta: hicbir uc "kullanici Id" parametresi ALMAZ.
/// Id her zaman TOKEN'DAN okunur. Aksi halde oyuncu baskasinin Id'sini gonderip
/// onun hesabinda islem yapabilirdi (IDOR — Insecure Direct Object Reference).
/// </summary>
[ApiController]
[Route("api/[controller]")]   // -> /api/game
[Authorize]
[Produces("application/json")]
public class GameController : ControllerBase
{
    private readonly IGameService _gameService;

    public GameController(IGameService gameService) => _gameService = gameService;

    /// <summary>Oyun ekraninin tum durumunu doner: kaynaklar, tesisler, kazma turleri.</summary>
    [HttpGet("state")]
    [ProducesResponseType(typeof(PlayerStateDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> GetState()
    {
        var userId = User.GetUserId();
        if (userId is null)
        {
            return Unauthorized(new { message = "Geçersiz token." });
        }

        var state = await _gameService.GetStateAsync(userId.Value);
        return Ok(state);
    }

    /// <summary>
    /// Kazma yapar.
    /// </summary>
    /// <remarks>
    /// Istek gövdesinde kazanc miktari YOKTUR ve olamaz; yalnizca hangi tesiste
    /// hangi kazma turunun kullanildigi bildirilir. Kazanci sunucu hesaplar.
    ///
    /// Bekleme suresi dolmamissa 400 doner — bu bir hata degil, oyunun normal akisidir.
    /// </remarks>
    [HttpPost("mine")]
    [ProducesResponseType(typeof(MineResultDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> Mine([FromBody] MineRequest request)
    {
        var userId = User.GetUserId();
        if (userId is null)
        {
            return Unauthorized(new { message = "Geçersiz token." });
        }

        var result = await _gameService.MineAsync(userId.Value, request);

        if (!result.Success)
        {
            return BadRequest(new { message = result.ErrorMessage });
        }

        return Ok(result.Data);
    }

    /// <summary>Tesis gelistirmesi baslatir.</summary>
    /// <remarks>
    /// Maliyet ve sure istekte GONDERILMEZ; sunucu denge tablosundan okur.
    /// Gelistirmeler tesis bazinda paraleldir: uc tesiste ayni anda gelistirme yapilabilir,
    /// ama ayni tesiste ikinci bir gelistirme baslatilamaz.
    /// </remarks>
    [HttpPost("facility/{facilityTypeId:int}/upgrade")]
    [ProducesResponseType(typeof(UpgradeStartedDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> StartUpgrade(int facilityTypeId)
    {
        var userId = User.GetUserId();
        if (userId is null)
        {
            return Unauthorized(new { message = "Geçersiz token." });
        }

        var result = await _gameService.StartUpgradeAsync(userId.Value, facilityTypeId);

        return result.Success
            ? Ok(result.Data)
            : BadRequest(new { message = result.ErrorMessage });
    }

    /// <summary>Devam eden gelistirmeyi Kristal odeyerek aninda bitirir.</summary>
    /// <remarks>
    /// Bedel kalan sureye gore hesaplanir ve dakika YUKARI yuvarlanir; istemci
    /// fiyat gonderemez. Sure zaten dolmussa gelistirme ucretsiz tamamlanir ve
    /// bu uc "devam eden gelistirme yok" doner.
    /// </remarks>
    [HttpPost("facility/{facilityTypeId:int}/finish-now")]
    [ProducesResponseType(typeof(UpgradeFinishedDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> FinishUpgradeNow(int facilityTypeId)
    {
        var userId = User.GetUserId();
        if (userId is null)
        {
            return Unauthorized(new { message = "Geçersiz token." });
        }

        var result = await _gameService.FinishUpgradeNowAsync(userId.Value, facilityTypeId);

        return result.Success
            ? Ok(result.Data)
            : BadRequest(new { message = result.ErrorMessage });
    }
}
