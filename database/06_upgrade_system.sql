-- ============================================================================
-- PROJE: MinerInMine
-- ADIM 6: Tesis Gelistirme Sistemi (zaman bazli mekanikler)
--
--   sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i 06_upgrade_system.sql
--
-- BU DOSYANIN ANA KONUSU: ZAMANI GUVENLI MODELLEMEK
--
-- Gelistirme 5 ile 60 dakika arasi surer. Uc soru cevaplanmali:
--   1. Sure dolduguna KIM karar verir?   -> sunucu, SYSUTCDATETIME() ile
--   2. Seviye NE ZAMAN artar?            -> ilk bakan istek uygular (tembel)
--   3. Ayni anda iki istek gelirse?      -> kosullu UPDATE + @@ROWCOUNT
--
-- TEMBEL TAMAMLAMA (lazy completion)
-- Arka planda saniyede bir calisip "suresi dolan var mi" diye bakan bir servis
-- YAZMIYORUZ. Bunun yerine oyuncu herhangi bir istek attiginda once suresi
-- dolmus gelistirmeleri uyguluyoruz. Oyuncu oyunda degilse hicbir kaynak
-- tuketilmez; girdiginde gelistirmesi coktan bitmis olur.
-- ============================================================================

USE MinerInMineDb;
GO

-- ============================================================================
-- 1. GameSettings — ayarlanabilir oyun sabitleri
--
-- "Aninda bitirme dakika basina 10 Kristal" gibi degerleri koda gomseydik,
-- dengeyi degistirmek icin yeniden derleyip dagitmak gerekirdi. Tabloda
-- tutunca tek UPDATE yeterli.
--
-- Anahtar-deger (key-value) tablosu deseni: az sayida, birbirinden bagimsiz
-- ayar icin her ayara ayri sutun acmaktan daha esnektir.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'GameSettings')
BEGIN
    CREATE TABLE GameSettings (
        SettingKey NVARCHAR(50) NOT NULL PRIMARY KEY,
        SettingValue NVARCHAR(200) NOT NULL,
        Description NVARCHAR(300) NULL
    );
END
GO

MERGE INTO GameSettings AS h
USING (VALUES
    (N'INSTANT_FINISH_PER_MINUTE', N'10',
     N'Gelistirmeyi aninda bitirmenin dakika basina Kristal bedeli')
) AS k (SettingKey, SettingValue, Description)
    ON h.SettingKey = k.SettingKey
WHEN MATCHED THEN UPDATE SET h.SettingValue = k.SettingValue, h.Description = k.Description
WHEN NOT MATCHED THEN INSERT (SettingKey, SettingValue, Description)
    VALUES (k.SettingKey, k.SettingValue, k.Description);
GO

-- ============================================================================
-- 2. sp_ApplyDueUpgrades — suresi dolmus gelistirmeleri uygula
--
-- Bu SP oyuncunun her isteginde en basta cagrilir. Tembel tamamlamanin kalbi burasi.
--
-- Tek bir UPDATE ile TUM tesisler icin calisir; dongu yok. Kosul UPDATE'in
-- WHERE'inde oldugu icin ayni anda iki istek gelse bile seviye yalnizca bir
-- kez artar (Gun 2'deki desenin aynisi).
--
-- CIKTI: Kac tesisin seviyesi arttigi. Arayuz bunu "gelistirmen tamamlandi"
-- bildirimi gostermek icin kullanabilir.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_ApplyDueUpgrades
    @UserId INT,
    @CompletedCount INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();

    UPDATE PlayerFacilities
    SET Level = Level + 1,
        UpgradeStartedAt = NULL,
        UpgradeCompletesAt = NULL
    WHERE UserId = @UserId
      AND UpgradeCompletesAt IS NOT NULL      -- devam eden bir gelistirme var
      AND UpgradeCompletesAt <= @Now;         -- ve suresi dolmus

    SET @CompletedCount = @@ROWCOUNT;
END
GO

-- ============================================================================
-- 3. sp_StartFacilityUpgrade — gelistirme baslat
--
-- Adimlar:
--   1. Once suresi dolmus gelistirmeleri uygula (tembel tamamlama)
--   2. Son seviyede mi? Zaten devam eden gelistirme var mi?
--   3. Maliyet ve sure DENGE TABLOSUNDAN okunur, hesaplanmaz
--   4. Zamanlayiciyi KOSULLU kur   -> yaris durumu korumasi
--   5. Kristal'i KOSULLU dus       -> yaris durumu korumasi
--   6. Gunluge yaz
--
-- 4 ve 5 ayni transaction icindedir: biri basarisiz olursa digeri de geri alinir.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_StartFacilityUpgrade
    @UserId INT,
    @FacilityTypeId INT,
    @ErrorMessage NVARCHAR(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ErrorMessage = NULL;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();
    DECLARE @Dummy INT;

    -- Belki gelistirme coktan bitti; once onu uygula.
    EXEC sp_ApplyDueUpgrades @UserId, @Dummy OUTPUT;

    DECLARE @Level INT, @MaxLevel INT, @InProgress DATETIME2;

    SELECT @Level = pf.Level,
           @MaxLevel = ft.MaxLevel,
           @InProgress = pf.UpgradeCompletesAt
    FROM PlayerFacilities pf
    JOIN FacilityTypes ft ON ft.Id = pf.FacilityTypeId
    WHERE pf.UserId = @UserId AND pf.FacilityTypeId = @FacilityTypeId;

    IF @Level IS NULL
    BEGIN
        SET @ErrorMessage = N'Bu tesise sahip degilsiniz.';
        RETURN -1;
    END

    IF @Level >= @MaxLevel
    BEGIN
        SET @ErrorMessage = N'Bu tesis son seviyede.';
        RETURN -2;
    END

    IF @InProgress IS NOT NULL
    BEGIN
        SET @ErrorMessage = N'Bu tesiste zaten devam eden bir gelistirme var.';
        RETURN -3;
    END

    -- Hedef seviyenin maliyeti ve suresi denge tablosundan. POWER() YOK.
    DECLARE @Cost BIGINT, @Minutes INT;

    SELECT @Cost = Cost, @Minutes = UpgradeMinutes
    FROM FacilityLevels
    WHERE FacilityTypeId = @FacilityTypeId AND Level = @Level + 1;

    IF @Cost IS NULL
    BEGIN
        SET @ErrorMessage = N'Denge tablosunda hedef seviye bulunamadi.';
        RETURN -99;
    END

    DECLARE @KristalId INT = (SELECT Id FROM ResourceTypes WHERE Code = N'KRISTAL');

    BEGIN TRANSACTION;

    -- Zamanlayiciyi kur (kosullu).
    -- "UpgradeCompletesAt IS NULL" ayni anda gelen ikinci istegin ikinci bir
    -- gelistirme baslatmasini engeller. "Level = @Level" ise arada seviye
    -- degistiyse islemi iptal eder.
    UPDATE PlayerFacilities
    SET UpgradeStartedAt = @Now,
        UpgradeCompletesAt = DATEADD(MINUTE, @Minutes, @Now)
    WHERE UserId = @UserId
      AND FacilityTypeId = @FacilityTypeId
      AND UpgradeCompletesAt IS NULL
      AND Level = @Level;

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK TRANSACTION;
        SET @ErrorMessage = N'Gelistirme baslatilamadi, tesis durumu degismis.';
        RETURN -3;
    END

    -- Bakiyeyi dus (kosullu). Kontrol WHERE'in icinde: "once kontrol et sonra
    -- dus" deseydik ayni anda gelen iki istek ayni parayi iki kez harcayabilirdi.
    UPDATE PlayerResources
    SET Amount = Amount - @Cost,
        UpdatedAt = @Now
    WHERE UserId = @UserId
      AND ResourceTypeId = @KristalId
      AND Amount >= @Cost;

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK TRANSACTION;   -- zamanlayici da geri alinir
        SET @ErrorMessage = N'Yetersiz Kristal.';
        RETURN -4;
    END

    DECLARE @NewBalance BIGINT =
        (SELECT Amount FROM PlayerResources WHERE UserId = @UserId AND ResourceTypeId = @KristalId);

    INSERT INTO Transactions (UserId, ResourceTypeId, Amount, BalanceAfter, Reason, ReferenceId, CreatedAt)
    VALUES (@UserId, @KristalId, -@Cost, @NewBalance, N'FACILITY_UPGRADE', @FacilityTypeId, @Now);

    COMMIT TRANSACTION;

    SELECT
        @Level + 1                        AS TargetLevel,
        @Cost                             AS Cost,
        @NewBalance                       AS NewBalance,
        @Minutes                          AS DurationMinutes,
        DATEADD(MINUTE, @Minutes, @Now)   AS UpgradeCompletesAt,
        @Now                              AS ServerTime;

    RETURN 0;
END
GO

-- ============================================================================
-- 4. sp_FinishUpgradeNow — parayla aninda bitirme
--
-- Bedel KALAN SUREYE gore hesaplanir:
--     bedel = YUKARI_YUVARLA(kalanSaniye / 60) x dakikaBasinaKristal
--
-- Neden kalan sureye gore? Sabit fiyat olsaydi son bir dakikasi kalan bir
-- gelistirmeyi bitirmek, yeni baslamis birini bitirmekle ayni fiyat olurdu.
--
-- Neden YUKARI yuvarliyoruz? Asagi yuvarlansaydi son 59 saniye BEDAVA
-- bitirilebilirdi; kucuk gorunen bu detay somurulebilir bir acik olurdu.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_FinishUpgradeNow
    @UserId INT,
    @FacilityTypeId INT,
    @ErrorMessage NVARCHAR(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ErrorMessage = NULL;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();
    DECLARE @Dummy INT;

    -- Sure zaten dolmus olabilir; once onu uygula ki bosuna para almayalim.
    EXEC sp_ApplyDueUpgrades @UserId, @Dummy OUTPUT;

    DECLARE @CompletesAt DATETIME2, @Level INT;

    SELECT @CompletesAt = UpgradeCompletesAt, @Level = Level
    FROM PlayerFacilities
    WHERE UserId = @UserId AND FacilityTypeId = @FacilityTypeId;

    IF @Level IS NULL
    BEGIN
        SET @ErrorMessage = N'Bu tesise sahip degilsiniz.';
        RETURN -1;
    END

    IF @CompletesAt IS NULL
    BEGIN
        -- sp_ApplyDueUpgrades zaten tamamladiysa buraya duseriz.
        SET @ErrorMessage = N'Devam eden bir gelistirme yok.';
        RETURN -2;
    END

    DECLARE @RemainingSeconds INT = DATEDIFF(SECOND, @Now, @CompletesAt);
    IF @RemainingSeconds < 0 SET @RemainingSeconds = 0;

    DECLARE @PerMinute INT =
        (SELECT CAST(SettingValue AS INT) FROM GameSettings WHERE SettingKey = N'INSTANT_FINISH_PER_MINUTE');

    DECLARE @Cost BIGINT = CAST(CEILING(@RemainingSeconds / 60.0) AS BIGINT) * @PerMinute;
    IF @Cost < @PerMinute SET @Cost = @PerMinute;   -- en az bir dakika ucreti

    DECLARE @KristalId INT = (SELECT Id FROM ResourceTypes WHERE Code = N'KRISTAL');

    BEGIN TRANSACTION;

    UPDATE PlayerResources
    SET Amount = Amount - @Cost, UpdatedAt = @Now
    WHERE UserId = @UserId AND ResourceTypeId = @KristalId AND Amount >= @Cost;

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK TRANSACTION;
        SET @ErrorMessage = N'Yetersiz Kristal. Gerekli: ' + CAST(@Cost AS NVARCHAR(20));
        RETURN -4;
    END

    -- Gelistirmeyi kosullu tamamla: hala AYNI gelistirme devam ediyorsa.
    -- Arada baska bir istek tamamladiysa @@ROWCOUNT sifir doner ve para geri verilir.
    UPDATE PlayerFacilities
    SET Level = Level + 1,
        UpgradeStartedAt = NULL,
        UpgradeCompletesAt = NULL
    WHERE UserId = @UserId
      AND FacilityTypeId = @FacilityTypeId
      AND UpgradeCompletesAt = @CompletesAt;

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK TRANSACTION;
        SET @ErrorMessage = N'Gelistirme durumu degismis, islem iptal edildi.';
        RETURN -3;
    END

    DECLARE @NewBalance BIGINT =
        (SELECT Amount FROM PlayerResources WHERE UserId = @UserId AND ResourceTypeId = @KristalId);

    INSERT INTO Transactions (UserId, ResourceTypeId, Amount, BalanceAfter, Reason, ReferenceId, CreatedAt)
    VALUES (@UserId, @KristalId, -@Cost, @NewBalance, N'INSTANT_FINISH', @FacilityTypeId, @Now);

    COMMIT TRANSACTION;

    SELECT
        @Level + 1          AS NewLevel,
        @Cost               AS Cost,
        @NewBalance         AS NewBalance,
        @RemainingSeconds   AS SkippedSeconds,
        @Now                AS ServerTime;

    RETURN 0;
END
GO

PRINT N'06_upgrade_system.sql tamamlandi.';
GO

-- ============================================================================
-- 5. sp_GetPlayerState — SURUM 2 (gelistirme farkinda)
--
-- NEDEN BURADA YENIDEN TANIMLIYORUZ?
-- Bu SP 04 numarali dosyada tanimlanmisti. Degistirmek icin oradaki tanimi
-- duzenlemek yerine, BU dosyaya tam yeni surumunu yaziyoruz.
--
-- Sebep: script'ler bir goc (migration) dizisidir ve dizinin HER ARA ADIMI
-- calisir durumda olmalidir. 04'u duzenleyip sp_ApplyDueUpgrades cagirsaydik,
-- yalnizca 01-04 arasi calistirilan bir veritabaninda henuz var olmayan bir
-- prosedur cagrilmis olurdu. Her goc dosyasi degistirdigi nesnenin TAM yeni
-- halini tasir — gercek projelerde de boyle yapilir.
--
-- IKI DEGISIKLIK:
--   1. En basta sp_ApplyDueUpgrades cagriliyor (tembel tamamlama)
--   2. Tesis sonucuna InstantFinishCost eklendi (aninda bitirme bedeli)
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_GetPlayerState
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;

    -- TEMBEL TAMAMLAMA: Oyuncu ekrani her actiginda once suresi dolmus
    -- gelistirmeler uygulanir. Arka planda calisan bir servise gerek kalmaz.
    DECLARE @Completed INT;
    EXEC sp_ApplyDueUpgrades @UserId, @Completed OUTPUT;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();
    DECLARE @PerMinute INT =
        (SELECT CAST(SettingValue AS INT) FROM GameSettings WHERE SettingKey = N'INSTANT_FINISH_PER_MINUTE');

    -- --- 1) Kaynaklar ---
    SELECT
        rt.Id AS ResourceTypeId, rt.Code, rt.Name,
        pr.Amount, rt.SellValue, rt.IsCurrency
    FROM PlayerResources pr
    JOIN ResourceTypes rt ON rt.Id = pr.ResourceTypeId
    WHERE pr.UserId = @UserId
    ORDER BY rt.DisplayOrder;

    -- --- 2) Tesisler ---
    -- InstantFinishCost, aninda bitirmenin O ANKI bedelidir. Sure azaldikca
    -- duser, bu yuzden her istekte yeniden hesaplanir. Gelistirme yoksa NULL.
    SELECT
        ft.Id AS FacilityTypeId,
        ft.Code, ft.Name, ft.MaxLevel,
        rt.Code AS ResourceCode,
        rt.Name AS ResourceName,
        pf.Level,
        fl.Production        AS CurrentProduction,
        nxt.Cost             AS NextLevelCost,
        nxt.UpgradeMinutes   AS NextLevelMinutes,
        nxt.Production       AS NextLevelProduction,
        pf.UpgradeCompletesAt,
        pf.LastCollectedAt,
        CASE
            WHEN pf.UpgradeCompletesAt IS NULL THEN NULL
            ELSE
                CASE
                    WHEN CAST(CEILING(
                             CASE WHEN DATEDIFF(SECOND, @Now, pf.UpgradeCompletesAt) < 0
                                  THEN 0
                                  ELSE DATEDIFF(SECOND, @Now, pf.UpgradeCompletesAt)
                             END / 60.0) AS BIGINT) * @PerMinute < @PerMinute
                    THEN @PerMinute
                    ELSE CAST(CEILING(
                             CASE WHEN DATEDIFF(SECOND, @Now, pf.UpgradeCompletesAt) < 0
                                  THEN 0
                                  ELSE DATEDIFF(SECOND, @Now, pf.UpgradeCompletesAt)
                             END / 60.0) AS BIGINT) * @PerMinute
                END
        END AS InstantFinishCost
    FROM PlayerFacilities pf
    JOIN FacilityTypes ft ON ft.Id = pf.FacilityTypeId
    JOIN ResourceTypes rt ON rt.Id = ft.ResourceTypeId
    JOIN FacilityLevels fl ON fl.FacilityTypeId = pf.FacilityTypeId AND fl.Level = pf.Level
    LEFT JOIN FacilityLevels nxt ON nxt.FacilityTypeId = pf.FacilityTypeId AND nxt.Level = pf.Level + 1
    WHERE pf.UserId = @UserId
    ORDER BY ft.DisplayOrder;

    -- --- 3) Kazma turleri ---
    SELECT
        ct.Id AS ClickTypeId, ct.Code, ct.Name,
        ct.CooldownSeconds, ct.YieldMultiplier, ct.UnlockCost,
        CAST(CASE WHEN pcu.UserId IS NULL THEN 0 ELSE 1 END AS BIT) AS IsUnlocked
    FROM ClickTypes ct
    LEFT JOIN PlayerClickUnlocks pcu ON pcu.ClickTypeId = ct.Id AND pcu.UserId = @UserId
    ORDER BY ct.DisplayOrder;

    -- --- 4) Tesis x kazma bekleme durumlari ---
    SELECT
        pfc.FacilityTypeId, pfc.ClickTypeId, pfc.LastClickAt,
        CASE WHEN pfc.LastClickAt IS NULL THEN @Now
             ELSE DATEADD(SECOND, ct.CooldownSeconds, pfc.LastClickAt)
        END AS NextAvailableAt
    FROM PlayerFacilityClicks pfc
    JOIN ClickTypes ct ON ct.Id = pfc.ClickTypeId
    WHERE pfc.UserId = @UserId;

    -- --- 5) Sunucu saati + bu istekte tamamlanan gelistirme sayisi ---
    SELECT @Now AS ServerTime, @Completed AS CompletedUpgrades;
END
GO
