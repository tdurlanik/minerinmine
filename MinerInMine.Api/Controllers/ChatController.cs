using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MinerInMine.Api.Data;
using MinerInMine.Api.Dtos;

namespace MinerInMine.Api.Controllers;

/// <summary>
/// Sohbet gecmisi.
///
/// NEDEN GECMIS HUB'DAN DEGIL DE HTTP'DEN GELIYOR?
/// SignalR bagi CANLI AKIS icindir: "bundan sonra ne oluyor". Gecmis ise
/// siradan bir sorgu — bir kez istenir, cevap gelir, biter. HTTP bunun icin
/// dogru arac ve mevcut altyapiyi (interceptor, token yenileme, hata
/// yonetimi) oldugu gibi kullaniyoruz.
///
/// Boylece sorumluluklar ayriliyor: gecmisi HTTP getirir, yeni mesajlari
/// WebSocket akitir.
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
[Produces("application/json")]
public class ChatController : ControllerBase
{
    private readonly IChatRepository _repository;

    public ChatController(IChatRepository repository) => _repository = repository;

    /// <summary>Son mesajlar, eskiden yeniye sirali.</summary>
    [HttpGet("history")]
    [ProducesResponseType(typeof(List<ChatMessageDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> GetHistory([FromQuery] int? top = null)
    {
        return Ok(await _repository.GetHistoryAsync(top));
    }
}
