-- ============================================================================
-- PROJE: MinerInMine
-- ADIM 5: DARALT (contract) — PlayerProfiles tablosunun kaldirilmasi
--
--   sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i 05_contract_playerprofiles.sql
--
-- "GENISLET / GECIS / DARALT" DESENININ SON ADIMI
--
--   1. GENISLET : Yeni tablolar olusturuldu, veri kopyalandi   (03 numarali dosya)
--   2. GECIS    : sp_RegisterUser yeni tablolara gecirildi      (04 numarali dosya)
--   3. DARALT   : Artik kimse kullanmiyor -> kaldirilir         (BU DOSYA)
--
-- Neden tek adimda "sil ve yenisini yaz" yapmadik?
-- Cunku kod ile sema arasinda uyumsuz bir an olusurdu. Calisan bir sistemde
-- o anda gelen her istek hata alirdi. Bu desen, sistem hic durmadan sema
-- degistirmeyi mumkun kilar ve gercek projelerdeki standart yontemdir.
--
-- PlayerProfiles'taki sutunlarin yeni karsiliklari:
--   Gold         -> PlayerResources (KRISTAL satiri)
--   MiningPower  -> PlayerUpgrades uzerinden hesaplanir (CLICK_POWER)
--   LastMinedAt  -> PlayerFacilityClicks.LastClickAt (tesis bazli)
--   Level        -> PlayerFacilities.Level (tesis bazli)
-- ============================================================================

USE MinerInMineDb;
GO

SET NOCOUNT ON;

-- ============================================================================
-- GUVENLIK KONTROLU
--
-- Yikici bir islem yapmadan once, tasinmasi gereken verinin GERCEKTEN tasinmis
-- oldugunu dogruluyoruz. Kontrol basarisiz olursa script hata verip DURUR;
-- tablo silinmez.
--
-- Bu aliskanlik cok onemlidir: "muhtemelen tasinmistir" diyerek DROP TABLE
-- calistirmak, geri donusu olmayan veri kaybinin en yaygin sebebidir.
-- ============================================================================
IF OBJECT_ID('PlayerProfiles', 'U') IS NULL
BEGIN
    PRINT N'PlayerProfiles zaten kaldırılmış. Yapılacak bir şey yok.';
END
ELSE
BEGIN
    DECLARE @EksikKaynak INT, @EksikKristal INT;

    -- 1) Her kullanicinin kaynak satirlari olusmus mu?
    SELECT @EksikKaynak = COUNT(*)
    FROM Users u
    WHERE NOT EXISTS (SELECT 1 FROM PlayerResources pr WHERE pr.UserId = u.Id);

    -- 2) Eski Gold degeri Kristal'e dogru tasinmis mi?
    --    (Tasima sonrasi oyun oynanmis olabilecegi icin Kristal ARTMIS olabilir;
    --     bu yuzden "esit mi" degil "en az o kadar mi" diye bakiyoruz.)
    SELECT @EksikKristal = COUNT(*)
    FROM PlayerProfiles pp
    JOIN ResourceTypes rt ON rt.Code = N'KRISTAL'
    LEFT JOIN PlayerResources pr ON pr.UserId = pp.UserId AND pr.ResourceTypeId = rt.Id
    WHERE pr.Amount IS NULL OR pr.Amount < pp.Gold;

    IF @EksikKaynak > 0 OR @EksikKristal > 0
    BEGIN
        PRINT N'DURDURULDU: Taşıma tamamlanmamış.';
        PRINT N'  Kaynak satırı olmayan kullanıcı sayısı : ' + CAST(@EksikKaynak AS NVARCHAR);
        PRINT N'  Kristal bakiyesi eksik kullanıcı sayısı: ' + CAST(@EksikKristal AS NVARCHAR);
        PRINT N'Önce 03_game_tables.sql dosyasını çalıştırın.';

        -- RAISERROR ile hata firlatiyoruz ki script sessizce "basarili" gorunmesin.
        RAISERROR(N'Migration doğrulaması başarısız — PlayerProfiles kaldırılmadı.', 16, 1);
    END
    ELSE
    BEGIN
        DECLARE @Toplam INT = (SELECT COUNT(*) FROM PlayerProfiles);

        PRINT N'Doğrulama başarılı. ' + CAST(@Toplam AS NVARCHAR) + N' oyuncunun verisi yeni tablolarda mevcut.';

        DROP TABLE PlayerProfiles;

        PRINT N'PlayerProfiles kaldırıldı. Şema artık tek modele dayanıyor.';
    END
END
GO
