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

    /// <summary>Tek oyuncunun tum durumu: kimlik, kaynaklar, tesisler, madenciler, son 50 islem.</summary>
    /// <remarks>
    /// Islem gecmisi ancak Transactions gunlugu en bastan tutuldugu icin var;
    /// "sikayet geldiginde kaynaklarin nereye gitti" sorusunun cevabi burasi.
    /// </remarks>
    [HttpGet("players/{id:int}")]
    [ProducesResponseType(typeof(AdminPlayerDetailDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetPlayerDetail(int id)
    {
        var detay = await _repository.GetPlayerDetailAsync(id);

        return detay.Player is null
            ? NotFound(new { message = "Oyuncu bulunamadı." })
            : Ok(detay);
    }

    /// <summary>Hesabi dondurur veya yeniden acar.</summary>
    /// <remarks>
    /// Kalici silme YOKTUR: IsActive = 0 yeterlidir, boylece gecmis kayitlar
    /// ve hile tespiti calismaya devam eder. Dondurulen hesabin acik oturumlari
    /// da dusurulur — aksi halde elindeki refresh token'la oynamaya devam ederdi.
    /// Admin kendi hesabini donduramaz (kendini kilitlemesin).
    /// </remarks>
    [HttpPost("players/{id:int}/active")]
    [ProducesResponseType(typeof(AdminSetActiveResultDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> SetActive(int id, [FromBody] AdminSetActiveRequest request)
    {
        var adminId = User.GetUserId();
        if (adminId is null) return Unauthorized(new { message = "Geçersiz token." });

        var result = await _repository.SetActiveAsync(adminId.Value, id, request.IsActive);

        return result.ReturnCode == 0 && result.Data is not null
            ? Ok(result.Data)
            : BadRequest(new { message = result.ErrorMessage ?? "İşlem yapılamadı." });
    }

    /// <summary>Oyuncuya rol verir veya alir.</summary>
    /// <remarks>
    /// Iki koruma veritabaninda: admin kendi rolunu degistiremez ve sistemdeki
    /// SON adminin rolu alinamaz — aksi halde sistem yonetimsiz kalirdi.
    /// </remarks>
    [HttpPost("players/{id:int}/role")]
    [ProducesResponseType(typeof(AdminSetRoleResultDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> SetRole(int id, [FromBody] AdminSetRoleRequest request)
    {
        var adminId = User.GetUserId();
        if (adminId is null) return Unauthorized(new { message = "Geçersiz token." });

        var result = await _repository.SetRoleAsync(adminId.Value, id, request.RoleName, request.Grant);

        return result.ReturnCode == 0 && result.Data is not null
            ? Ok(result.Data)
            : BadRequest(new { message = result.ErrorMessage ?? "Rol değiştirilemedi." });
    }

    /// <summary>Oyuncunun tum acik oturumlarini dusurur.</summary>
    /// <remarks>
    /// Sifresi calinmis olabilecek bir hesap icin dogru mudahale: hesap
    /// dondurulmadan "cikis yaptirilir". Token'lar silinmez, RevokedAt
    /// isaretlenir — iptal edilmis token tekrar kullanilirsa gorulebilsin.
    /// </remarks>
    [HttpPost("players/{id:int}/revoke-sessions")]
    [ProducesResponseType(typeof(AdminRevokeSessionsResultDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> RevokeSessions(int id)
    {
        var adminId = User.GetUserId();
        if (adminId is null) return Unauthorized(new { message = "Geçersiz token." });

        var result = await _repository.RevokeSessionsAsync(adminId.Value, id);

        return result.ReturnCode == 0 && result.Data is not null
            ? Ok(result.Data)
            : BadRequest(new { message = result.ErrorMessage ?? "Oturumlar düşürülemedi." });
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

    /// <summary>Ekonomi sagligi raporu: faucet/sink dengesi, mekanik kullanimi, ilerleme dagilimi.</summary>
    /// <remarks>
    /// FAUCET / SINK: ekonomiye giren para ile cikan para. Faucet surekli
    /// sink'i asiyorsa para birikir, fiyatlar anlamsizlasir ve ilerleme hissi
    /// kaybolur. Bu iki sayi yan yana gorulmeden denge konusulamaz.
    ///
    /// Rakamlarin tamami Transactions gunlugunden turetilir; bakiye tablolari
    /// yalnizca son durumu bilir, "dun ne kadar uretildi" sorusunu cevaplayamaz.
    /// </remarks>
    [HttpGet("economy")]
    [ProducesResponseType(typeof(EconomyReportDto), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetEconomy([FromQuery] int days = 7)
    {
        return Ok(await _repository.GetEconomyAsync(days));
    }

    /// <summary>Son yonetici mudahaleleri (denetim izi).</summary>
    /// <remarks>
    /// Denetim izi, OKUNAMIYORSA denetim izi degildir. "Bu hesabi kim
    /// dondurdu, bu kaynagi kim verdi" sorusunun cevabi bu uctan gelir.
    /// </remarks>
    [HttpGet("actions")]
    [ProducesResponseType(typeof(List<AdminActionLogDto>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetActionLog([FromQuery] int top = 50)
    {
        return Ok(await _repository.GetActionLogAsync(top));
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
