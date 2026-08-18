using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MinerInMine.Api.Data;
using MinerInMine.Api.Dtos;
using MinerInMine.Api.Extensions;

namespace MinerInMine.Api.Controllers;

/// <summary>Oyuncu siralamasi.</summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
[Produces("application/json")]
public class LeaderboardController : ControllerBase
{
    private readonly IAdminRepository _repository;

    public LeaderboardController(IAdminRepository repository) => _repository = repository;

    /// <summary>Servet siralamasinda ilk N oyuncu ve kendi sirani doner.</summary>
    /// <remarks>
    /// Servet = Kristal + (her madenin miktari x birim degeri). Madenini
    /// satmamis oyuncu da hak ettigi yerde gorunur.
    /// </remarks>
    [HttpGet]
    [ProducesResponseType(typeof(LeaderboardDto), StatusCodes.Status200OK)]
    public async Task<IActionResult> Get([FromQuery] int top = 25)
    {
        var userId = User.GetUserId();
        if (userId is null) return Unauthorized(new { message = "Geçersiz token." });

        if (top < 1 || top > 100) top = 25;

        return Ok(await _repository.GetLeaderboardAsync(userId.Value, top));
    }
}
