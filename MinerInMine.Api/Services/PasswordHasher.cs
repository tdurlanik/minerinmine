using System.Security.Cryptography;
using System.Text;

namespace MinerInMine.Api.Services;

public interface IPasswordHasher
{
    (string Hash, string Salt) Create(string password);
    bool Verify(string password, string storedHash, string storedSalt);
}

/// <summary>
/// ŞİFRE GÜVENLİĞİ — HMACSHA512 ile hash + salt
///
/// TEMEL KURAL: Şifreler veritabanında ASLA açık metin (plaintext) tutulmaz.
/// Veritabanı çalınsa bile şifreler geri döndürülemez olmalıdır.
///
/// HASH NEDİR?
/// Tek yönlü matematiksel dönüşüm. "1234" -> "a3f9c2..." üretilir ama
/// "a3f9c2..." -> "1234" geri hesaplanamaz. Giriş yaparken de aynı dönüşümü
/// uygulayıp sonuçları karşılaştırırız.
///
/// SALT (TUZ) NEDİR, NEDEN GEREKLİ?
/// Salt olmasaydı, aynı şifreyi kullanan iki kullanıcının hash'i AYNI olurdu.
/// Saldırgan "en çok kullanılan 10.000 şifrenin hash'i" tablosunu (rainbow table)
/// önceden hazırlayıp veritabanıyla eşleştirebilirdi.
/// Her kullanıcıya rastgele bir salt verince aynı şifre bile farklı hash üretir
/// ve hazır tablolar işe yaramaz hale gelir.
///
/// NEDEN HMACSHA512?
/// Bu projede öğretici sadelik için seçildi: ekstra paket gerektirmez ve
/// salt/hash ayrımını çok net gösterir.
/// GERÇEK DÜNYA NOTU: Üretim ortamında PBKDF2 (Rfc2898DeriveBytes), bcrypt veya
/// Argon2 tercih edilir. Farkları: bunlar KASITLI OLARAK YAVAŞ çalışır
/// (yüz binlerce iterasyon). HMACSHA512 çok hızlıdır — saldırgan saniyede
/// milyarlarca deneme yapabilir. Yavaşlık, brute-force saldırısında savunmadır.
/// </summary>
public class PasswordHasher : IPasswordHasher
{
    /// <summary>
    /// Yeni bir şifre için (hash, salt) çifti üretir.
    /// Dönen iki değer de Base64 string'dir çünkü veritabanındaki kolonlar NVARCHAR(256).
    /// </summary>
    public (string Hash, string Salt) Create(string password)
    {
        // HMACSHA512 parametresiz kurulduğunda kriptografik olarak güvenli,
        // RASTGELE bir Key (128 byte) üretir. İşte bizim salt'ımız bu.
        using var hmac = new HMACSHA512();

        var saltBytes = hmac.Key;                                               // 128 byte
        var hashBytes = hmac.ComputeHash(Encoding.UTF8.GetBytes(password));     // 64 byte

        // Base64'e çevirince: 128 byte -> 172 karakter, 64 byte -> 88 karakter.
        // İkisi de NVARCHAR(256) sınırının altında kalır.
        return (Convert.ToBase64String(hashBytes), Convert.ToBase64String(saltBytes));
    }

    /// <summary>
    /// Girilen şifrenin, veritabanındaki hash ile eşleşip eşleşmediğini kontrol eder.
    /// Mantık: saklanan SALT ile HMAC'i yeniden kurar, hash'i yeniden hesaplar,
    /// sonucu saklanan hash ile karşılaştırır.
    /// </summary>
    public bool Verify(string password, string storedHash, string storedSalt)
    {
        try
        {
            var saltBytes = Convert.FromBase64String(storedSalt);
            var storedHashBytes = Convert.FromBase64String(storedHash);

            // Bu sefer Key'i biz veriyoruz: kayıt sırasında üretilmiş olan salt.
            using var hmac = new HMACSHA512(saltBytes);
            var computedHash = hmac.ComputeHash(Encoding.UTF8.GetBytes(password));

            // DİKKAT: Basit '==' veya SequenceEqual KULLANMIYORUZ.
            // Normal karşılaştırma ilk farklı byte'ta durur; doğru tahmin edilen
            // karakter sayısı arttıkça işlem mikro saniyeler kadar uzar. Saldırgan
            // bu süre farkını ölçerek şifreyi karakter karakter çözebilir
            // (timing attack). FixedTimeEquals ise her zaman aynı sürede çalışır.
            return CryptographicOperations.FixedTimeEquals(computedHash, storedHashBytes);
        }
        catch (FormatException)
        {
            // Veritabanındaki değer bozuksa / Base64 değilse: doğrulama başarısız.
            return false;
        }
    }
}
