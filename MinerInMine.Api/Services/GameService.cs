using MinerInMine.Api.Data;
using MinerInMine.Api.Dtos;

namespace MinerInMine.Api.Services;

public interface IGameService
{
    Task<PlayerStateDto> GetStateAsync(int userId);
    Task<ServiceResult<MineResultDto>> MineAsync(int userId, MineRequest request);
    Task<ServiceResult<UpgradeStartedDto>> StartUpgradeAsync(int userId, int facilityTypeId);
    Task<ServiceResult<UpgradeFinishedDto>> FinishUpgradeNowAsync(int userId, int facilityTypeId);
    Task<List<CollectedResourceDto>> CollectAsync(int userId);
    Task<ServiceResult<HireMinerResultDto>> HireMinerAsync(int userId, int facilityTypeId, int minerTypeId);
    Task<ServiceResult<SellResultDto>> SellAsync(int userId, SellRequest request);
    Task<ServiceResult<PurchaseResultDto>> BuyUpgradeAsync(int userId, int upgradeTypeId);
    Task<ServiceResult<UnlockResultDto>> UnlockClickAsync(int userId, int clickTypeId);
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

    /// <summary>
    /// Tesis gelistirmesi baslatir.
    ///
    /// sp_StartFacilityUpgrade RETURN kodlari:
    ///   0    basarili
    ///  -1    tesise sahip degil
    ///  -2    son seviyede
    ///  -3    zaten devam eden gelistirme var (ya da yaris durumunda kaybetti)
    ///  -4    yetersiz Kristal
    ///  -99   beklenmeyen hata
    /// </summary>
    public async Task<ServiceResult<UpgradeStartedDto>> StartUpgradeAsync(int userId, int facilityTypeId)
    {
        var result = await _repository.StartUpgradeAsync(userId, facilityTypeId);

        if (result.ReturnCode == 0 && result.Data is not null)
        {
            return ServiceResult<UpgradeStartedDto>.Ok(result.Data);
        }

        if (result.ReturnCode >= -4)
        {
            return ServiceResult<UpgradeStartedDto>.Fail(result.ErrorMessage ?? "Gelistirme baslatilamadi.");
        }

        _logger.LogError(
            "sp_StartFacilityUpgrade beklenmeyen sonuc. UserId={UserId} Facility={Facility} RC={RC} Hata={Error}",
            userId, facilityTypeId, result.ReturnCode, result.ErrorMessage);

        return ServiceResult<UpgradeStartedDto>.Fail("Geliştirme sırasında beklenmeyen bir hata oluştu.");
    }

    /// <summary>
    /// Devam eden gelistirmeyi Kristal odeyerek aninda bitirir.
    /// Bedel istemciden gelmez; sunucu kalan sureye gore hesaplar.
    /// </summary>
    public async Task<ServiceResult<UpgradeFinishedDto>> FinishUpgradeNowAsync(int userId, int facilityTypeId)
    {
        var result = await _repository.FinishUpgradeNowAsync(userId, facilityTypeId);

        if (result.ReturnCode == 0 && result.Data is not null)
        {
            return ServiceResult<UpgradeFinishedDto>.Ok(result.Data);
        }

        if (result.ReturnCode >= -4)
        {
            return ServiceResult<UpgradeFinishedDto>.Fail(result.ErrorMessage ?? "İşlem tamamlanamadı.");
        }

        _logger.LogError(
            "sp_FinishUpgradeNow beklenmeyen sonuc. UserId={UserId} Facility={Facility} RC={RC} Hata={Error}",
            userId, facilityTypeId, result.ReturnCode, result.ErrorMessage);

        return ServiceResult<UpgradeFinishedDto>.Fail("İşlem sırasında beklenmeyen bir hata oluştu.");
    }

    /// <summary>
    /// Birikmis uretimi toplar. Hata durumu yoktur: toplanacak bir sey yoksa
    /// bos liste doner. Bu yuzden ServiceResult sarmalayicisina gerek duymuyoruz.
    /// </summary>
    public Task<List<CollectedResourceDto>> CollectAsync(int userId) => _repository.CollectAsync(userId);

    /// <summary>
    /// Madenci ise alir.
    ///
    /// SIRA ONEMLI: Once birikmis uretim toplanir. Aksi halde yeni madenci,
    /// henuz calismadigi gecmis sure icin de uretmis gibi sayilirdi.
    /// Bu sirayi burada kuruyoruz; SP icinden cagirsaydik SP birden fazla
    /// sonuc kumesi dondururdu ve erken hata durumlarinda okuma karisirdi.
    /// </summary>
    public async Task<ServiceResult<HireMinerResultDto>> HireMinerAsync(int userId, int facilityTypeId, int minerTypeId)
    {
        await _repository.CollectAsync(userId);

        var r = await _repository.HireMinerAsync(userId, facilityTypeId, minerTypeId);
        return Yorumla(r.ReturnCode, r.ErrorMessage, r.Data, "Madenci işe alınamadı.", userId, "sp_HireMiner");
    }

    public async Task<ServiceResult<SellResultDto>> SellAsync(int userId, SellRequest request)
    {
        var r = await _repository.SellAsync(userId, request.ResourceTypeId, request.Amount);
        return Yorumla(r.ReturnCode, r.ErrorMessage, r.Data, "Satış yapılamadı.", userId, "sp_SellResource");
    }

    /// <summary>
    /// Kalici guclendirme alir.
    ///
    /// MINER_SPEED guclendirmesi uretim hizini degistirdigi icin, satin almadan
    /// once birikmis uretim ESKI hizla toplanir. Aksi halde gecmiste biriken
    /// uretim yeni (daha yuksek) hizla hesaplanir ve oyuncu haksiz kazanc elde ederdi.
    /// </summary>
    public async Task<ServiceResult<PurchaseResultDto>> BuyUpgradeAsync(int userId, int upgradeTypeId)
    {
        await _repository.CollectAsync(userId);

        var r = await _repository.BuyUpgradeAsync(userId, upgradeTypeId);
        return Yorumla(r.ReturnCode, r.ErrorMessage, r.Data, "Güçlendirme alınamadı.", userId, "sp_BuyUpgrade");
    }

    public async Task<ServiceResult<UnlockResultDto>> UnlockClickAsync(int userId, int clickTypeId)
    {
        var r = await _repository.UnlockClickAsync(userId, clickTypeId);
        return Yorumla(r.ReturnCode, r.ErrorMessage, r.Data, "Kazma türü açılamadı.", userId, "sp_UnlockClickType");
    }

    /// <summary>
    /// SP RETURN kodlarini ServiceResult'a ceviren ortak yardimci.
    ///
    /// Kural: 0 = basarili, -1..-9 = beklenen is kurali hatasi (kullaniciya
    /// SP'nin mesaji gosterilir), digerleri = beklenmeyen hata (loglanir ve
    /// kullaniciya genel mesaj verilir; ic detay sizdirilmaz).
    ///
    /// Bu mantik dort metotta da ayni oldugu icin tek yere alindi.
    /// </summary>
    private ServiceResult<T> Yorumla<T>(
        int returnCode, string? errorMessage, T? data, string varsayilan, int userId, string spAdi)
    {
        if (returnCode == 0 && data is not null)
        {
            return ServiceResult<T>.Ok(data);
        }

        if (returnCode < 0 && returnCode >= -9)
        {
            return ServiceResult<T>.Fail(errorMessage ?? varsayilan);
        }

        _logger.LogError("{Sp} beklenmeyen sonuc. UserId={UserId} RC={RC} Hata={Error}",
            spAdi, userId, returnCode, errorMessage);

        return ServiceResult<T>.Fail("İşlem sırasında beklenmeyen bir hata oluştu.");
    }
}
