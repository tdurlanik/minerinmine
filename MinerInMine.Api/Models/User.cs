namespace MinerInMine.Api.Models;

/// <summary>
/// Veritabanındaki Users tablosunun C# karşılığı (POCO - Plain Old CLR Object).
///
/// ÖNEMLİ: Bu sınıf "iç dünya" (internal) modelidir. PasswordHash ve PasswordSalt
/// gibi hassas alanlar içerdiği için ASLA doğrudan API cevabı olarak dışarı verilmez.
/// Dışarıya verilecek veri için Dtos/ klasöründeki DTO sınıflarını kullanıyoruz.
///
/// Dapper, sp_GetUserByLogin'in döndürdüğü kolon isimlerini bu property isimleriyle
/// otomatik eşleştirir (Id -> Id, Username -> Username ...). İsimler birebir aynı
/// olduğu için ekstra bir mapping koduna gerek kalmaz.
/// </summary>
public class User
{
    public int Id { get; set; }
    public string Username { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;
    public string PasswordSalt { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? LastLoginAt { get; set; }
}
