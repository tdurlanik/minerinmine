-- ============================================================================
-- PROJE: MinerInMine
-- ADIM 10: Denge Duzeltmesi
--
--   sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i 10_denge_duzeltmesi.sql
--
-- NEDEN? Denge simulasyonu (tools/denge-simulasyonu.js) uc sorunu OLCTU:
--
--   1. Aceleci oyuncu oyunu 7 DAKIKADA bitirdi.
--      Sebep: aninda bitirme bedeli MUTLAK Kristal (dakika x 10). Gelir usel
--      buyurken bedel sabit kaldigi icin zaman mekanigi tamamen atlaniyordu.
--
--   2. Tum madenciler 2 SAATTE tavana ulasti.
--      Sebep: madenci ucreti SABIT. Ilk madenci ile 25. madenci ayni fiyat,
--      dolayisiyla "bir tane daha mi alsam?" diye bir karar hic olusmuyordu.
--
--   3. Manuel tiklamanin anlami yoktu.
--      Sebep: madenci, manuel tiklamayla BIREBIR AYNI verimde uretiyordu ve
--      25 tane alinabiliyordu. Hicbir insan 25 tiklama/sn ile yarisamaz.
--
-- UC DUZELTME:
--   A. Madenci ucreti olceklensin  -> her ek madenci %18 pahali
--   B. Madenci verimi %50 olsun     -> manuel tiklama her zaman daha verimli
--   C. Aninda bitirme ORANSAL olsun -> yukseltme maliyetine bagli, sonsuza kadar olcekleni
-- ============================================================================

USE MinerInMineDb;
GO

-- ============================================================================
-- 1. Yeni ayarlar
-- ============================================================================
MERGE INTO GameSettings AS h
USING (VALUES
    (N'MINER_EFFICIENCY', N'0.50',
     N'Madencinin verimi: manuel tiklamanin yuzde kaci kadar uretir (0.50 = yarisi)'),
    (N'INSTANT_FINISH_MULTIPLIER', N'2.0',
     N'Aninda bitirme bedeli = yukseltme maliyeti x kalan oran x bu carpan'),
    (N'MINER_COST_MULTIPLIER', N'1.18',
     N'Her ek madencinin ucreti bir oncekinin bu kati olur')
) AS k (SettingKey, SettingValue, Description)
    ON h.SettingKey = k.SettingKey
WHEN MATCHED THEN UPDATE SET h.SettingValue = k.SettingValue, h.Description = k.Description
WHEN NOT MATCHED THEN INSERT (SettingKey, SettingValue, Description)
    VALUES (k.SettingKey, k.SettingValue, k.Description);
GO

-- ============================================================================
-- MADENCI TAVANI PRATIKTE KALDIRILIYOR (25 -> 150)
--
-- ILK DENEMEDE HATA YAPTIK: tavani 25'ten 50'ye cikarip verimi %50'ye
-- dusurunce ikisi BIRBIRINI TAM OLARAK IPTAL ETTI (25 x 7.4 = 50 x 7.4 x 0.5)
-- ve gelir hic degismedi. Simulasyon bunu aninda gosterdi.
--
-- Asil sorun tavanin degeri degil, TAVANIN VARLIGIYDI. Her sey tavanliydi:
-- madenciler, kazma turleri, guclendirmeler. Oyuncu birkac saat sonra
-- alinabilecek her seyi aliyor ve Kristal SONSUZA KADAR birikiyordu —
-- 24 saatte 406 milyar, harcayacak yer yok.
--
-- Cozum: tavani pratikte kaldirip SINIRLAYICI OLARAK MALIYETI birakmak.
-- 1.18 uslu artisla 150. madenci zaten astronomik pahali; oyuncu tavana
-- carpmaz, butcesine carpar. Idle oyun turunun klasik cozumu budur:
-- sinirsiz satin alma + uslu fiyat = her zaman bir sonraki hedef.
--
-- Neden 150? Daha yukarisi BIGINT sinirini asar (90000 x 1.18^199 > 9.2e18).
-- ============================================================================
UPDATE MinerTypes SET MaxCount = 150;
GO

-- ============================================================================
-- 2. MinerLevels — madenci ucretleri icin denge tablosu
--
-- FacilityLevels ve UpgradeLevels ile AYNI gerekce: maliyeti calisma aninda
-- POWER() ile hesaplarsak SQL, C# ve JavaScript farkli sonuc verebilir.
-- Sonlu sayida madenci oldugu icin bir kez hesaplayip tam sayi olarak sakliyoruz.
--
-- SATIR ANLAMI: "Count = N" satiri, N. MADENCIYI ise almanin bedelidir.
-- Yani ilk madenci Count=1, ikinci madenci Count=2 satirindan okunur.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'MinerLevels')
BEGIN
    CREATE TABLE MinerLevels (
        MinerTypeId INT NOT NULL,
        Count INT NOT NULL,
        Cost BIGINT NOT NULL,

        CONSTRAINT PK_MinerLevels PRIMARY KEY (MinerTypeId, Count),
        CONSTRAINT FK_MinerLevels_MinerTypes
            FOREIGN KEY (MinerTypeId) REFERENCES MinerTypes(Id) ON DELETE CASCADE,
        CONSTRAINT CK_MinerLevels_Count CHECK (Count >= 1),
        CONSTRAINT CK_MinerLevels_Cost CHECK (Cost > 0)
    );
END
GO

WITH Sayilar AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM Sayilar WHERE n < 200
)
MERGE INTO MinerLevels AS h
USING (
    SELECT mt.Id AS MinerTypeId, s.n AS Count,
           CAST(FLOOR(mt.HireCost * POWER(
               (SELECT CAST(SettingValue AS FLOAT) FROM GameSettings WHERE SettingKey = N'MINER_COST_MULTIPLIER'),
               s.n - 1)) AS BIGINT) AS Cost
    FROM MinerTypes mt
    JOIN Sayilar s ON s.n <= mt.MaxCount
) AS k
    ON h.MinerTypeId = k.MinerTypeId AND h.Count = k.Count
WHEN MATCHED THEN UPDATE SET h.Cost = k.Cost
WHEN NOT MATCHED BY TARGET THEN
    INSERT (MinerTypeId, Count, Cost) VALUES (k.MinerTypeId, k.Count, k.Cost)
WHEN NOT MATCHED BY SOURCE THEN DELETE
OPTION (MAXRECURSION 300);
GO

-- ============================================================================
-- 3. fn_MinerRates — SURUM 2: madenci verimi uygulaniyor
--
-- Madenci artik manuel tiklamanin YARISI kadar uretiyor.
--
-- NEDEN? Onceden madenci, manuel tiklamayla birebir ayni verimdeydi ve 25 tane
-- alinabiliyordu. Hicbir insan 25 tiklama/saniye ile yarisamaz; dolayisiyla
-- manuel kazma otomasyondan sonra tamamen anlamsizlasiyordu.
--
-- Verim <1 olunca denge tersine doner: manuel tiklama HER ZAMAN en verimli
-- eylemdir, otomasyon ise olcek ve offline icindir. Aktif oyuncu odullendirilir,
-- pasif oyuncu yine ilerler.
--
-- Bu tek fonksiyonu degistirmek yetiyor cunku hem toplama hem ekranda gosterme
-- ayni yerden besleniyor (Gun 4'te bilincli olarak boyle kurmustuk).
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
            * ayar.Verim
        ) AS BasePerSecond
    FROM PlayerMiners pm

    -- Ayari CROSS JOIN ile SUTUN haline getiriyoruz. Dogrudan alt sorgu olarak
    -- SUM() icine yazmak SQL Server'da hata verir: "aggregate icinde alt sorgu olamaz".
    CROSS JOIN (
        SELECT CAST(SettingValue AS DECIMAL(10,4)) AS Verim
        FROM GameSettings WHERE SettingKey = N'MINER_EFFICIENCY'
    ) ayar
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
-- 4. sp_HireMiner — SURUM 2: olcekli ucret
--
-- Ucret artik sabit degil; kacinci madenciyi aldigina bagli ve MinerLevels
-- denge tablosundan okunuyor.
--
-- Bunun oyun tasarimindaki karsiligi: her satin alma bir KARAR haline geliyor.
-- "Bir Cirak daha mi alsam, yoksa biriktirip Usta'ya mi gecsem?" Sabit ucrette
-- boyle bir soru yoktu; tavana kadar hepsini alip gecerdin.
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

    DECLARE @ClickTypeId INT, @MaxCount INT;
    SELECT @ClickTypeId = ClickTypeId, @MaxCount = MaxCount
    FROM MinerTypes WHERE Id = @MinerTypeId;

    IF @MaxCount IS NULL
    BEGIN
        SET @ErrorMessage = N'Madenci turu bulunamadi.';
        RETURN -2;
    END

    IF NOT EXISTS (SELECT 1 FROM PlayerClickUnlocks WHERE UserId = @UserId AND ClickTypeId = @ClickTypeId)
    BEGIN
        SET @ErrorMessage = N'Bu madencinin kullandigi kazma turu henuz acilmamis.';
        RETURN -3;
    END

    DECLARE @Mevcut INT = ISNULL((
        SELECT Count FROM PlayerMiners
        WHERE UserId = @UserId AND FacilityTypeId = @FacilityTypeId AND MinerTypeId = @MinerTypeId), 0);

    IF @Mevcut >= @MaxCount
    BEGIN
        SET @ErrorMessage = N'Bu tesiste bu madenci kademesi icin ust sinira ulastiniz.';
        RETURN -4;
    END

    -- Bir sonraki madencinin ucreti denge tablosundan
    DECLARE @HireCost BIGINT =
        (SELECT Cost FROM MinerLevels WHERE MinerTypeId = @MinerTypeId AND Count = @Mevcut + 1);

    IF @HireCost IS NULL
    BEGIN
        SET @ErrorMessage = N'Denge tablosunda bu madenci sayisi bulunamadi.';
        RETURN -99;
    END

    DECLARE @KristalId INT = (SELECT Id FROM ResourceTypes WHERE Code = N'KRISTAL');

    BEGIN TRANSACTION;

    IF @Mevcut = 0
    BEGIN
        INSERT INTO PlayerMiners (UserId, FacilityTypeId, MinerTypeId, Count)
        VALUES (@UserId, @FacilityTypeId, @MinerTypeId, 0);
    END

    -- Sayiyi kosullu artir: "Count = @Mevcut" kosulu, arada baska bir istek
    -- madenci aldiysa bu islemi iptal eder (yaris durumu korumasi).
    UPDATE PlayerMiners
    SET Count = Count + 1, UpdatedAt = @Now
    WHERE UserId = @UserId AND FacilityTypeId = @FacilityTypeId
      AND MinerTypeId = @MinerTypeId AND Count = @Mevcut;

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK TRANSACTION;
        SET @ErrorMessage = N'Madenci sayisi degismis, islem iptal edildi.';
        RETURN -4;
    END

    UPDATE PlayerResources
    SET Amount = Amount - @HireCost, UpdatedAt = @Now
    WHERE UserId = @UserId AND ResourceTypeId = @KristalId AND Amount >= @HireCost;

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK TRANSACTION;
        SET @ErrorMessage = N'Yetersiz Kristal.';
        RETURN -5;
    END

    DECLARE @NewBalance BIGINT =
        (SELECT Amount FROM PlayerResources WHERE UserId = @UserId AND ResourceTypeId = @KristalId);

    INSERT INTO Transactions (UserId, ResourceTypeId, Amount, BalanceAfter, Reason, ReferenceId, CreatedAt)
    VALUES (@UserId, @KristalId, -@HireCost, @NewBalance, N'HIRE_MINER', @FacilityTypeId, @Now);

    COMMIT TRANSACTION;

    SELECT @Mevcut + 1 AS NewCount, @HireCost AS Cost, @NewBalance AS NewBalance, @Now AS ServerTime;
    RETURN 0;
END
GO

-- ============================================================================
-- 5. sp_FinishUpgradeNow — SURUM 2: ORANSAL bedel
--
-- ESKI:  bedel = kalanDakika x 10 Kristal          (MUTLAK)
-- YENI:  bedel = yukseltmeMaliyeti x kalanOran x 2 (ORANSAL)
--
-- NEDEN? Simulasyon olctu: mutlak bedelle aceleci oyuncu oyunu 7 DAKIKADA
-- bitiriyordu. Cunku gelir usel buyurken bedel sabit kaliyor; 60 dakikalik bir
-- insaati atlamak, oyuncunun 0.06 saniyelik gelirine mal oluyordu.
--
-- Oransal bedel bu sorunu KOKTEN cozer: yukseltme pahalilastikca atlama da
-- pahalilanir. Iliski hicbir zaman bozulmaz, ek ayar gerekmez.
--
-- kalanOran = kalanSaniye / toplamSaniye
--   UpgradeStartedAt ve UpgradeCompletesAt zaten kayitli oldugu icin toplam
--   sureyi tablodan aramaya gerek yok; ikisinin farki bize veriyor.
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

    EXEC sp_ApplyDueUpgrades @UserId, @Dummy OUTPUT;

    DECLARE @CompletesAt DATETIME2, @StartedAt DATETIME2, @Level INT;

    SELECT @CompletesAt = UpgradeCompletesAt, @StartedAt = UpgradeStartedAt, @Level = Level
    FROM PlayerFacilities
    WHERE UserId = @UserId AND FacilityTypeId = @FacilityTypeId;

    IF @Level IS NULL
    BEGIN
        SET @ErrorMessage = N'Bu tesise sahip degilsiniz.';
        RETURN -1;
    END

    IF @CompletesAt IS NULL
    BEGIN
        SET @ErrorMessage = N'Devam eden bir gelistirme yok.';
        RETURN -2;
    END

    DECLARE @RemainingSeconds INT = DATEDIFF(SECOND, @Now, @CompletesAt);
    IF @RemainingSeconds < 0 SET @RemainingSeconds = 0;

    DECLARE @TotalSeconds INT = DATEDIFF(SECOND, @StartedAt, @CompletesAt);
    IF @TotalSeconds <= 0 SET @TotalSeconds = 1;      -- sifira bolmeyi engelle

    -- Hedef seviyenin maliyeti (denge tablosundan)
    DECLARE @UpgradeCost BIGINT =
        (SELECT Cost FROM FacilityLevels WHERE FacilityTypeId = @FacilityTypeId AND Level = @Level + 1);

    DECLARE @Carpan DECIMAL(10,3) =
        (SELECT CAST(SettingValue AS DECIMAL(10,3)) FROM GameSettings WHERE SettingKey = N'INSTANT_FINISH_MULTIPLIER');

    DECLARE @Cost BIGINT = CAST(CEILING(
        @UpgradeCost * (CAST(@RemainingSeconds AS DECIMAL(18,6)) / @TotalSeconds) * @Carpan
    ) AS BIGINT);

    IF @Cost < 1 SET @Cost = 1;

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

    UPDATE PlayerFacilities
    SET Level = Level + 1, UpgradeStartedAt = NULL, UpgradeCompletesAt = NULL
    WHERE UserId = @UserId AND FacilityTypeId = @FacilityTypeId
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

    SELECT @Level + 1 AS NewLevel, @Cost AS Cost, @NewBalance AS NewBalance,
           @RemainingSeconds AS SkippedSeconds, @Now AS ServerTime;
    RETURN 0;
END
GO

-- ============================================================================
-- 6. sp_GetPlayerState — SURUM 5
--
-- Uc degisiklik (denge duzeltmesinin arayuze yansimasi):
--   1. InstantFinishCost artik ORANSAL formulle hesaplaniyor
--   2. Madenci ucreti MinerLevels'tan, SIRADAKI madencinin fiyati olarak geliyor
--   3. PerSecondEach'e madenci verimi uygulaniyor
--
-- 2. maddeye dikkat: arayuzde gorunen fiyat ile sunucunun tahsil ettigi fiyat
-- AYNI kaynaktan (MinerLevels) okunuyor. Farkli yerlerden okusalardi oyuncu
-- bir fiyat gorup baska bir fiyat oderdi.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_GetPlayerState
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Completed INT;
    EXEC sp_ApplyDueUpgrades @UserId, @Completed OUTPUT;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();
    DECLARE @CapSeconds INT =
        (SELECT CAST(SettingValue AS INT) * 3600 FROM GameSettings WHERE SettingKey = N'OFFLINE_CAP_HOURS');
    DECLARE @SkipCarpan DECIMAL(10,3) =
        (SELECT CAST(SettingValue AS DECIMAL(10,3)) FROM GameSettings WHERE SettingKey = N'INSTANT_FINISH_MULTIPLIER');
    DECLARE @Verim DECIMAL(10,4) =
        (SELECT CAST(SettingValue AS DECIMAL(10,4)) FROM GameSettings WHERE SettingKey = N'MINER_EFFICIENCY');

    DECLARE @MinerMult DECIMAL(10,3) = 1.0;
    SELECT @MinerMult = 1.0 + ISNULL(SUM(ut.EffectValue * pu.Level), 0)
    FROM PlayerUpgrades pu JOIN UpgradeTypes ut ON ut.Id = pu.UpgradeTypeId
    WHERE pu.UserId = @UserId AND ut.EffectType = N'MINER_SPEED';

    -- --- 1) Kaynaklar ---
    SELECT rt.Id AS ResourceTypeId, rt.Code, rt.Name, pr.Amount, rt.SellValue, rt.IsCurrency
    FROM PlayerResources pr JOIN ResourceTypes rt ON rt.Id = pr.ResourceTypeId
    WHERE pr.UserId = @UserId ORDER BY rt.DisplayOrder;

    -- --- 2) Tesisler (InstantFinishCost artik oransal) ---
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
            CAST(CEILING(
                nxt.Cost
                * (CAST(CASE WHEN DATEDIFF(SECOND, @Now, pf.UpgradeCompletesAt) < 0 THEN 0
                             ELSE DATEDIFF(SECOND, @Now, pf.UpgradeCompletesAt) END AS DECIMAL(18,6))
                   / CASE WHEN DATEDIFF(SECOND, pf.UpgradeStartedAt, pf.UpgradeCompletesAt) <= 0 THEN 1
                          ELSE DATEDIFF(SECOND, pf.UpgradeStartedAt, pf.UpgradeCompletesAt) END)
                * @SkipCarpan
            ) AS BIGINT)
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

    -- --- 4) Bekleme durumlari ---
    SELECT pfc.FacilityTypeId, pfc.ClickTypeId, pfc.LastClickAt,
           CASE WHEN pfc.LastClickAt IS NULL THEN @Now
                ELSE DATEADD(SECOND, ct.CooldownSeconds, pfc.LastClickAt) END AS NextAvailableAt
    FROM PlayerFacilityClicks pfc JOIN ClickTypes ct ON ct.Id = pfc.ClickTypeId
    WHERE pfc.UserId = @UserId;

    -- --- 5) Madenciler (ucret = SIRADAKI madencinin fiyati, verim uygulanmis) ---
    SELECT
        ft.Id AS FacilityTypeId, mt.Id AS MinerTypeId,
        mt.Code, mt.Name,
        ISNULL(sonraki.Cost, 0) AS HireCost,
        mt.MaxCount,
        ct.Code AS ClickCode, ct.Name AS ClickName,
        ISNULL(pm.Count, 0) AS Count,
        CAST(CASE WHEN pcu.UserId IS NULL THEN 0 ELSE 1 END AS BIT) AS IsAvailable,
        CAST(fl.Production * ct.YieldMultiplier / ct.CooldownSeconds * @Verim AS DECIMAL(18,2)) AS PerSecondEach
    FROM PlayerFacilities pf
    JOIN FacilityTypes ft ON ft.Id = pf.FacilityTypeId
    JOIN FacilityLevels fl ON fl.FacilityTypeId = pf.FacilityTypeId AND fl.Level = pf.Level
    CROSS JOIN MinerTypes mt
    JOIN ClickTypes ct ON ct.Id = mt.ClickTypeId
    LEFT JOIN PlayerMiners pm ON pm.UserId = @UserId AND pm.FacilityTypeId = ft.Id AND pm.MinerTypeId = mt.Id
    LEFT JOIN PlayerClickUnlocks pcu ON pcu.UserId = @UserId AND pcu.ClickTypeId = mt.ClickTypeId
    LEFT JOIN MinerLevels sonraki ON sonraki.MinerTypeId = mt.Id AND sonraki.Count = ISNULL(pm.Count, 0) + 1
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

    -- --- 8) Satin alinabilir tesisler ---
    SELECT
        ft.Id AS FacilityTypeId, ft.Code, ft.Name,
        rt.Code AS ResourceCode, rt.Name AS ResourceName,
        fl.Cost, fl.Production AS StartProduction,
        gerekli.Name AS RequiredFacilityName,
        ft.UnlockLevel AS RequiredLevel,
        ISNULL(sahip.Level, 0) AS RequiredCurrentLevel,
        CAST(CASE WHEN ft.UnlockFacilityTypeId IS NULL THEN 1
                  WHEN ISNULL(sahip.Level, 0) >= ft.UnlockLevel THEN 1 ELSE 0 END AS BIT) AS IsUnlocked
    FROM FacilityTypes ft
    JOIN ResourceTypes rt ON rt.Id = ft.ResourceTypeId
    JOIN FacilityLevels fl ON fl.FacilityTypeId = ft.Id AND fl.Level = 1
    LEFT JOIN FacilityTypes gerekli ON gerekli.Id = ft.UnlockFacilityTypeId
    LEFT JOIN PlayerFacilities sahip ON sahip.UserId = @UserId AND sahip.FacilityTypeId = ft.UnlockFacilityTypeId
    WHERE NOT EXISTS (SELECT 1 FROM PlayerFacilities pf WHERE pf.UserId = @UserId AND pf.FacilityTypeId = ft.Id)
    ORDER BY ft.DisplayOrder;

    -- --- 9) Sunucu saati ---
    SELECT @Now AS ServerTime, @Completed AS CompletedUpgrades;
END
GO

PRINT N'10_denge_duzeltmesi.sql tamamlandi.';
GO

-- ============================================================================
-- 7. GUNLUK ATLAMA SINIRI
--
-- SIMULASYON NE GOSTERDI?
-- Aninda bitirme bedelini 2 kattan 150 KATA cikardik — aceleci oyuncu yine
-- oyunu bitirdi. Cunku bedel "yukseltme maliyetine" orantili ve yukseltme
-- maliyetleri, oyunun urettigi gelirin yaninda zaten cok kucuk.
--
-- ASIL SEBEP BIR TASARIM KARARI:
-- Tek para birimi kullaniyoruz (Kristal). Oyuncu, atlamak icin odeyecegi parayi
-- KENDISI URETIYOR. Gercek oyunlarda atlama ayri bir premium parayla yapilir ve
-- o para farm edilemez — sorun bu yuzden orada olusmaz.
--
-- Kararı geri almadan cozum: atlamayi PARAYLA degil SAYIYLA sinirlamak.
-- Gunde en fazla N kez atlama yapilabilir. Boylece atlama "acil durumda
-- kullanilan bir kolaylik" olur, bir hizli bitirme stratejisi degil.
-- ============================================================================
MERGE INTO GameSettings AS h
USING (VALUES
    (N'INSTANT_FINISH_DAILY_LIMIT', N'5',
     N'24 saat icinde en fazla kac gelistirme parayla bitirilebilir')
) AS k (SettingKey, SettingValue, Description)
    ON h.SettingKey = k.SettingKey
WHEN MATCHED THEN UPDATE SET h.SettingValue = k.SettingValue, h.Description = k.Description
WHEN NOT MATCHED THEN INSERT (SettingKey, SettingValue, Description)
    VALUES (k.SettingKey, k.SettingValue, k.Description);
GO

-- sp_FinishUpgradeNow'a gunluk sinir kontrolu ekleniyor.
-- Sayim Transactions gunlugunden yapiliyor — ayri bir sayac tablosu tutmuyoruz.
-- Gun 4'te "olay gunlugu sonradan eklenemez" demistik; iste somut karsiligi:
-- yeni bir kural, var olan gunluk sayesinde ek tablo gerektirmeden yazilabiliyor.
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

    EXEC sp_ApplyDueUpgrades @UserId, @Dummy OUTPUT;

    -- Gunluk sinir kontrolu
    DECLARE @Limit INT =
        (SELECT CAST(SettingValue AS INT) FROM GameSettings WHERE SettingKey = N'INSTANT_FINISH_DAILY_LIMIT');
    DECLARE @Bugun INT =
        (SELECT COUNT(*) FROM Transactions
         WHERE UserId = @UserId AND Reason = N'INSTANT_FINISH'
           AND CreatedAt >= DATEADD(HOUR, -24, @Now));

    IF @Bugun >= @Limit
    BEGIN
        SET @ErrorMessage = N'Gunluk hizlandirma hakkiniz doldu (' + CAST(@Limit AS NVARCHAR(10))
                          + N'/gun). Insaatin bitmesini bekleyin.';
        RETURN -5;
    END

    DECLARE @CompletesAt DATETIME2, @StartedAt DATETIME2, @Level INT;

    SELECT @CompletesAt = UpgradeCompletesAt, @StartedAt = UpgradeStartedAt, @Level = Level
    FROM PlayerFacilities
    WHERE UserId = @UserId AND FacilityTypeId = @FacilityTypeId;

    IF @Level IS NULL
    BEGIN
        SET @ErrorMessage = N'Bu tesise sahip degilsiniz.';
        RETURN -1;
    END

    IF @CompletesAt IS NULL
    BEGIN
        SET @ErrorMessage = N'Devam eden bir gelistirme yok.';
        RETURN -2;
    END

    DECLARE @RemainingSeconds INT = DATEDIFF(SECOND, @Now, @CompletesAt);
    IF @RemainingSeconds < 0 SET @RemainingSeconds = 0;

    DECLARE @TotalSeconds INT = DATEDIFF(SECOND, @StartedAt, @CompletesAt);
    IF @TotalSeconds <= 0 SET @TotalSeconds = 1;

    DECLARE @UpgradeCost BIGINT =
        (SELECT Cost FROM FacilityLevels WHERE FacilityTypeId = @FacilityTypeId AND Level = @Level + 1);

    DECLARE @Carpan DECIMAL(10,3) =
        (SELECT CAST(SettingValue AS DECIMAL(10,3)) FROM GameSettings WHERE SettingKey = N'INSTANT_FINISH_MULTIPLIER');

    DECLARE @Cost BIGINT = CAST(CEILING(
        @UpgradeCost * (CAST(@RemainingSeconds AS DECIMAL(18,6)) / @TotalSeconds) * @Carpan
    ) AS BIGINT);

    IF @Cost < 1 SET @Cost = 1;

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

    UPDATE PlayerFacilities
    SET Level = Level + 1, UpgradeStartedAt = NULL, UpgradeCompletesAt = NULL
    WHERE UserId = @UserId AND FacilityTypeId = @FacilityTypeId
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

    SELECT @Level + 1 AS NewLevel, @Cost AS Cost, @NewBalance AS NewBalance,
           @RemainingSeconds AS SkippedSeconds, @Limit - @Bugun - 1 AS RemainingSkips,
           @Now AS ServerTime;
    RETURN 0;
END
GO
