using System.Data;
using Dapper;
using MinerInMine.Api.Dtos;

namespace MinerInMine.Api.Data;

/// <summary>sp_Mine'in ham ciktisi: RETURN kodu + OUTPUT mesaj + sonuc satiri.</summary>
public record MineDbResult(int ReturnCode, string? ErrorMessage, MineResultDto? Data);

public interface IGameRepository
{
    Task<PlayerStateDto> GetPlayerStateAsync(int userId);
    Task<MineDbResult> MineAsync(int userId, int facilityTypeId, int clickTypeId);
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

        return new PlayerStateDto
        {
            Resources = (await multi.ReadAsync<ResourceDto>()).ToList(),
            Facilities = (await multi.ReadAsync<FacilityDto>()).ToList(),
            ClickTypes = (await multi.ReadAsync<ClickTypeDto>()).ToList(),
            FacilityClicks = (await multi.ReadAsync<FacilityClickDto>()).ToList(),
            ServerTime = await multi.ReadSingleAsync<DateTime>()
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
}
