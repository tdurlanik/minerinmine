using System.Security.Cryptography;
using System.Text;

namespace MinerInMine.Api.Services;

public interface IAdSignatureService
{
    string Compute(int userId, string transactionId);
    bool Verify(int userId, string transactionId, string signature);
}

/// <summary>
/// REKLAM ODULU DOGRULAMASI (Server-Side Verification — SSV)
///
/// PROBLEM: Istemci "reklami izledim, odulu ver" derse buna guvenilemez.
/// Tarayici konsolunda tek satirla taklit edilir:
///     fetch('/api/ads/reward', { method: 'POST' })
/// Odul dogrudan paraya donustugu icin bu, ekonominin sonu olur.
///
/// GERCEK COZUM: Reklam agi (AdMob, Unity Ads, AppLovin) izleme tamamlandiginda
/// ISTEMCIYE DEGIL, DOGRUDAN SUNUCUMUZA bir bildirim gonderir. Istemci bu akisin
/// icinde hic yer almaz — dolayisiyla taklit edemez.
///
/// Peki bildirimin gercekten reklam agindan geldigini nasil bilecegiz?
/// Ag ile aramizda paylasilan GIZLI ANAHTAR ile imzalanir:
///
///     imza = HMACSHA256(userId + ":" + transactionId, gizliAnahtar)
///
/// Anahtari bilmeyen bir saldirgan gecerli imza uretemez. Bu, JWT'yi
/// imzalarken kullandigimiz mantigin aynisidir.
///
/// BU PROJEDE: Gercek bir reklam agi entegrasyonu staj kapsamini asardigi icin
/// akisi SIMULE ediyoruz — ama imza uretimi ve dogrulamasi GERCEKTIR.
/// Simulasyon ucu yalnizca Development ortaminda aciktir.
/// </summary>
public class AdSignatureService : IAdSignatureService
{
    private readonly byte[] _secret;

    public AdSignatureService(IConfiguration configuration)
    {
        var secret = configuration["Ads:CallbackSecret"]
            ?? throw new InvalidOperationException("appsettings.json icinde Ads:CallbackSecret tanimli degil!");

        _secret = Encoding.UTF8.GetBytes(secret);
    }

    /// <summary>
    /// Imzayi uretir. Gercekte bunu reklam agi yapar; biz yalnizca
    /// dogrulamak (ve gelistirme ortaminda simule etmek) icin kullaniyoruz.
    /// </summary>
    public string Compute(int userId, string transactionId)
    {
        var payload = Encoding.UTF8.GetBytes($"{userId}:{transactionId}");

        using var hmac = new HMACSHA256(_secret);
        var hash = hmac.ComputeHash(payload);

        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    /// <summary>
    /// Gelen imzayi dogrular.
    ///
    /// Karsilastirma yine FixedTimeEquals ile: sifre dogrulamada oldugu gibi
    /// burada da normal karsilastirma sure farki sizdirir ve saldirgan imzayi
    /// karakter karakter cozebilir (timing attack).
    /// </summary>
    public bool Verify(int userId, string transactionId, string signature)
    {
        if (string.IsNullOrWhiteSpace(signature))
        {
            return false;
        }

        var expected = Compute(userId, transactionId);

        try
        {
            return CryptographicOperations.FixedTimeEquals(
                Convert.FromHexString(expected),
                Convert.FromHexString(signature));
        }
        catch (FormatException)
        {
            // Imza gecerli onaltilik (hex) bir metin degil.
            return false;
        }
    }
}
