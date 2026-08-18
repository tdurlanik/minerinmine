using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MinerInMine.Api.Data;
using MinerInMine.Api.Dtos;
using MinerInMine.Api.Extensions;
using MinerInMine.Api.Services;

namespace MinerInMine.Api.Controllers;

/// <summary>
/// Reklam odulu uclari.
///
/// TASARIMIN OZU: Odulu veren uc, ISTEMCININ CAGIRDIGI uc DEGILDIR.
/// Reklam agi izleme bittiginde dogrudan sunucumuza bildirim gonderir ve bu
/// bildirim gizli anahtarla imzalanmistir. Istemci akisin icinde yer almadigi
/// icin odulu taklit edemez.
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class AdsController : ControllerBase
{
    private readonly IAdminRepository _repository;
    private readonly IAdSignatureService _signature;
    private readonly IWebHostEnvironment _environment;
    private readonly ILogger<AdsController> _logger;

    public AdsController(
        IAdminRepository repository,
        IAdSignatureService signature,
        IWebHostEnvironment environment,
        ILogger<AdsController> logger)
    {
        _repository = repository;
        _signature = signature;
        _environment = environment;
        _logger = logger;
    }

    /// <summary>Reklam agindan gelen odul bildirimi (Server-Side Verification).</summary>
    /// <remarks>
    /// [AllowAnonymous]: Bu ucu cagiran reklam agidir, oturum acmis bir kullanici degil.
    /// Guvenligi saglayan sey token degil, HMAC IMZASIDIR.
    ///
    /// Ayni TransactionId ile tekrar gelen bildirimler odulu TEKRAR VERMEZ
    /// (idempotency) ama hata da dondurmez — tekrar gonderim aglarin normal
    /// davranisidir ve hata donersek ag denemeye devam eder.
    /// </remarks>
    [HttpPost("callback")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(AdRewardResultDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> Callback([FromBody] AdCallbackRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.TransactionId))
        {
            return BadRequest(new { message = "TransactionId zorunludur." });
        }

        if (!_signature.Verify(request.UserId, request.TransactionId, request.Signature))
        {
            // Gecersiz imza = ya sahte istek ya yanlis anahtar. Ikisi de loglanmali.
            _logger.LogWarning(
                "Gecersiz reklam imzasi. UserId={UserId} TransactionId={TransactionId}",
                request.UserId, request.TransactionId);

            return Unauthorized(new { message = "Geçersiz imza." });
        }

        var result = await _repository.GrantAdRewardAsync(request.UserId, request.TransactionId);

        return result.ReturnCode == 0 && result.Data is not null
            ? Ok(result.Data)
            : BadRequest(new { message = result.ErrorMessage ?? "Ödül verilemedi." });
    }

    /// <summary>Reklam izlemeyi simule eder (YALNIZCA GELISTIRME ORTAMI).</summary>
    /// <remarks>
    /// Gercek bir reklam agi entegrasyonu bu projenin kapsami disinda oldugu icin,
    /// agin yapacagi imzali cagriyi burada taklit ediyoruz.
    ///
    /// Bu uc uretimde KAPALIDIR: acik olsaydi istemci kendine sinirsiz odul
    /// yazdirabilirdi ve SSV'nin butun anlami kaybolurdu.
    /// </remarks>
    [HttpPost("simulate-watch")]
    [Authorize]
    [ProducesResponseType(typeof(AdRewardResultDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> SimulateWatch()
    {
        if (!_environment.IsDevelopment())
        {
            // Uretimde bu ucun VAR OLMADIGINI soyluyoruz (403 yerine 404):
            // saldirgana sistemin yapisi hakkinda bilgi vermemek icin.
            return NotFound();
        }

        var userId = User.GetUserId();
        if (userId is null) return Unauthorized(new { message = "Geçersiz token." });

        // Reklam aginin uretecegi benzersiz islem kimligi
        var transactionId = $"sim-{Guid.NewGuid():N}";
        var signature = _signature.Compute(userId.Value, transactionId);

        // Agin gonderecegi imzali cagrinin aynisini yapiyoruz
        var result = await _repository.GrantAdRewardAsync(userId.Value, transactionId);

        return result.ReturnCode == 0 && result.Data is not null
            ? Ok(result.Data)
            : BadRequest(new { message = result.ErrorMessage ?? "Ödül verilemedi." });
    }
}
