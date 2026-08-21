using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using MinerInMine.Api.Data;
using MinerInMine.Api.Dtos;
using MinerInMine.Api.Extensions;

namespace MinerInMine.Api.Hubs;

/// <summary>
/// MADEN SOHBETI — SignalR hub'i.
///
/// HTTP ILE FARKI NEDIR?
/// Sıradan bir HTTP isteğinde konuşmayı hep istemci başlatır: sorar, sunucu
/// cevaplar, bağlantı kapanır. Sunucunun kendiliğinden "yeni bir mesaj var"
/// diyebilmesi mümkün değildir; istemcinin sürekli sorması (polling) gerekir.
///
/// WebSocket bağlantıyı AÇIK TUTAR ve iki taraf da istediği anda yazabilir.
/// SignalR bu bağlantıyı yönetir: kopunca yeniden bağlanır, WebSocket
/// desteklenmiyorsa daha eski yöntemlere düşer.
///
/// HUB NEDIR? Sunucudaki metotları istemcinin, istemcideki metotları da
/// sunucunun çağırabildiği bir buluşma noktası. Aşağıdaki MesajGonder'i
/// tarayıcı çağırır; Clients.All.SendAsync ile de sunucu tarayıcıları çağırır.
///
/// GÜVENLİK: [Authorize] burada da geçerli. Kimliği doğrulanmamış bir bağlantı
/// hub'a hiç giremez. Kullanıcı kimliği yine TOKEN'DAN okunur — istemcinin
/// gönderdiği hiçbir alandan değil.
/// </summary>
[Authorize]
public class ChatHub : Hub
{
    private readonly IChatRepository _repository;
    private readonly ILogger<ChatHub> _logger;

    /// <summary>İstemci tarafında dinlenen olayın adı. Tek yerde tanımlı olsun.</summary>
    public const string YeniMesajOlayi = "YeniMesaj";

    public ChatHub(IChatRepository repository, ILogger<ChatHub> logger)
    {
        _repository = repository;
        _logger = logger;
    }

    /// <summary>
    /// İstemciden çağrılır: mesaj gönder.
    /// </summary>
    /// <remarks>
    /// Parametre yalnızca METİNDİR. Kullanıcı adı ve kimlik alınmaz; onlar
    /// token'dan okunur. Aksi halde herkes başkasının adına yazabilirdi —
    /// oyunun her yerinde uyguladığımız "sunucu otoritesi" kuralının aynısı.
    ///
    /// Hata durumunda istisna fırlatmıyoruz; yalnızca ÇAĞIRAN istemciye
    /// bir hata olayı gönderiyoruz. Böylece spam sınırına takılan oyuncunun
    /// bağlantısı kopmaz, sadece uyarı alır.
    /// </remarks>
    public async Task MesajGonder(string body)
    {
        var userId = Context.User?.GetUserId();

        if (userId is null)
        {
            await Clients.Caller.SendAsync("Hata", "Geçersiz oturum.");
            return;
        }

        // Sunucu tarafı ilk savunma: aşırı uzun metni veritabanına hiç götürme.
        if (string.IsNullOrWhiteSpace(body) || body.Length > 300)
        {
            await Clients.Caller.SendAsync("Hata", "Mesaj boş olamaz ve 300 karakteri aşamaz.");
            return;
        }

        var sonuc = await _repository.SendAsync(userId.Value, body);

        if (sonuc.ReturnCode != 0 || sonuc.Data is null)
        {
            // -1 boş mesaj, -2 hesap dondurulmuş, -3 spam sınırı.
            await Clients.Caller.SendAsync("Hata", sonuc.ErrorMessage ?? "Mesaj gönderilemedi.");
            return;
        }

        // Clients.All: bağlı HERKESE gönder — gönderen dahil.
        // Göndereni dışarıda bırakmak (Clients.Others) mümkün ama o zaman
        // istemci kendi mesajını kendisi ekranına eklemek zorunda kalır ve
        // iki farklı kod yolu doğar. Tek yol daha basit ve sıralama garantili.
        await Clients.All.SendAsync(YeniMesajOlayi, sonuc.Data);
    }

    /// <summary>Bağlantı kurulduğunda çalışır — günlüğe kim bağlandığını yazıyoruz.</summary>
    public override async Task OnConnectedAsync()
    {
        _logger.LogInformation(
            "Sohbete baglandi: {Kullanici} ({ConnectionId})",
            Context.User?.Identity?.Name ?? "?", Context.ConnectionId);

        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        _logger.LogInformation(
            "Sohbetten ayrildi: {Kullanici} ({ConnectionId})",
            Context.User?.Identity?.Name ?? "?", Context.ConnectionId);

        await base.OnDisconnectedAsync(exception);
    }
}
