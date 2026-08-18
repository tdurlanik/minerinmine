using System.Data;
using Dapper;
using MinerInMine.Api.Dtos;

namespace MinerInMine.Api.Data;

/// <summary>sp_Mine'in ham ciktisi: RETURN kodu + OUTPUT mesaj + sonuc satiri.</summary>
public record MineDbResult(int ReturnCode, string? ErrorMessage, MineResultDto? Data);
public record UpgradeStartDbResult(int ReturnCode, string? ErrorMessage, UpgradeStartedDto? Data);
public record UpgradeFinishDbResult(int ReturnCode, string? ErrorMessage, UpgradeFinishedDto? Data);
public record HireDbResult(int ReturnCode, string? ErrorMessage, HireMinerResultDto? Data);
public record SellDbResult(int ReturnCode, string? ErrorMessage, SellResultDto? Data);
public record PurchaseDbResult(int ReturnCode, string? ErrorMessage, PurchaseResultDto? Data);
public record UnlockDbResult(int ReturnCode, string? ErrorMessage, UnlockResultDto? Data);

/// <summary>sp_GetPlayerState son sonuc kumesi: sunucu saati + tamamlanan gelistirme sayisi.</summary>
internal record StateTailRow(DateTime ServerTime, int CompletedUpgrades);

public interface IGameRepository
{
    Task<PlayerStateDto> GetPlayerStateAsync(int userId);
    Task<MineDbResult> MineAsync(int userId, int facilityTypeId, int clickTypeId);
    Task<UpgradeStartDbResult> StartUpgradeAsync(int userId, int facilityTypeId);
    Task<UpgradeFinishDbResult> FinishUpgradeNowAsync(int userId, int facilityTypeId);
    Task<List<CollectedResourceDto>> CollectAsync(int userId);
    Task<HireDbResult> HireMinerAsync(int userId, int facilityTypeId, int minerTypeId);
    Task<SellDbResult> SellAsync(int userId, int resourceTypeId, long amount);
    Task<PurchaseDbResult> BuyUpgradeAsync(int userId, int upgradeTypeId);
    Task<UnlockDbResult> UnlockClickAsync(int userId, int clickTypeId);
}

/// <summary>
/// Oyun mekanigi veri erisimi. Yine yalnizca stored procedure cagrilir.
/// </summary>
public class GameRepository : IGameRepository
{
    private readonly ISqlConnectionFactory _factory;

    public GameRepository(ISqlConnectionFactory factory) => _factory = factory;

    /// <summary>
    /// Oyun ekraninin tamamini TEK veritabani gidis-donusunde okur.
    ///
    /// QueryMultipleAsync: SP birden fazla SELECT dondurdugunde hepsini sirayla
    /// okumamizi saglar. Ayri ayri 5 sorgu calistirsaydik 5 ag gidis-donusu olurdu;
    /// oyun ekrani sik yenilenecegi icin bu fark birikir.
    ///
    /// SIRA ONEMLIDIR: SP icindeki SELECT sirasi ile buradaki ReadAsync sirasi
    /// birebir ayni olmali. Biri kayarsa yanlis tabloyu yanlis tipe okuruz.
    /// </summary>
    public async Task<PlayerStateDto> GetPlayerStateAsync(int userId)
    {
        using var connection = _factory.CreateConnection();

        using var multi = await connection.QueryMultipleAsync(
            "sp_GetPlayerState",
            new { UserId = userId },
            commandType: CommandType.StoredProcedure);

        var resources = (await multi.ReadAsync<ResourceDto>()).ToList();
        var facilities = (await multi.ReadAsync<FacilityDto>()).ToList();
        var clickTypes = (await multi.ReadAsync<ClickTypeDto>()).ToList();
        var facilityClicks = (await multi.ReadAsync<FacilityClickDto>()).ToList();
        var miners = (await multi.ReadAsync<MinerDto>()).ToList();
        var upgrades = (await multi.ReadAsync<UpgradeDto>()).ToList();
        var pending = (await multi.ReadAsync<PendingProductionDto>()).ToList();
        var tail = await multi.ReadSingleAsync<StateTailRow>();

        return new PlayerStateDto
        {
            Resources = resources,
            Facilities = facilities,
            ClickTypes = clickTypes,
            FacilityClicks = facilityClicks,
            Miners = miners,
            Upgrades = upgrades,
            Pending = pending,
            // Son sonuc kumesi artik iki sutun donduruyor (ServerTime + CompletedUpgrades),
            // bu yuzden duz DateTime yerine kucuk bir kayit tipine okuyoruz.
            ServerTime = tail.ServerTime,
            CompletedUpgrades = tail.CompletedUpgrades
        };
    }

    /// <summary>
    /// Kazma islemi. Tum dogrulama ve hesaplama SP icinde yapilir.
    ///
    /// DIKKAT: Bu metot bir "kazanc miktari" parametresi ALMAZ. Alsaydi istemci
    /// istedigi sayiyi gonderebilirdi. Metodun imzasi bile sunucu otoritesini yansitir.
    /// </summary>
    public async Task<MineDbResult> MineAsync(int userId, int facilityTypeId, int clickTypeId)
    {
        using var connection = _factory.CreateConnection();

        var parameters = new DynamicParameters();
        parameters.Add("@UserId", userId, DbType.Int32);
        parameters.Add("@FacilityTypeId", facilityTypeId, DbType.Int32);
        parameters.Add("@ClickTypeId", clickTypeId, DbType.Int32);
        parameters.Add("@ErrorMessage", dbType: DbType.String, size: 255, direction: ParameterDirection.Output);
        parameters.Add("@ReturnValue", dbType: DbType.Int32, direction: ParameterDirection.ReturnValue);

        // Hata durumunda SP erken RETURN eder ve HIC sonuc satiri dondurmez;
        // bu yuzden SingleOrDefault kullaniyoruz (null gelebilir).
        var data = await connection.QuerySingleOrDefaultAsync<MineResultDto>(
            "sp_Mine", parameters, commandType: CommandType.StoredProcedure);

        // ONEMLI: OUTPUT ve RETURN degerleri ancak sonuc kumesi TAMAMEN okunduktan
        // sonra dolar. Bu yuzden bu satirlar QuerySingleOrDefaultAsync'ten SONRA gelir.
        return new MineDbResult(
            ReturnCode: parameters.Get<int>("@ReturnValue"),
            ErrorMessage: parameters.Get<string?>("@ErrorMessage"),
            Data: data);
    }

    /// <summary>
    /// Gelistirme baslatir. Maliyet, sure ve tum dogrulamalar SP icinde.
    /// Yine miktar/sure parametresi YOK — istemci sadece hangi tesis oldugunu soyler.
    /// </summary>
    public async Task<UpgradeStartDbResult> StartUpgradeAsync(int userId, int facilityTypeId)
    {
        using var connection = _factory.CreateConnection();

        var p = new DynamicParameters();
        p.Add("@UserId", userId, DbType.Int32);
        p.Add("@FacilityTypeId", facilityTypeId, DbType.Int32);
        p.Add("@ErrorMessage", dbType: DbType.String, size: 255, direction: ParameterDirection.Output);
        p.Add("@ReturnValue", dbType: DbType.Int32, direction: ParameterDirection.ReturnValue);

        var data = await connection.QuerySingleOrDefaultAsync<UpgradeStartedDto>(
            "sp_StartFacilityUpgrade", p, commandType: CommandType.StoredProcedure);

        return new UpgradeStartDbResult(
            p.Get<int>("@ReturnValue"), p.Get<string?>("@ErrorMessage"), data);
    }

    /// <summary>
    /// Devam eden gelistirmeyi Kristal odeyerek aninda bitirir.
    /// Bedeli sunucu KALAN SUREYE gore hesaplar; istemci fiyat gonderemez.
    /// </summary>
    public async Task<UpgradeFinishDbResult> FinishUpgradeNowAsync(int userId, int facilityTypeId)
    {
        using var connection = _factory.CreateConnection();

        var p = new DynamicParameters();
        p.Add("@UserId", userId, DbType.Int32);
        p.Add("@FacilityTypeId", facilityTypeId, DbType.Int32);
        p.Add("@ErrorMessage", dbType: DbType.String, size: 255, direction: ParameterDirection.Output);
        p.Add("@ReturnValue", dbType: DbType.Int32, direction: ParameterDirection.ReturnValue);

        var data = await connection.QuerySingleOrDefaultAsync<UpgradeFinishedDto>(
            "sp_FinishUpgradeNow", p, commandType: CommandType.StoredProcedure);

        return new UpgradeFinishDbResult(
            p.Get<int>("@ReturnValue"), p.Get<string?>("@ErrorMessage"), data);
    }

    /// <summary>
    /// Birikmis uretimi toplar. Hesap tamamen SP icinde; istemci miktar gonderemez.
    /// Bu SP hata kodu dondurmez, dogrudan toplanan kaynaklarin listesini verir.
    /// </summary>
    public async Task<List<CollectedResourceDto>> CollectAsync(int userId)
    {
        using var connection = _factory.CreateConnection();

        var p = new DynamicParameters();
        p.Add("@UserId", userId, DbType.Int32);
        p.Add("@ErrorMessage", dbType: DbType.String, size: 255, direction: ParameterDirection.Output);

        var rows = await connection.QueryAsync<CollectedResourceDto>(
            "sp_CollectProduction", p, commandType: CommandType.StoredProcedure);

        return rows.ToList();
    }

    public async Task<HireDbResult> HireMinerAsync(int userId, int facilityTypeId, int minerTypeId)
    {
        using var connection = _factory.CreateConnection();

        var p = new DynamicParameters();
        p.Add("@UserId", userId, DbType.Int32);
        p.Add("@FacilityTypeId", facilityTypeId, DbType.Int32);
        p.Add("@MinerTypeId", minerTypeId, DbType.Int32);
        p.Add("@ErrorMessage", dbType: DbType.String, size: 255, direction: ParameterDirection.Output);
        p.Add("@ReturnValue", dbType: DbType.Int32, direction: ParameterDirection.ReturnValue);

        var data = await connection.QuerySingleOrDefaultAsync<HireMinerResultDto>(
            "sp_HireMiner", p, commandType: CommandType.StoredProcedure);

        return new HireDbResult(p.Get<int>("@ReturnValue"), p.Get<string?>("@ErrorMessage"), data);
    }

    public async Task<SellDbResult> SellAsync(int userId, int resourceTypeId, long amount)
    {
        using var connection = _factory.CreateConnection();

        var p = new DynamicParameters();
        p.Add("@UserId", userId, DbType.Int32);
        p.Add("@ResourceTypeId", resourceTypeId, DbType.Int32);
        p.Add("@Amount", amount, DbType.Int64);
        p.Add("@ErrorMessage", dbType: DbType.String, size: 255, direction: ParameterDirection.Output);
        p.Add("@ReturnValue", dbType: DbType.Int32, direction: ParameterDirection.ReturnValue);

        var data = await connection.QuerySingleOrDefaultAsync<SellResultDto>(
            "sp_SellResource", p, commandType: CommandType.StoredProcedure);

        return new SellDbResult(p.Get<int>("@ReturnValue"), p.Get<string?>("@ErrorMessage"), data);
    }

    public async Task<PurchaseDbResult> BuyUpgradeAsync(int userId, int upgradeTypeId)
    {
        using var connection = _factory.CreateConnection();

        var p = new DynamicParameters();
        p.Add("@UserId", userId, DbType.Int32);
        p.Add("@UpgradeTypeId", upgradeTypeId, DbType.Int32);
        p.Add("@ErrorMessage", dbType: DbType.String, size: 255, direction: ParameterDirection.Output);
        p.Add("@ReturnValue", dbType: DbType.Int32, direction: ParameterDirection.ReturnValue);

        var data = await connection.QuerySingleOrDefaultAsync<PurchaseResultDto>(
            "sp_BuyUpgrade", p, commandType: CommandType.StoredProcedure);

        return new PurchaseDbResult(p.Get<int>("@ReturnValue"), p.Get<string?>("@ErrorMessage"), data);
    }

    public async Task<UnlockDbResult> UnlockClickAsync(int userId, int clickTypeId)
    {
        using var connection = _factory.CreateConnection();

        var p = new DynamicParameters();
        p.Add("@UserId", userId, DbType.Int32);
        p.Add("@ClickTypeId", clickTypeId, DbType.Int32);
        p.Add("@ErrorMessage", dbType: DbType.String, size: 255, direction: ParameterDirection.Output);
        p.Add("@ReturnValue", dbType: DbType.Int32, direction: ParameterDirection.ReturnValue);

        var data = await connection.QuerySingleOrDefaultAsync<UnlockResultDto>(
            "sp_UnlockClickType", p, commandType: CommandType.StoredProcedure);

        return new UnlockDbResult(p.Get<int>("@ReturnValue"), p.Get<string?>("@ErrorMessage"), data);
    }
}
