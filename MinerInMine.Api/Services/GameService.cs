using MinerInMine.Api.Data;
using MinerInMine.Api.Dtos;

namespace MinerInMine.Api.Services;

public interface IGameService
{
    Task<PlayerStateDto> GetStateAsync(int userId);
    Task<ServiceResult<MineResultDto>> MineAsync(int userId, MineRequest request);
}

/// <summary>
/// Oyun is mantigi katmani.
///
/// Bu sinif SP'nin dondurdugu sayisal hata kodlarini, istemcinin anlayacagi
/// mesajlara ve HTTP durumlarina cevirir. Kural olarak asil DOGRULAMA burada
/// DEGIL, SP icinde yapilir — cunku yaris durumunu ancak veritabani
/// seviyesinde atomik olarak engelleyebiliriz.
///
/// Buradaki kontroller "kullaniciya duzgun mesaj gostermek" icindir,
/// guvenlik icin degil.
/// </summary>
public class GameService : IGameService
{
    private readonly IGameRepository _repository;
    private readonly ILogger<GameService> _logger;

    public GameService(IGameRepository repository, ILogger<GameService> logger)
    {
        _repository = repository;
        _logger = logger;
    }

    public Task<PlayerStateDto> GetStateAsync(int userId) => _repository.GetPlayerStateAsync(userId);

    public async Task<ServiceResult<MineResultDto>> MineAsync(int userId, MineRequest request)
    {
        var result = await _repository.MineAsync(userId, request.FacilityTypeId, request.ClickTypeId);

        // sp_Mine'in RETURN kodlari:
        //   0   basarili
        //  -1   kazma turu acilmamis
        //  -2   tesise sahip degil
        //  -3   bekleme suresi dolmamis   (en sik gorulen: normal oyun akisi)
        //  -99  beklenmeyen hata
        switch (result.ReturnCode)
        {
            case 0 when result.Data is not null:
                return ServiceResult<MineResultDto>.Ok(result.Data);

            case -1:
            case -2:
            case -3:
                return ServiceResult<MineResultDto>.Fail(result.ErrorMessage ?? "Kazma yapılamadı.");

            default:
                _logger.LogError(
                    "sp_Mine beklenmeyen sonuc. UserId={UserId} Facility={Facility} Click={Click} RC={RC} Hata={Error}",
                    userId, request.FacilityTypeId, request.ClickTypeId, result.ReturnCode, result.ErrorMessage);

                return ServiceResult<MineResultDto>.Fail("Kazma sırasında beklenmeyen bir hata oluştu.");
        }
    }
}
