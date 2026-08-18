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

    /// <summary>Madencilerin birikmis uretimini toplar (offline kazanc dahil).</summary>
    /// <remarks>
    /// Miktar istekte gonderilmez; sunucu "simdi - son toplama" suresinden hesaplar.
    /// Es zamanli iki istek gelse bile uretim yalnizca bir kez eklenir.
    /// </remarks>
    [HttpPost("collect")]
    [ProducesResponseType(typeof(List<CollectedResourceDto>), StatusCodes.Status200OK)]
    public async Task<IActionResult> Collect()
    {
        var userId = User.GetUserId();
        if (userId is null) return Unauthorized(new { message = "Geçersiz token." });

        return Ok(await _gameService.CollectAsync(userId.Value));
    }

    /// <summary>Bir tesise madenci alir. Kademe, otomatiklestirdigi kazma turuyle eslesir.</summary>
    [HttpPost("facility/{facilityTypeId:int}/miner/{minerTypeId:int}")]
    [ProducesResponseType(typeof(HireMinerResultDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> HireMiner(int facilityTypeId, int minerTypeId)
    {
        var userId = User.GetUserId();
        if (userId is null) return Unauthorized(new { message = "Geçersiz token." });

        var r = await _gameService.HireMinerAsync(userId.Value, facilityTypeId, minerTypeId);
        return r.Success ? Ok(r.Data) : BadRequest(new { message = r.ErrorMessage });
    }

    /// <summary>Maden satar, karsiliginda Kristal kazandirir.</summary>
    /// <remarks>Miktar istemciden gelir ama sunucu bakiyeyi dogrular; Kristal satilamaz.</remarks>
    [HttpPost("sell")]
    [ProducesResponseType(typeof(SellResultDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Sell([FromBody] SellRequest request)
    {
        var userId = User.GetUserId();
        if (userId is null) return Unauthorized(new { message = "Geçersiz token." });

        var r = await _gameService.SellAsync(userId.Value, request);
        return r.Success ? Ok(r.Data) : BadRequest(new { message = r.ErrorMessage });
    }

    /// <summary>Kalici guclendirme satin alir.</summary>
    [HttpPost("upgrade/{upgradeTypeId:int}")]
    [ProducesResponseType(typeof(PurchaseResultDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> BuyUpgrade(int upgradeTypeId)
    {
        var userId = User.GetUserId();
        if (userId is null) return Unauthorized(new { message = "Geçersiz token." });

        var r = await _gameService.BuyUpgradeAsync(userId.Value, upgradeTypeId);
        return r.Success ? Ok(r.Data) : BadRequest(new { message = r.ErrorMessage });
    }

    /// <summary>Yeni kazma turu acar.</summary>
    [HttpPost("click/{clickTypeId:int}/unlock")]
    [ProducesResponseType(typeof(UnlockResultDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> UnlockClick(int clickTypeId)
    {
        var userId = User.GetUserId();
        if (userId is null) return Unauthorized(new { message = "Geçersiz token." });

        var r = await _gameService.UnlockClickAsync(userId.Value, clickTypeId);
        return r.Success ? Ok(r.Data) : BadRequest(new { message = r.ErrorMessage });
    }
}
