-- ============================================================================
-- PROJE: MinerInMine
-- ADIM 7: Madenci Otomasyonu, Offline Kazanc, Satis ve Guclendirmeler
--
--   sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i 07_automation_economy.sql
--
-- BU DOSYANIN ANA KONUSU: BIRIKMIS URETIMI GUVENLI TOPLAMAK
--
-- Madenciler oyuncu yokken de calisir. Ama arka planda saniyede bir calisan
-- bir servis YOK. Uretim su formulle, TOPLAMA ANINDA hesaplanir:
--
--     birikmis = uretimHizi x (simdi - LastCollectedAt)
--
-- Bu yaklasim offline kazanci bedavaya getirir: oyuncu 8 saat sonra girdiginde
-- fark zaten 8 saat cikar, ekstra kod gerekmez.
--
-- YENI TEHLIKE: Toplama islemi "oku - hesapla - yaz" adimlarindan olusur.
-- Ayni anda iki istek gelirse ikisi de ayni sureyi okur ve uretim IKI KEZ
-- eklenir. Cozum yine kosullu yazma, ama bu kez COK SATIR icin:
-- UPDATE ... OUTPUT deleted.* ile eski degeri ATOMIK olarak yakaliyoruz.
-- ============================================================================

USE MinerInMineDb;
GO

-- ============================================================================
-- 1. Offline kazanc tavani
--
-- Oyuncu bir ay girmezse bir aylik uretim biriksin mi? Hayir: hem ekonomiyi
-- bozar hem de geri donmeyi anlamsizlastirir (zaten her sey birikmis olur).
-- Sektor standardi birkac saatlik bir tavandir.
-- ============================================================================
MERGE INTO GameSettings AS h
USING (VALUES
    (N'OFFLINE_CAP_HOURS', N'8',
     N'Madencilerin oyuncu yokken en fazla kac saatlik uretim biriktirebilecegi')
) AS k (SettingKey, SettingValue, Description)
    ON h.SettingKey = k.SettingKey
WHEN MATCHED THEN UPDATE SET h.SettingValue = k.SettingValue, h.Description = k.Description
WHEN NOT MATCHED THEN INSERT (SettingKey, SettingValue, Description)
    VALUES (k.SettingKey, k.SettingValue, k.Description);
GO

-- ============================================================================
-- 2. UpgradeLevels — guclendirmeler icin denge tablosu
--
-- FacilityLevels ile AYNI gerekcey: maliyet calisma aninda POWER() ile
-- hesaplanirsa SQL, C# ve JavaScript farkli sonuc verebilir. Sonlu sayida
-- seviye oldugu icin bir kez hesaplayip tam sayi olarak sakliyoruz.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'UpgradeLevels')
BEGIN
    CREATE TABLE UpgradeLevels (
        UpgradeTypeId INT NOT NULL,
        Level INT NOT NULL,
        Cost BIGINT NOT NULL,

        CONSTRAINT PK_UpgradeLevels PRIMARY KEY (UpgradeTypeId, Level),
        CONSTRAINT FK_UpgradeLevels_UpgradeTypes
            FOREIGN KEY (UpgradeTypeId) REFERENCES UpgradeTypes(Id) ON DELETE CASCADE,
        CONSTRAINT CK_UpgradeLevels_Level CHECK (Level >= 1),
        CONSTRAINT CK_UpgradeLevels_Cost CHECK (Cost > 0)
    );
END
GO

WITH Seviyeler AS (
    SELECT 1 AS Level
    UNION ALL
    SELECT Level + 1 FROM Seviyeler WHERE Level < 100
)
MERGE INTO UpgradeLevels AS h
USING (
    SELECT ut.Id AS UpgradeTypeId, s.Level,
           CAST(FLOOR(ut.BaseCost * POWER(CAST(ut.CostMultiplier AS FLOAT), s.Level - 1)) AS BIGINT) AS Cost
    FROM UpgradeTypes ut
    JOIN Seviyeler s ON s.Level <= ut.MaxLevel
) AS k
    ON h.UpgradeTypeId = k.UpgradeTypeId AND h.Level = k.Level
WHEN MATCHED THEN UPDATE SET h.Cost = k.Cost
WHEN NOT MATCHED BY TARGET THEN
    INSERT (UpgradeTypeId, Level, Cost) VALUES (k.UpgradeTypeId, k.Level, k.Cost)
WHEN NOT MATCHED BY SOURCE THEN DELETE
OPTION (MAXRECURSION 200);
GO

-- ============================================================================
-- 3. fn_MinerRates — oyuncunun tesis basina saniyelik uretimi
--
-- Her madenci kademesi bir kazma turunu otomatiklestirir, yani:
--     saniyelikUretim = tesisUretimi x kazmaVerimi / beklemeSuresi x madenciSayisi
--
-- Ornek: Sef Madenci (30 sn, x90) 3. seviye Demir Ocagi'nda
--     3 x 90 / 30 = saniyede 9 demir
--
-- NEDEN INLINE TABLE-VALUED FUNCTION (iTVF)?
-- Skaler fonksiyonlar (RETURNS INT) SQL Server'da satir satir calisir ve
-- yavastir. "RETURNS TABLE ... AS RETURN (tek SELECT)" bicimindeki iTVF ise
-- sorgunun icine gomulur (inline edilir); optimizer onu normal bir JOIN gibi
-- ele alir. Ayni hesabi hem okuma hem toplama SP'sinde kullanacagimiz icin
-- tek yerde tanimlamak, iki yerin ayrisma riskini de ortadan kaldirir.
-- ============================================================================
CREATE OR ALTER FUNCTION fn_MinerRates(@UserId INT)
RETURNS TABLE
AS RETURN
(
    SELECT
        pm.FacilityTypeId,
        ft.ResourceTypeId,
        SUM(
            CAST(fl.Production AS DECIMAL(18,6))
            * ct.YieldMultiplier
            / ct.CooldownSeconds
            * pm.Count
        ) AS BasePerSecond
    FROM PlayerMiners pm
    JOIN PlayerFacilities pf ON pf.UserId = pm.UserId AND pf.FacilityTypeId = pm.FacilityTypeId
    JOIN FacilityTypes ft ON ft.Id = pm.FacilityTypeId
    JOIN FacilityLevels fl ON fl.FacilityTypeId = pm.FacilityTypeId AND fl.Level = pf.Level
    JOIN MinerTypes mt ON mt.Id = pm.MinerTypeId
    JOIN ClickTypes ct ON ct.Id = mt.ClickTypeId
    WHERE pm.UserId = @UserId AND pm.Count > 0
    GROUP BY pm.FacilityTypeId, ft.ResourceTypeId
);
GO

-- ============================================================================
-- 4. Madenci sayisi ustunu MinerTypes'a ekle
-- Ise alma bedeli sabit; ilerleme tesis seviyesinden geliyor. Sinirsiz madenci
-- alinabilseydi gec oyunda uretim kontrolsuz buyurdu.
-- ============================================================================
IF COL_LENGTH('MinerTypes', 'MaxCount') IS NULL
BEGIN
    ALTER TABLE MinerTypes ADD MaxCount INT NOT NULL DEFAULT 25;
END
GO

-- ============================================================================
-- 5. sp_CollectProduction — birikmis uretimi topla
--
-- BU DOSYANIN EN ONEMLI KISMI.
--
-- Naif cozum soyle olurdu:
--     1. LastCollectedAt oku
--     2. gecen sureyi hesapla, kaynagi ekle
--     3. LastCollectedAt = simdi yaz
-- Ayni anda iki istek gelirse ikisi de AYNI eski zamani okur ve uretim
-- iki kez eklenir. Klasik yaris durumu.
--
-- COZUM: UPDATE ... OUTPUT deleted.*
-- UPDATE atomiktir; OUTPUT ise guncellemeden ONCEKI degeri (deleted) ayni
-- islem icinde bize verir. Yani "eski zamani al ve ayni anda yenisini yaz"
-- tek adimda olur. Ikinci istek geldiginde LastCollectedAt zaten @Now
-- oldugu icin WHERE kosulunu gecemez ve hicbir sey toplayamaz.
--
-- Gun 2-3'te tek satir icin kullandigimiz kosullu yazma desenini, burada
-- COK SATIR icin uyguluyoruz.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_CollectProduction
    @UserId INT,
    @ErrorMessage NVARCHAR(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ErrorMessage = NULL;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();
    DECLARE @Dummy INT;

    -- Once suresi dolmus gelistirmeler uygulansin: uretim YENI seviyeden hesaplansin.
    EXEC sp_ApplyDueUpgrades @UserId, @Dummy OUTPUT;

    DECLARE @CapSeconds INT =
        (SELECT CAST(SettingValue AS INT) * 3600 FROM GameSettings WHERE SettingKey = N'OFFLINE_CAP_HOURS');

    -- MINER_SPEED guclendirmelerinin toplam carpani
    DECLARE @Mult DECIMAL(10,3) = 1.0;
    SELECT @Mult = 1.0 + ISNULL(SUM(ut.EffectValue * pu.Level), 0)
    FROM PlayerUpgrades pu
    JOIN UpgradeTypes ut ON ut.Id = pu.UpgradeTypeId
    WHERE pu.UserId = @UserId AND ut.EffectType = N'MINER_SPEED';

    DECLARE @Toplanan TABLE (FacilityTypeId INT PRIMARY KEY, Saniye INT);
    DECLARE @Kazanc TABLE (ResourceTypeId INT PRIMARY KEY, Miktar BIGINT);

    BEGIN TRANSACTION;

    -- ATOMIK ADIM: eski zamani yakala ve ayni anda yenisini yaz.
    UPDATE pf
    SET LastCollectedAt = @Now
    OUTPUT
        inserted.FacilityTypeId,
        CASE
            WHEN DATEDIFF(SECOND, deleted.LastCollectedAt, @Now) > @CapSeconds THEN @CapSeconds
            ELSE DATEDIFF(SECOND, deleted.LastCollectedAt, @Now)
        END
    INTO @Toplanan (FacilityTypeId, Saniye)
    FROM PlayerFacilities pf
    WHERE pf.UserId = @UserId
      AND pf.LastCollectedAt < @Now;

    -- Hangi kaynaktan ne kadar biriktigini hesapla
    INSERT INTO @Kazanc (ResourceTypeId, Miktar)
    SELECT r.ResourceTypeId,
           CAST(FLOOR(SUM(r.BasePerSecond * @Mult * t.Saniye)) AS BIGINT)
    FROM @Toplanan t
    JOIN fn_MinerRates(@UserId) r ON r.FacilityTypeId = t.FacilityTypeId
    GROUP BY r.ResourceTypeId;

    DELETE FROM @Kazanc WHERE Miktar <= 0;   -- sifir kazanci gunluge yazmayalim

    UPDATE pr
    SET Amount = pr.Amount + k.Miktar,
        UpdatedAt = @Now
    FROM PlayerResources pr
    JOIN @Kazanc k ON k.ResourceTypeId = pr.ResourceTypeId
    WHERE pr.UserId = @UserId;

    INSERT INTO Transactions (UserId, ResourceTypeId, Amount, BalanceAfter, Reason, ReferenceId, CreatedAt)
    SELECT @UserId, k.ResourceTypeId, k.Miktar, pr.Amount, N'COLLECT', NULL, @Now
    FROM @Kazanc k
    JOIN PlayerResources pr ON pr.UserId = @UserId AND pr.ResourceTypeId = k.ResourceTypeId;

    COMMIT TRANSACTION;

    -- Toplanan kaynaklarin dokumu
    SELECT rt.Code, rt.Name, k.Miktar AS Amount, pr.Amount AS NewBalance
    FROM @Kazanc k
    JOIN ResourceTypes rt ON rt.Id = k.ResourceTypeId
    JOIN PlayerResources pr ON pr.UserId = @UserId AND pr.ResourceTypeId = k.ResourceTypeId
    ORDER BY rt.DisplayOrder;

    RETURN 0;
END
GO

-- ============================================================================
-- 6. sp_HireMiner — madenci ise al
--
-- TASARIM TUTARLILIGI: Her madenci kademesi bir kazma turunu otomatiklestirir.
-- Bu yuzden henuz ACMADIGIN bir kazmanin madencisini ise alamazsin —
-- ogrenmedigin bir teknigi otomatiklestiremezsin.
--
-- ONEMLI: Ise almadan once birikmis uretimin toplanmasi gerekir; aksi halde yeni
-- madenci, gecmiste calismamis oldugu sure icin de uretmis gibi sayilir.
-- Bu toplamayi SP ICINDEN cagirmiyoruz: cagirsaydik SP birden fazla sonuc kumesi
-- dondurur, erken RETURN durumlarinda ise hic kume dondurmezdi ve istemci
-- tarafinda okuma karisirdi. Sirayi SERVIS KATMANI yonetiyor (once topla, sonra al).
-- Her SP tek bir is yapar ve tek bir sonuc kumesi dondurur.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_HireMiner
    @UserId INT,
    @FacilityTypeId INT,
    @MinerTypeId INT,
    @ErrorMessage NVARCHAR(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ErrorMessage = NULL;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();

    IF NOT EXISTS (SELECT 1 FROM PlayerFacilities WHERE UserId = @UserId AND FacilityTypeId = @FacilityTypeId)
    BEGIN
        SET @ErrorMessage = N'Bu tesise sahip degilsiniz.';
        RETURN -1;
    END

    DECLARE @ClickTypeId INT, @HireCost BIGINT, @MaxCount INT;
    SELECT @ClickTypeId = ClickTypeId, @HireCost = HireCost, @MaxCount = MaxCount
    FROM MinerTypes WHERE Id = @MinerTypeId;

    IF @HireCost IS NULL
    BEGIN
        SET @ErrorMessage = N'Madenci turu bulunamadi.';
        RETURN -2;
    END

    IF NOT EXISTS (SELECT 1 FROM PlayerClickUnlocks WHERE UserId = @UserId AND ClickTypeId = @ClickTypeId)
    BEGIN
        SET @ErrorMessage = N'Bu madencinin kullandigi kazma turu henuz acilmamis.';
        RETURN -3;
    END

    DECLARE @KristalId INT = (SELECT Id FROM ResourceTypes WHERE Code = N'KRISTAL');

    BEGIN TRANSACTION;

    -- Satir yoksa olustur (ilk madenci)
    IF NOT EXISTS (SELECT 1 FROM PlayerMiners
                   WHERE UserId = @UserId AND FacilityTypeId = @FacilityTypeId AND MinerTypeId = @MinerTypeId)
    BEGIN
        INSERT INTO PlayerMiners (UserId, FacilityTypeId, MinerTypeId, Count)
        VALUES (@UserId, @FacilityTypeId, @MinerTypeId, 0);
    END

    -- Sayiyi KOSULLU artir: ust sinira ulasildiysa satir guncellenmez.
    UPDATE PlayerMiners
    SET Count = Count + 1, UpdatedAt = @Now
    WHERE UserId = @UserId
      AND FacilityTypeId = @FacilityTypeId
      AND MinerTypeId = @MinerTypeId
      AND Count < @MaxCount;

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK TRANSACTION;
        SET @ErrorMessage = N'Bu tesiste bu madenci kademesi icin ust sinira ulastiniz.';
        RETURN -4;
    END

    -- Bedeli KOSULLU dus
    UPDATE PlayerResources
    SET Amount = Amount - @HireCost, UpdatedAt = @Now
    WHERE UserId = @UserId AND ResourceTypeId = @KristalId AND Amount >= @HireCost;

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK TRANSACTION;   -- madenci artisi da geri alinir
        SET @ErrorMessage = N'Yetersiz Kristal.';
        RETURN -5;
    END

    DECLARE @NewBalance BIGINT =
        (SELECT Amount FROM PlayerResources WHERE UserId = @UserId AND ResourceTypeId = @KristalId);

    INSERT INTO Transactions (UserId, ResourceTypeId, Amount, BalanceAfter, Reason, ReferenceId, CreatedAt)
    VALUES (@UserId, @KristalId, -@HireCost, @NewBalance, N'HIRE_MINER', @FacilityTypeId, @Now);

    COMMIT TRANSACTION;

    SELECT
        (SELECT Count FROM PlayerMiners
         WHERE UserId = @UserId AND FacilityTypeId = @FacilityTypeId AND MinerTypeId = @MinerTypeId) AS NewCount,
        @HireCost   AS Cost,
        @NewBalance AS NewBalance,
        @Now        AS ServerTime;

    RETURN 0;
END
GO

-- ============================================================================
-- 7. sp_SellResource — maden sat, Kristal kazan
--
-- gelir = miktar x birimDeger x (1 + SELL_BONUS carpani)
--
-- Miktar istemciden gelir ama DOGRULANIR: pozitif olmali ve oyuncunun
-- bakiyesi yetmeli. Bakiye kontrolu yine UPDATE'in WHERE'inde.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_SellResource
    @UserId INT,
    @ResourceTypeId INT,
    @Amount BIGINT,
    @ErrorMessage NVARCHAR(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ErrorMessage = NULL;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();

    IF @Amount IS NULL OR @Amount <= 0
    BEGIN
        SET @ErrorMessage = N'Satis miktari sifirdan buyuk olmali.';
        RETURN -1;
    END

    DECLARE @SellValue INT, @IsCurrency BIT;
    SELECT @SellValue = SellValue, @IsCurrency = IsCurrency
    FROM ResourceTypes WHERE Id = @ResourceTypeId;

    IF @SellValue IS NULL
    BEGIN
        SET @ErrorMessage = N'Kaynak turu bulunamadi.';
        RETURN -2;
    END

    IF @IsCurrency = 1 OR @SellValue <= 0
    BEGIN
        SET @ErrorMessage = N'Bu kaynak satilamaz.';
        RETURN -3;
    END

    DECLARE @Bonus DECIMAL(10,3) = 1.0;
    SELECT @Bonus = 1.0 + ISNULL(SUM(ut.EffectValue * pu.Level), 0)
    FROM PlayerUpgrades pu
    JOIN UpgradeTypes ut ON ut.Id = pu.UpgradeTypeId
    WHERE pu.UserId = @UserId AND ut.EffectType = N'SELL_BONUS';

    DECLARE @Gelir BIGINT = CAST(FLOOR(@Amount * @SellValue * @Bonus) AS BIGINT);
    DECLARE @KristalId INT = (SELECT Id FROM ResourceTypes WHERE Code = N'KRISTAL');

    BEGIN TRANSACTION;

    -- Madeni KOSULLU dus
    UPDATE PlayerResources
    SET Amount = Amount - @Amount, UpdatedAt = @Now
    WHERE UserId = @UserId AND ResourceTypeId = @ResourceTypeId AND Amount >= @Amount;

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK TRANSACTION;
        SET @ErrorMessage = N'Yetersiz kaynak.';
        RETURN -4;
    END

    UPDATE PlayerResources
    SET Amount = Amount + @Gelir, UpdatedAt = @Now
    WHERE UserId = @UserId AND ResourceTypeId = @KristalId;

    DECLARE @KristalBakiye BIGINT =
        (SELECT Amount FROM PlayerResources WHERE UserId = @UserId AND ResourceTypeId = @KristalId);
    DECLARE @MadenBakiye BIGINT =
        (SELECT Amount FROM PlayerResources WHERE UserId = @UserId AND ResourceTypeId = @ResourceTypeId);

    -- Satis iki satir uretir: giden maden ve gelen Kristal.
    INSERT INTO Transactions (UserId, ResourceTypeId, Amount, BalanceAfter, Reason, ReferenceId, CreatedAt)
    VALUES (@UserId, @ResourceTypeId, -@Amount, @MadenBakiye, N'SELL', NULL, @Now),
           (@UserId, @KristalId, @Gelir, @KristalBakiye, N'SELL', @ResourceTypeId, @Now);

    COMMIT TRANSACTION;

    SELECT @Amount AS SoldAmount, @Gelir AS Earned,
           @KristalBakiye AS KristalBalance, @MadenBakiye AS ResourceBalance, @Now AS ServerTime;

    RETURN 0;
END
GO

-- ============================================================================
-- 8. sp_BuyUpgrade — kalici guclendirme satin al
-- Maliyet UpgradeLevels denge tablosundan okunur, hesaplanmaz.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_BuyUpgrade
    @UserId INT,
    @UpgradeTypeId INT,
    @ErrorMessage NVARCHAR(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ErrorMessage = NULL;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();

    -- NOT: MINER_SPEED guclendirmesi uretim hizini degistirdigi icin, bu SP
    -- cagrilmadan ONCE birikmis uretimin toplanmis olmasi gerekir. Bu sirayi
    -- servis katmani saglar; SP icinden cagirmiyoruz ki tek sonuc kumesi kalsin.
    DECLARE @MaxLevel INT = (SELECT MaxLevel FROM UpgradeTypes WHERE Id = @UpgradeTypeId);
    IF @MaxLevel IS NULL
    BEGIN
        SET @ErrorMessage = N'Guclendirme bulunamadi.';
        RETURN -1;
    END

    DECLARE @Current INT =
        ISNULL((SELECT Level FROM PlayerUpgrades WHERE UserId = @UserId AND UpgradeTypeId = @UpgradeTypeId), 0);

    IF @Current >= @MaxLevel
    BEGIN
        SET @ErrorMessage = N'Bu guclendirme son seviyede.';
        RETURN -2;
    END

    DECLARE @Cost BIGINT =
        (SELECT Cost FROM UpgradeLevels WHERE UpgradeTypeId = @UpgradeTypeId AND Level = @Current + 1);

    DECLARE @KristalId INT = (SELECT Id FROM ResourceTypes WHERE Code = N'KRISTAL');

    BEGIN TRANSACTION;

    UPDATE PlayerResources
    SET Amount = Amount - @Cost, UpdatedAt = @Now
    WHERE UserId = @UserId AND ResourceTypeId = @KristalId AND Amount >= @Cost;

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK TRANSACTION;
        SET @ErrorMessage = N'Yetersiz Kristal.';
        RETURN -3;
    END

    -- Seviyeyi KOSULLU artir: arada baska bir istek artirdiysa bu islem iptal olur.
    IF @Current = 0
        INSERT INTO PlayerUpgrades (UserId, UpgradeTypeId, Level) VALUES (@UserId, @UpgradeTypeId, 1);
    ELSE
    BEGIN
        UPDATE PlayerUpgrades SET Level = Level + 1, UpdatedAt = @Now
        WHERE UserId = @UserId AND UpgradeTypeId = @UpgradeTypeId AND Level = @Current;

        IF @@ROWCOUNT = 0
        BEGIN
            ROLLBACK TRANSACTION;
            SET @ErrorMessage = N'Guclendirme durumu degismis, islem iptal edildi.';
            RETURN -4;
        END
    END

    DECLARE @NewBalance BIGINT =
        (SELECT Amount FROM PlayerResources WHERE UserId = @UserId AND ResourceTypeId = @KristalId);

    INSERT INTO Transactions (UserId, ResourceTypeId, Amount, BalanceAfter, Reason, ReferenceId, CreatedAt)
    VALUES (@UserId, @KristalId, -@Cost, @NewBalance, N'BUY_UPGRADE', @UpgradeTypeId, @Now);

    COMMIT TRANSACTION;

    SELECT @Current + 1 AS NewLevel, @Cost AS Cost, @NewBalance AS NewBalance, @Now AS ServerTime;
    RETURN 0;
END
GO

-- ============================================================================
-- 9. sp_UnlockClickType — yeni kazma turu ac
-- Acilis GENELDIR ama her tesis icin bekleme takip satiri olusturulmalidir.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_UnlockClickType
    @UserId INT,
    @ClickTypeId INT,
    @ErrorMessage NVARCHAR(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ErrorMessage = NULL;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();
    DECLARE @Cost BIGINT = (SELECT UnlockCost FROM ClickTypes WHERE Id = @ClickTypeId);

    IF @Cost IS NULL
    BEGIN
        SET @ErrorMessage = N'Kazma turu bulunamadi.';
        RETURN -1;
    END

    IF EXISTS (SELECT 1 FROM PlayerClickUnlocks WHERE UserId = @UserId AND ClickTypeId = @ClickTypeId)
    BEGIN
        SET @ErrorMessage = N'Bu kazma turu zaten acik.';
        RETURN -2;
    END

    DECLARE @KristalId INT = (SELECT Id FROM ResourceTypes WHERE Code = N'KRISTAL');

    BEGIN TRANSACTION;

    UPDATE PlayerResources
    SET Amount = Amount - @Cost, UpdatedAt = @Now
    WHERE UserId = @UserId AND ResourceTypeId = @KristalId AND Amount >= @Cost;

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK TRANSACTION;
        SET @ErrorMessage = N'Yetersiz Kristal.';
        RETURN -3;
    END

    INSERT INTO PlayerClickUnlocks (UserId, ClickTypeId, UnlockedAt)
    VALUES (@UserId, @ClickTypeId, @Now);

    -- Sahip olunan HER tesis icin bekleme takip satiri
    INSERT INTO PlayerFacilityClicks (UserId, FacilityTypeId, ClickTypeId)
    SELECT @UserId, pf.FacilityTypeId, @ClickTypeId
    FROM PlayerFacilities pf
    WHERE pf.UserId = @UserId
      AND NOT EXISTS (SELECT 1 FROM PlayerFacilityClicks x
                      WHERE x.UserId = @UserId AND x.FacilityTypeId = pf.FacilityTypeId
                        AND x.ClickTypeId = @ClickTypeId);

    DECLARE @NewBalance BIGINT =
        (SELECT Amount FROM PlayerResources WHERE UserId = @UserId AND ResourceTypeId = @KristalId);

    INSERT INTO Transactions (UserId, ResourceTypeId, Amount, BalanceAfter, Reason, ReferenceId, CreatedAt)
    VALUES (@UserId, @KristalId, -@Cost, @NewBalance, N'UNLOCK_CLICK', @ClickTypeId, @Now);

    COMMIT TRANSACTION;

    SELECT @Cost AS Cost, @NewBalance AS NewBalance, @Now AS ServerTime;
    RETURN 0;
END
GO

-- ============================================================================
-- 10. sp_GetPlayerState — SURUM 3
--
-- Yeni sonuc kumeleri: madenciler, guclendirmeler ve BEKLEYEN URETIM.
--
-- BekleyenUretim, sp_CollectProduction ile AYNI formulu kullanir:
--     min(gecenSure, tavan) x uretimHizi x carpan
-- Ikisi de fn_MinerRates'i cagirdigi icin hesap tek yerde tanimli kalir;
-- ekranda gorunen sayi ile toplandiginda gelen sayi ayrisamaz.
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

    -- --- 2) Tesisler (+ saniyelik otomatik uretim) ---
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

    -- --- 5) Madenciler: her tesis x her kademe icin mevcut sayi ---
    SELECT
        ft.Id AS FacilityTypeId,
        mt.Id AS MinerTypeId,
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
    SELECT
        ut.Id AS UpgradeTypeId, ut.Code, ut.Name, ut.Description,
        ut.EffectType, ut.EffectValue, ut.MaxLevel,
        ISNULL(pu.Level, 0) AS Level,
        nxt.Cost AS NextLevelCost
    FROM UpgradeTypes ut
    LEFT JOIN PlayerUpgrades pu ON pu.UserId = @UserId AND pu.UpgradeTypeId = ut.Id
    LEFT JOIN UpgradeLevels nxt ON nxt.UpgradeTypeId = ut.Id AND nxt.Level = ISNULL(pu.Level, 0) + 1
    ORDER BY ut.DisplayOrder;

    -- --- 7) Bekleyen (henuz toplanmamis) uretim ---
    SELECT
        rt.Id AS ResourceTypeId, rt.Code, rt.Name,
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

    -- --- 8) Sunucu saati + tamamlanan gelistirme sayisi ---
    SELECT @Now AS ServerTime, @Completed AS CompletedUpgrades;
END
GO

PRINT N'07_automation_economy.sql tamamlandi.';
GO
