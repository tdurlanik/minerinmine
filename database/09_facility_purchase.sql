-- ============================================================================
-- PROJE: MinerInMine
-- ADIM 9: Tesis Satin Alma
--
--   sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i 09_facility_purchase.sql
--
-- NEDEN BU DOSYA VAR?
-- Oyuncular yalnizca Demir Ocagi ile basliyordu ve Altin Damari / Kimberlit
-- Bacasi'na ULASMANIN HICBIR YOLU YOKTU. Oyunun ucte ikisi erisilemez durumdaydi.
--
-- TASARIM: Tesisler sadece PARAYLA degil, ILERLEMEYLE de kapilanir.
-- "2.000 Kristal biriktir" bir hedef degildir; "Demir Ocagi'ni 10. seviyeye
-- cikar" bir hedeftir. Onun icin her tesisin bir on kosulu var.
-- ============================================================================

USE MinerInMineDb;
GO

-- ============================================================================
-- 1. FacilityTypes'a acilis kosulu sutunlari
--
-- Kosulu koda gomseydik ("if altin damari ise demir ocagi 10 olmali") yeni bir
-- tesis eklemek kod degisikligi gerektirirdi. Tabloda tutunca tek INSERT yeter.
-- ============================================================================
IF COL_LENGTH('FacilityTypes', 'UnlockFacilityTypeId') IS NULL
BEGIN
    ALTER TABLE FacilityTypes ADD UnlockFacilityTypeId INT NULL;
END
GO

IF COL_LENGTH('FacilityTypes', 'UnlockLevel') IS NULL
BEGIN
    ALTER TABLE FacilityTypes ADD UnlockLevel INT NOT NULL DEFAULT 0;
END
GO

-- Kendine referans veren yabanci anahtar: bir tesis, baska bir tesise baglidir.
IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE name = 'FK_FacilityTypes_Unlock')
BEGIN
    ALTER TABLE FacilityTypes ADD CONSTRAINT FK_FacilityTypes_Unlock
        FOREIGN KEY (UnlockFacilityTypeId) REFERENCES FacilityTypes(Id);
END
GO

-- --- Acilis zinciri: Demir -> Altin -> Kimberlit ---
UPDATE ft
SET UnlockFacilityTypeId = onceki.Id,
    UnlockLevel = 10
FROM FacilityTypes ft
JOIN FacilityTypes onceki ON onceki.Code = N'DEMIR_OCAGI'
WHERE ft.Code = N'ALTIN_DAMARI';

UPDATE ft
SET UnlockFacilityTypeId = onceki.Id,
    UnlockLevel = 10
FROM FacilityTypes ft
JOIN FacilityTypes onceki ON onceki.Code = N'ALTIN_DAMARI'
WHERE ft.Code = N'KIMBERLIT_BACASI';

-- Baslangic tesisinin on kosulu yoktur.
UPDATE FacilityTypes SET UnlockFacilityTypeId = NULL, UnlockLevel = 0
WHERE Code = N'DEMIR_OCAGI';
GO

-- ============================================================================
-- 2. Transactions.Reason listesine BUY_FACILITY ekle
--
-- Reason sutununda CHECK kisiti var ve yeni bir islem turu eklerken onu
-- guncellemek ZORUNLU. Kisit, gunluge tanimsiz bir tur yazilmasini engelliyor —
-- bu iyi bir sey, ama yeni tur eklerken hatirlanmasi gerekiyor.
-- ============================================================================
IF EXISTS (SELECT * FROM sys.check_constraints WHERE name = 'CK_Transactions_Reason')
BEGIN
    ALTER TABLE Transactions DROP CONSTRAINT CK_Transactions_Reason;
END
GO

ALTER TABLE Transactions ADD CONSTRAINT CK_Transactions_Reason CHECK (Reason IN (
    N'CLICK', N'COLLECT', N'SELL', N'FACILITY_UPGRADE', N'BUY_FACILITY',
    N'HIRE_MINER', N'BUY_UPGRADE', N'UNLOCK_CLICK', N'INSTANT_FINISH',
    N'AD_REWARD', N'ADMIN_ADJUST'
));
GO

-- ============================================================================
-- 3. sp_BuyFacility — yeni tesis satin al
--
-- Adimlar:
--   1. Zaten sahip mi?
--   2. On kosul saglaniyor mu? (onceki tesis yeterli seviyede mi)
--   3. Bedel FacilityLevels'in 1. seviye satirindan okunur (denge tablosu)
--   4. Kristal KOSULLU dusulur  -> yaris durumu korumasi
--   5. Tesis KOSULLU eklenir    -> ayni anda iki istek gelirse ikincisi eklenemez
--   6. Acik olan her kazma turu icin bekleme takip satiri olusturulur
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_BuyFacility
    @UserId INT,
    @FacilityTypeId INT,
    @ErrorMessage NVARCHAR(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ErrorMessage = NULL;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();

    IF EXISTS (SELECT 1 FROM PlayerFacilities WHERE UserId = @UserId AND FacilityTypeId = @FacilityTypeId)
    BEGIN
        SET @ErrorMessage = N'Bu tesise zaten sahipsiniz.';
        RETURN -1;
    END

    DECLARE @UnlockId INT, @UnlockLevel INT, @Ad NVARCHAR(50);
    SELECT @UnlockId = UnlockFacilityTypeId, @UnlockLevel = UnlockLevel, @Ad = Name
    FROM FacilityTypes WHERE Id = @FacilityTypeId;

    IF @Ad IS NULL
    BEGIN
        SET @ErrorMessage = N'Tesis bulunamadi.';
        RETURN -2;
    END

    -- On kosul kontrolu: gerekli tesis yeterli seviyede mi?
    IF @UnlockId IS NOT NULL
    BEGIN
        DECLARE @MevcutSeviye INT =
            ISNULL((SELECT Level FROM PlayerFacilities WHERE UserId = @UserId AND FacilityTypeId = @UnlockId), 0);

        IF @MevcutSeviye < @UnlockLevel
        BEGIN
            SET @ErrorMessage =
                (SELECT Name FROM FacilityTypes WHERE Id = @UnlockId)
                + N' seviye ' + CAST(@UnlockLevel AS NVARCHAR(10)) + N' olmali (su an '
                + CAST(@MevcutSeviye AS NVARCHAR(10)) + N').';
            RETURN -3;
        END
    END

    -- Bedel: denge tablosunun 1. seviye satiri = tesisin satin alma fiyati
    DECLARE @Cost BIGINT =
        (SELECT Cost FROM FacilityLevels WHERE FacilityTypeId = @FacilityTypeId AND Level = 1);

    IF @Cost IS NULL
    BEGIN
        SET @ErrorMessage = N'Denge tablosunda bu tesis bulunamadi.';
        RETURN -99;
    END

    DECLARE @KristalId INT = (SELECT Id FROM ResourceTypes WHERE Code = N'KRISTAL');

    BEGIN TRANSACTION;

    -- Bakiyeyi kosullu dus
    UPDATE PlayerResources
    SET Amount = Amount - @Cost, UpdatedAt = @Now
    WHERE UserId = @UserId AND ResourceTypeId = @KristalId AND Amount >= @Cost;

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK TRANSACTION;
        SET @ErrorMessage = N'Yetersiz Kristal.';
        RETURN -4;
    END

    -- Tesisi kosullu ekle: ayni anda gelen ikinci istek buraya giremez.
    INSERT INTO PlayerFacilities (UserId, FacilityTypeId, Level, LastCollectedAt, CreatedAt)
    SELECT @UserId, @FacilityTypeId, 1, @Now, @Now
    WHERE NOT EXISTS (
        SELECT 1 FROM PlayerFacilities WHERE UserId = @UserId AND FacilityTypeId = @FacilityTypeId
    );

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK TRANSACTION;   -- para da geri verilir
        SET @ErrorMessage = N'Bu tesise zaten sahipsiniz.';
        RETURN -1;
    END

    -- Acilmis her kazma turu icin bu tesiste bekleme takip satiri olustur.
    INSERT INTO PlayerFacilityClicks (UserId, FacilityTypeId, ClickTypeId)
    SELECT @UserId, @FacilityTypeId, pcu.ClickTypeId
    FROM PlayerClickUnlocks pcu
    WHERE pcu.UserId = @UserId
      AND NOT EXISTS (
          SELECT 1 FROM PlayerFacilityClicks x
          WHERE x.UserId = @UserId AND x.FacilityTypeId = @FacilityTypeId
            AND x.ClickTypeId = pcu.ClickTypeId
      );

    DECLARE @NewBalance BIGINT =
        (SELECT Amount FROM PlayerResources WHERE UserId = @UserId AND ResourceTypeId = @KristalId);

    INSERT INTO Transactions (UserId, ResourceTypeId, Amount, BalanceAfter, Reason, ReferenceId, CreatedAt)
    VALUES (@UserId, @KristalId, -@Cost, @NewBalance, N'BUY_FACILITY', @FacilityTypeId, @Now);

    COMMIT TRANSACTION;

    SELECT @Ad AS FacilityName, @Cost AS Cost, @NewBalance AS NewBalance, @Now AS ServerTime;
    RETURN 0;
END
GO

-- ============================================================================
-- 4. sp_GetPlayerState — SURUM 4
--
-- Tek degisiklik: SATIN ALINABILIR TESISLER sonuc kumesi eklendi (8. kume).
-- Sunucu, oyuncunun sahip OLMADIGI tesisleri, bedelini ve on kosulun saglanip
-- saglanmadigini doner; arayuz "Yeni Tesis" bolumunu bununla cizer.
--
-- Yine tam yeni tanimi buraya yaziyoruz (04 ve 06/07'yi duzenlemiyoruz) ki
-- goc dizisinin her ara adimi calisir kalsin.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_GetPlayerState
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Completed INT;
    EXEC sp_ApplyDueUpgrades @UserId, @Completed OUTPUT;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();
    DECLARE @PerMinute INT =
        (SELECT CAST(SettingValue AS INT) FROM GameSettings WHERE SettingKey = N'INSTANT_FINISH_PER_MINUTE');
    DECLARE @CapSeconds INT =
        (SELECT CAST(SettingValue AS INT) * 3600 FROM GameSettings WHERE SettingKey = N'OFFLINE_CAP_HOURS');

    DECLARE @MinerMult DECIMAL(10,3) = 1.0;
    SELECT @MinerMult = 1.0 + ISNULL(SUM(ut.EffectValue * pu.Level), 0)
    FROM PlayerUpgrades pu JOIN UpgradeTypes ut ON ut.Id = pu.UpgradeTypeId
    WHERE pu.UserId = @UserId AND ut.EffectType = N'MINER_SPEED';

    -- --- 1) Kaynaklar ---
    SELECT rt.Id AS ResourceTypeId, rt.Code, rt.Name, pr.Amount, rt.SellValue, rt.IsCurrency
    FROM PlayerResources pr JOIN ResourceTypes rt ON rt.Id = pr.ResourceTypeId
    WHERE pr.UserId = @UserId ORDER BY rt.DisplayOrder;

    -- --- 2) Sahip olunan tesisler ---
    SELECT
        ft.Id AS FacilityTypeId, ft.Code, ft.Name, ft.MaxLevel,
        rt.Code AS ResourceCode, rt.Name AS ResourceName,
        pf.Level,
        fl.Production AS CurrentProduction,
        nxt.Cost AS NextLevelCost,
        nxt.UpgradeMinutes AS NextLevelMinutes,
        nxt.Production AS NextLevelProduction,
        pf.UpgradeCompletesAt,
        pf.LastCollectedAt,
        CAST(ISNULL(r.BasePerSecond, 0) * @MinerMult AS DECIMAL(18,2)) AS AutoPerSecond,
        CASE WHEN pf.UpgradeCompletesAt IS NULL THEN NULL ELSE
            CASE WHEN DATEDIFF(SECOND, @Now, pf.UpgradeCompletesAt) <= 0 THEN @PerMinute
                 ELSE CAST(CEILING(DATEDIFF(SECOND, @Now, pf.UpgradeCompletesAt) / 60.0) AS BIGINT) * @PerMinute
            END
        END AS InstantFinishCost
    FROM PlayerFacilities pf
    JOIN FacilityTypes ft ON ft.Id = pf.FacilityTypeId
    JOIN ResourceTypes rt ON rt.Id = ft.ResourceTypeId
    JOIN FacilityLevels fl ON fl.FacilityTypeId = pf.FacilityTypeId AND fl.Level = pf.Level
    LEFT JOIN FacilityLevels nxt ON nxt.FacilityTypeId = pf.FacilityTypeId AND nxt.Level = pf.Level + 1
    LEFT JOIN fn_MinerRates(@UserId) r ON r.FacilityTypeId = pf.FacilityTypeId
    WHERE pf.UserId = @UserId ORDER BY ft.DisplayOrder;

    -- --- 3) Kazma turleri ---
    SELECT ct.Id AS ClickTypeId, ct.Code, ct.Name, ct.CooldownSeconds,
           ct.YieldMultiplier, ct.UnlockCost,
           CAST(CASE WHEN pcu.UserId IS NULL THEN 0 ELSE 1 END AS BIT) AS IsUnlocked
    FROM ClickTypes ct
    LEFT JOIN PlayerClickUnlocks pcu ON pcu.ClickTypeId = ct.Id AND pcu.UserId = @UserId
    ORDER BY ct.DisplayOrder;

    -- --- 4) Tesis x kazma bekleme durumlari ---
    SELECT pfc.FacilityTypeId, pfc.ClickTypeId, pfc.LastClickAt,
           CASE WHEN pfc.LastClickAt IS NULL THEN @Now
                ELSE DATEADD(SECOND, ct.CooldownSeconds, pfc.LastClickAt) END AS NextAvailableAt
    FROM PlayerFacilityClicks pfc JOIN ClickTypes ct ON ct.Id = pfc.ClickTypeId
    WHERE pfc.UserId = @UserId;

    -- --- 5) Madenciler ---
    SELECT
        ft.Id AS FacilityTypeId, mt.Id AS MinerTypeId,
        mt.Code, mt.Name, mt.HireCost, mt.MaxCount,
        ct.Code AS ClickCode, ct.Name AS ClickName,
        ISNULL(pm.Count, 0) AS Count,
        CAST(CASE WHEN pcu.UserId IS NULL THEN 0 ELSE 1 END AS BIT) AS IsAvailable,
        CAST(fl.Production * ct.YieldMultiplier / ct.CooldownSeconds AS DECIMAL(18,2)) AS PerSecondEach
    FROM PlayerFacilities pf
    JOIN FacilityTypes ft ON ft.Id = pf.FacilityTypeId
    JOIN FacilityLevels fl ON fl.FacilityTypeId = pf.FacilityTypeId AND fl.Level = pf.Level
    CROSS JOIN MinerTypes mt
    JOIN ClickTypes ct ON ct.Id = mt.ClickTypeId
    LEFT JOIN PlayerMiners pm ON pm.UserId = @UserId AND pm.FacilityTypeId = ft.Id AND pm.MinerTypeId = mt.Id
    LEFT JOIN PlayerClickUnlocks pcu ON pcu.UserId = @UserId AND pcu.ClickTypeId = mt.ClickTypeId
    WHERE pf.UserId = @UserId
    ORDER BY ft.DisplayOrder, mt.DisplayOrder;

    -- --- 6) Guclendirmeler ---
    SELECT ut.Id AS UpgradeTypeId, ut.Code, ut.Name, ut.Description,
           ut.EffectType, ut.EffectValue, ut.MaxLevel,
           ISNULL(pu.Level, 0) AS Level, nxt.Cost AS NextLevelCost
    FROM UpgradeTypes ut
    LEFT JOIN PlayerUpgrades pu ON pu.UserId = @UserId AND pu.UpgradeTypeId = ut.Id
    LEFT JOIN UpgradeLevels nxt ON nxt.UpgradeTypeId = ut.Id AND nxt.Level = ISNULL(pu.Level, 0) + 1
    ORDER BY ut.DisplayOrder;

    -- --- 7) Bekleyen uretim ---
    SELECT rt.Id AS ResourceTypeId, rt.Code, rt.Name,
        CAST(FLOOR(SUM(
            r.BasePerSecond * @MinerMult *
            CASE WHEN DATEDIFF(SECOND, pf.LastCollectedAt, @Now) > @CapSeconds THEN @CapSeconds
                 ELSE DATEDIFF(SECOND, pf.LastCollectedAt, @Now) END
        )) AS BIGINT) AS Amount
    FROM PlayerFacilities pf
    JOIN fn_MinerRates(@UserId) r ON r.FacilityTypeId = pf.FacilityTypeId
    JOIN ResourceTypes rt ON rt.Id = r.ResourceTypeId
    WHERE pf.UserId = @UserId
    GROUP BY rt.Id, rt.Code, rt.Name, rt.DisplayOrder
    HAVING SUM(r.BasePerSecond) > 0
    ORDER BY rt.DisplayOrder;

    -- --- 8) SATIN ALINABILIR TESISLER (yeni) ---
    -- Sahip olunmayan tesisler; bedeli, on kosulu ve kosulun saglanip
    -- saglanmadigi ile birlikte. Arayuz "Yeni Tesis" bolumunu bundan cizer.
    SELECT
        ft.Id AS FacilityTypeId,
        ft.Code, ft.Name,
        rt.Code AS ResourceCode, rt.Name AS ResourceName,
        fl.Cost,
        fl.Production AS StartProduction,
        gerekli.Name AS RequiredFacilityName,
        ft.UnlockLevel AS RequiredLevel,
        ISNULL(sahip.Level, 0) AS RequiredCurrentLevel,
        CAST(CASE
            WHEN ft.UnlockFacilityTypeId IS NULL THEN 1
            WHEN ISNULL(sahip.Level, 0) >= ft.UnlockLevel THEN 1
            ELSE 0
        END AS BIT) AS IsUnlocked
    FROM FacilityTypes ft
    JOIN ResourceTypes rt ON rt.Id = ft.ResourceTypeId
    JOIN FacilityLevels fl ON fl.FacilityTypeId = ft.Id AND fl.Level = 1
    LEFT JOIN FacilityTypes gerekli ON gerekli.Id = ft.UnlockFacilityTypeId
    LEFT JOIN PlayerFacilities sahip ON sahip.UserId = @UserId AND sahip.FacilityTypeId = ft.UnlockFacilityTypeId
    WHERE NOT EXISTS (
        SELECT 1 FROM PlayerFacilities pf WHERE pf.UserId = @UserId AND pf.FacilityTypeId = ft.Id
    )
    ORDER BY ft.DisplayOrder;

    -- --- 9) Sunucu saati + tamamlanan gelistirme sayisi ---
    SELECT @Now AS ServerTime, @Completed AS CompletedUpgrades;
END
GO

PRINT N'09_facility_purchase.sql tamamlandi.';
GO
