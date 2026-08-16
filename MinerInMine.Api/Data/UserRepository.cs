using System.Data;
using Dapper;
using MinerInMine.Api.Models;

namespace MinerInMine.Api.Data;

/// <summary>
/// sp_RegisterUser'ın çıktısını taşıyan küçük kayıt tipi.
/// SP hem OUTPUT parametre hem de RETURN kodu döndürdüğü için ikisini bir arada tutuyoruz.
/// ReturnCode:  0 = başarılı | -1 = kullanıcı adı dolu | -2 = e-posta dolu | -99 = beklenmeyen hata
/// </summary>
public record RegisterDbResult(int ReturnCode, int NewUserId, string? ErrorMessage);

public interface IUserRepository
{
    Task<RegisterDbResult> RegisterAsync(string username, string email, string passwordHash, string passwordSalt);
    Task<User?> GetByLoginAsync(string loginInput);
    Task<List<Role>> GetRolesAsync(int userId);
    Task SaveRefreshTokenAsync(int userId, string token, DateTime expiresAt);
    Task<RefreshToken?> GetRefreshTokenAsync(string token);
    Task RevokeRefreshTokenAsync(string token, string? replacedByToken = null);
    Task UpdateLastLoginAsync(int userId);
}

/// <summary>
/// TÜM veritabanı erişimi burada toplanır ve YALNIZCA Stored Procedure çağrılır.
/// Bu dosyada tek bir "SELECT ... FROM ..." cümlesi göremezsiniz — proje kuralı budur.
///
/// CommandType.StoredProcedure demek, Dapper'a "bu bir SQL metni değil, bir SP adı"
/// demektir. Böylece parametreler SQL metnine string olarak yapıştırılmaz,
/// ADO.NET tarafından tipli parametre olarak gönderilir → SQL Injection imkânsız hale gelir.
/// </summary>
public class UserRepository : IUserRepository
{
    private readonly ISqlConnectionFactory _factory;

    public UserRepository(ISqlConnectionFactory factory) => _factory = factory;

    // ------------------------------------------------------------------------
    // 1. KAYIT — sp_RegisterUser
    // Bu SP tek başına 3 tabloya yazar (Users, UserRoles, PlayerProfiles) ve bunu
    // TRANSACTION içinde yapar. Yani ya üçü birden oluşur ya da hiçbiri.
    // C# tarafında 3 ayrı INSERT yazsaydık, ikincisi patladığında yarım kullanıcı kalırdı.
    // ------------------------------------------------------------------------
    public async Task<RegisterDbResult> RegisterAsync(string username, string email, string passwordHash, string passwordSalt)
    {
        using var connection = _factory.CreateConnection();

        // DynamicParameters: OUTPUT ve RETURN değerlerini yakalayabilmemizi sağlar.
        var parameters = new DynamicParameters();
        parameters.Add("@Username", username, DbType.String, size: 50);
        parameters.Add("@Email", email, DbType.String, size: 100);
        parameters.Add("@PasswordHash", passwordHash, DbType.String, size: 256);
        parameters.Add("@PasswordSalt", passwordSalt, DbType.String, size: 256);
        parameters.Add("@RoleName", "Player", DbType.String, size: 50);

        // OUTPUT parametreler: SP çalıştıktan SONRA değerleri okunur.
        parameters.Add("@NewUserId", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@ErrorMessage", dbType: DbType.String, size: 255, direction: ParameterDirection.Output);

        // RETURN değeri: SP içindeki "RETURN 0 / -1 / -2 / -99" ifadelerini yakalar.
        parameters.Add("@ReturnValue", dbType: DbType.Int32, direction: ParameterDirection.ReturnValue);

        await connection.ExecuteAsync("sp_RegisterUser", parameters, commandType: CommandType.StoredProcedure);

        return new RegisterDbResult(
            ReturnCode: parameters.Get<int>("@ReturnValue"),
            NewUserId: parameters.Get<int?>("@NewUserId") ?? 0,
            ErrorMessage: parameters.Get<string?>("@ErrorMessage")
        );
    }

    // ------------------------------------------------------------------------
    // 2. GİRİŞ İÇİN KULLANICI BULMA — sp_GetUserByLogin
    // QuerySingleOrDefaultAsync: 0 satır gelirse null, 1 satır gelirse nesne döner.
    // Birden fazla satır gelirse hata fırlatır — Username ve Email UNIQUE olduğu için
    // bu durum zaten oluşamaz; oluşursa veri bütünlüğü bozulmuş demektir, bilmek isteriz.
    // ------------------------------------------------------------------------
    public async Task<User?> GetByLoginAsync(string loginInput)
    {
        using var connection = _factory.CreateConnection();

        return await connection.QuerySingleOrDefaultAsync<User>(
            "sp_GetUserByLogin",
            new { LoginInput = loginInput },   // anonim nesne = parametre listesi
            commandType: CommandType.StoredProcedure);
    }

    // ------------------------------------------------------------------------
    // 3. ROLLER — sp_GetUserRoles
    // JWT üretilirken çağrılır; her rol token'a bir claim olarak eklenir.
    // ------------------------------------------------------------------------
    public async Task<List<Role>> GetRolesAsync(int userId)
    {
        using var connection = _factory.CreateConnection();

        var roles = await connection.QueryAsync<Role>(
            "sp_GetUserRoles",
            new { UserId = userId },
            commandType: CommandType.StoredProcedure);

        return roles.ToList();
    }

    // ------------------------------------------------------------------------
    // 4. REFRESH TOKEN KAYDET — sp_SaveRefreshToken
    // ------------------------------------------------------------------------
    public async Task SaveRefreshTokenAsync(int userId, string token, DateTime expiresAt)
    {
        using var connection = _factory.CreateConnection();

        await connection.ExecuteAsync(
            "sp_SaveRefreshToken",
            new { UserId = userId, Token = token, ExpiresAt = expiresAt },
            commandType: CommandType.StoredProcedure);
    }

    // ------------------------------------------------------------------------
    // 5. REFRESH TOKEN OKU — sp_GetRefreshToken
    // ------------------------------------------------------------------------
    public async Task<RefreshToken?> GetRefreshTokenAsync(string token)
    {
        using var connection = _factory.CreateConnection();

        return await connection.QuerySingleOrDefaultAsync<RefreshToken>(
            "sp_GetRefreshToken",
            new { Token = token },
            commandType: CommandType.StoredProcedure);
    }

    // ------------------------------------------------------------------------
    // 6. REFRESH TOKEN İPTAL — sp_RevokeRefreshToken
    // replacedByToken dolu gelirse "rotation" (yenisiyle değiştirildi),
    // null gelirse "logout" anlamına gelir. İkisi de aynı SP ile yapılır.
    // ------------------------------------------------------------------------
    public async Task RevokeRefreshTokenAsync(string token, string? replacedByToken = null)
    {
        using var connection = _factory.CreateConnection();

        await connection.ExecuteAsync(
            "sp_RevokeRefreshToken",
            new { Token = token, ReplacedByToken = replacedByToken },
            commandType: CommandType.StoredProcedure);
    }

    // ------------------------------------------------------------------------
    // 7. SON GİRİŞ ZAMANI — sp_UpdateLastLogin
    // ------------------------------------------------------------------------
    public async Task UpdateLastLoginAsync(int userId)
    {
        using var connection = _factory.CreateConnection();

        await connection.ExecuteAsync(
            "sp_UpdateLastLogin",
            new { UserId = userId },
            commandType: CommandType.StoredProcedure);
    }
}
