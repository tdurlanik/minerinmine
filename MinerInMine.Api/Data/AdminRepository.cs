using System.Data;
using Dapper;
using MinerInMine.Api.Dtos;

namespace MinerInMine.Api.Data;

public record AdRewardDbResult(int ReturnCode, string? ErrorMessage, AdRewardResultDto? Data);
public record AdminAdjustDbResult(int ReturnCode, string? ErrorMessage, AdminAdjustResultDto? Data);
public record AdminSetActiveDbResult(int ReturnCode, string? ErrorMessage, AdminSetActiveResultDto? Data);
public record AdminSetRoleDbResult(int ReturnCode, string? ErrorMessage, AdminSetRoleResultDto? Data);
public record AdminRevokeDbResult(int ReturnCode, string? ErrorMessage, AdminRevokeSessionsResultDto? Data);

public interface IAdminRepository
{
    Task<LeaderboardDto> GetLeaderboardAsync(int userId, int top);
    Task<AdminPlayerListDto> GetPlayersAsync(string? search, int page, int pageSize);
    Task<AdminAdjustDbResult> AdjustResourceAsync(int adminUserId, AdminAdjustRequest request);
    Task<List<SuspiciousEntryDto>> GetSuspiciousAsync(int minutes, long minGain);
    Task<AdRewardDbResult> GrantAdRewardAsync(int userId, string transactionId);
    Task<AdminPlayerDetailDto> GetPlayerDetailAsync(int userId);
    Task<AdminSetActiveDbResult> SetActiveAsync(int adminUserId, int targetUserId, bool isActive);
    Task<AdminSetRoleDbResult> SetRoleAsync(int adminUserId, int targetUserId, string roleName, bool grant);
    Task<AdminRevokeDbResult> RevokeSessionsAsync(int adminUserId, int targetUserId);
    Task<EconomyReportDto> GetEconomyAsync(int days);
    Task<List<AdminActionLogDto>> GetActionLogAsync(int top);
}

public class AdminRepository : IAdminRepository
{
    private readonly ISqlConnectionFactory _factory;

    public AdminRepository(ISqlConnectionFactory factory) => _factory = factory;

    /// <summary>
    /// Siralama. SP iki sonuc kumesi doner: ilk N oyuncu ve istekte bulunanin
    /// kendi sirasi. Oyuncu listede yoksa ikinci kume bos gelir.
    /// </summary>
    public async Task<LeaderboardDto> GetLeaderboardAsync(int userId, int top)
    {
        using var connection = _factory.CreateConnection();

        using var multi = await connection.QueryMultipleAsync(
            "sp_GetLeaderboard",
            new { UserId = userId, Top = top },
            commandType: CommandType.StoredProcedure);

        return new LeaderboardDto
        {
            Top = (await multi.ReadAsync<LeaderboardEntryDto>()).ToList(),
            Me = await multi.ReadSingleOrDefaultAsync<MyRankDto>()
        };
    }

    public async Task<AdminPlayerListDto> GetPlayersAsync(string? search, int page, int pageSize)
    {
        using var connection = _factory.CreateConnection();

        using var multi = await connection.QueryMultipleAsync(
            "sp_AdminGetPlayers",
            new { Search = search, Page = page, PageSize = pageSize },
            commandType: CommandType.StoredProcedure);

        var players = (await multi.ReadAsync<AdminPlayerDto>()).ToList();
        var total = await multi.ReadSingleAsync<int>();

        return new AdminPlayerListDto
        {
            Players = players,
            TotalCount = total,
            Page = page,
            PageSize = pageSize
        };
    }

    public async Task<AdminAdjustDbResult> AdjustResourceAsync(int adminUserId, AdminAdjustRequest request)
    {
        using var connection = _factory.CreateConnection();

        var p = new DynamicParameters();
        p.Add("@AdminUserId", adminUserId, DbType.Int32);
        p.Add("@TargetUserId", request.TargetUserId, DbType.Int32);
        p.Add("@ResourceTypeId", request.ResourceTypeId, DbType.Int32);
        p.Add("@Delta", request.Delta, DbType.Int64);
        p.Add("@ErrorMessage", dbType: DbType.String, size: 255, direction: ParameterDirection.Output);
        p.Add("@ReturnValue", dbType: DbType.Int32, direction: ParameterDirection.ReturnValue);

        var data = await connection.QuerySingleOrDefaultAsync<AdminAdjustResultDto>(
            "sp_AdminAdjustResource", p, commandType: CommandType.StoredProcedure);

        return new AdminAdjustDbResult(
            p.Get<int>("@ReturnValue"), p.Get<string?>("@ErrorMessage"), data);
    }

    public async Task<List<SuspiciousEntryDto>> GetSuspiciousAsync(int minutes, long minGain)
    {
        using var connection = _factory.CreateConnection();

        var rows = await connection.QueryAsync<SuspiciousEntryDto>(
            "sp_AdminGetSuspicious",
            new { Minutes = minutes, MinGain = minGain },
            commandType: CommandType.StoredProcedure);

        return rows.ToList();
    }

    public async Task<AdRewardDbResult> GrantAdRewardAsync(int userId, string transactionId)
    {
        using var connection = _factory.CreateConnection();

        var p = new DynamicParameters();
        p.Add("@UserId", userId, DbType.Int32);
        p.Add("@TransactionId", transactionId, DbType.String, size: 100);
        p.Add("@ErrorMessage", dbType: DbType.String, size: 255, direction: ParameterDirection.Output);
        p.Add("@ReturnValue", dbType: DbType.Int32, direction: ParameterDirection.ReturnValue);

        var data = await connection.QuerySingleOrDefaultAsync<AdRewardResultDto>(
            "sp_GrantAdReward", p, commandType: CommandType.StoredProcedure);

        return new AdRewardDbResult(
            p.Get<int>("@ReturnValue"), p.Get<string?>("@ErrorMessage"), data);
    }

    /// <summary>
    /// Tek oyuncunun tum durumu. sp_AdminGetPlayerDetail BES sonuc kumesi doner;
    /// buradaki okuma sirasi SP icindeki SELECT sirasiyla ayni olmak zorundadir.
    /// </summary>
    public async Task<AdminPlayerDetailDto> GetPlayerDetailAsync(int userId)
    {
        using var connection = _factory.CreateConnection();

        using var multi = await connection.QueryMultipleAsync(
            "sp_AdminGetPlayerDetail",
            new { UserId = userId },
            commandType: CommandType.StoredProcedure);

        return new AdminPlayerDetailDto
        {
            Player = await multi.ReadSingleOrDefaultAsync<AdminPlayerInfoDto>(),
            Resources = (await multi.ReadAsync<AdminResourceDto>()).ToList(),
            Facilities = (await multi.ReadAsync<AdminFacilityDto>()).ToList(),
            Miners = (await multi.ReadAsync<AdminMinerDto>()).ToList(),
            Transactions = (await multi.ReadAsync<AdminTransactionDto>()).ToList()
        };
    }

    public async Task<AdminSetActiveDbResult> SetActiveAsync(int adminUserId, int targetUserId, bool isActive)
    {
        using var connection = _factory.CreateConnection();

        var p = new DynamicParameters();
        p.Add("@AdminUserId", adminUserId, DbType.Int32);
        p.Add("@TargetUserId", targetUserId, DbType.Int32);
        p.Add("@IsActive", isActive, DbType.Boolean);
        p.Add("@ErrorMessage", dbType: DbType.String, size: 255, direction: ParameterDirection.Output);
        p.Add("@ReturnValue", dbType: DbType.Int32, direction: ParameterDirection.ReturnValue);

        var data = await connection.QuerySingleOrDefaultAsync<AdminSetActiveResultDto>(
            "sp_AdminSetActive", p, commandType: CommandType.StoredProcedure);

        return new AdminSetActiveDbResult(
            p.Get<int>("@ReturnValue"), p.Get<string?>("@ErrorMessage"), data);
    }

    public async Task<AdminSetRoleDbResult> SetRoleAsync(int adminUserId, int targetUserId, string roleName, bool grant)
    {
        using var connection = _factory.CreateConnection();

        var p = new DynamicParameters();
        p.Add("@AdminUserId", adminUserId, DbType.Int32);
        p.Add("@TargetUserId", targetUserId, DbType.Int32);
        p.Add("@RoleName", roleName, DbType.String, size: 50);
        p.Add("@Grant", grant, DbType.Boolean);
        p.Add("@ErrorMessage", dbType: DbType.String, size: 255, direction: ParameterDirection.Output);
        p.Add("@ReturnValue", dbType: DbType.Int32, direction: ParameterDirection.ReturnValue);

        var data = await connection.QuerySingleOrDefaultAsync<AdminSetRoleResultDto>(
            "sp_AdminSetRole", p, commandType: CommandType.StoredProcedure);

        return new AdminSetRoleDbResult(
            p.Get<int>("@ReturnValue"), p.Get<string?>("@ErrorMessage"), data);
    }

    public async Task<AdminRevokeDbResult> RevokeSessionsAsync(int adminUserId, int targetUserId)
    {
        using var connection = _factory.CreateConnection();

        var p = new DynamicParameters();
        p.Add("@AdminUserId", adminUserId, DbType.Int32);
        p.Add("@TargetUserId", targetUserId, DbType.Int32);
        p.Add("@ErrorMessage", dbType: DbType.String, size: 255, direction: ParameterDirection.Output);
        p.Add("@ReturnValue", dbType: DbType.Int32, direction: ParameterDirection.ReturnValue);

        var data = await connection.QuerySingleOrDefaultAsync<AdminRevokeSessionsResultDto>(
            "sp_AdminRevokeSessions", p, commandType: CommandType.StoredProcedure);

        return new AdminRevokeDbResult(
            p.Get<int>("@ReturnValue"), p.Get<string?>("@ErrorMessage"), data);
    }

    /// <summary>
    /// Ekonomi sagligi raporu. sp_AdminGetEconomy BES sonuc kumesi doner;
    /// okuma sirasi SP icindeki SELECT sirasiyla ayni olmak zorundadir.
    /// </summary>
    public async Task<EconomyReportDto> GetEconomyAsync(int days)
    {
        using var connection = _factory.CreateConnection();

        using var multi = await connection.QueryMultipleAsync(
            "sp_AdminGetEconomy",
            new { Days = days },
            commandType: CommandType.StoredProcedure);

        return new EconomyReportDto
        {
            Summary = await multi.ReadSingleOrDefaultAsync<EconomySummaryDto>() ?? new EconomySummaryDto(),
            Daily = (await multi.ReadAsync<EconomyDailyDto>()).ToList(),
            Reasons = (await multi.ReadAsync<EconomyReasonDto>()).ToList(),
            Facilities = (await multi.ReadAsync<EconomyFacilityDto>()).ToList(),
            Clicks = (await multi.ReadAsync<EconomyClickDto>()).ToList()
        };
    }

    /// <summary>
    /// Son yonetici mudahaleleri. Denetim izi iki tabloda duruyor
    /// (AdminActions + Transactions/ADMIN_ADJUST); SP ikisini UNION ALL ile
    /// tek listede birlestiriyor.
    /// </summary>
    public async Task<List<AdminActionLogDto>> GetActionLogAsync(int top)
    {
        using var connection = _factory.CreateConnection();

        var rows = await connection.QueryAsync<AdminActionLogDto>(
            "sp_AdminGetActionLog",
            new { Top = top },
            commandType: CommandType.StoredProcedure);

        return rows.ToList();
    }
}
