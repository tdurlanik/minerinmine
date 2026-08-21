using System.ComponentModel.DataAnnotations;

namespace MinerInMine.Api.Dtos;

/// <summary>
/// Sohbet mesaji — hem gecmiste hem canli yayinda ayni sekil.
///
/// Istemciye iki ayri bicim gondermiyoruz: gecmisten gelen mesajla az once
/// yazilan mesaj arayuz icin ayni sey. Tek sekil, tek cizim kodu.
/// </summary>
public class ChatMessageDto
{
    public long Id { get; set; }
    public int UserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
}

/// <summary>
/// Istemcinin gonderdigi tek sey: METIN.
///
/// Kullanici adi ve kimlik BU SINIFTA YOKTUR ve olamaz. Kim oldugu token'dan
/// okunur; istemcinin soyledigine guvenilseydi herkes baskasinin adina
/// mesaj yazabilirdi. Oyunun geri kalanindaki kuralin aynisi: istemci
/// "ne yaptim" der, "kim oldugumu" ve "sonucu" soylemez.
/// </summary>
public class SendChatRequest
{
    [Required(ErrorMessage = "Mesaj bos olamaz.")]
    [MaxLength(300, ErrorMessage = "Mesaj en fazla 300 karakter olabilir.")]
    public string Body { get; set; } = string.Empty;
}
