using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;

namespace MinerInMine.Api.Extensions;

/// <summary>
/// Token icindeki kullanici kimligini okumak icin yardimci metotlar.
///
/// NEDEN AYRI BIR SINIF?
/// "sub claim'ini bul, int'e cevir, olmazsa hata" mantigi her korumali
/// controller'da tekrarlanacakti. Tek yere alarak hem tekrari onluyoruz hem de
/// ileride claim adi degisirse tek dosyayi guncelliyoruz.
///
/// EXTENSION METHOD: Var olan bir sinifa (ClaimsPrincipal) kaynagina
/// dokunmadan metot eklememizi saglar. 'this' anahtar kelimesi ilk parametrede
/// kullanildiginda C# bunu "o tipin metoduymus gibi" cagirmamiza izin verir:
///     User.GetUserId()
/// </summary>
public static class ClaimsPrincipalExtensions
{
    /// <summary>
    /// Token'daki "sub" claim'inden kullanici Id'sini okur.
    /// Okunamazsa null doner (controller 401 dondurur).
    /// </summary>
    public static int? GetUserId(this ClaimsPrincipal user)
    {
        var value = user.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;

        return int.TryParse(value, out var id) ? id : null;
    }
}
