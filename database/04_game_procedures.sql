-- ============================================================================
-- PROJE: MinerInMine
-- ADIM 4: Oyun Mekanigi Stored Procedure'leri
--
--   sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i 04_game_procedures.sql
--
-- BU DOSYANIN ANA KONUSU: SUNUCU OTORITESI (server authority)
--
-- Istemci ASLA "5 demir kazandim" diyemez. Istemci yalnizca NIYET bildirir:
-- "Demir Ocagi'nda 1 sn'lik kazmayi yaptim." Ne kadar kazandigini, hatta
-- kazanip kazanamayacagini sunucu kendisi belirler.
--
-- Aksi halde oyuncu F12 acar, istegi degistirir, kendine milyonlarca kaynak
-- yazar. Leaderboard'u olan bir oyunda bu, oyunu ilk gunde bitirir.
-- ============================================================================

USE MinerInMineDb;
GO

-- ############################################################################
-- BOLUM 1: GECIS — sp_RegisterUser'i yeni tablolara tasima
--
-- "Genislet / Gecis / Daralt" deseninin ikinci adimi.
-- 03 numarali dosyada yeni tablolari olusturup veriyi kopyalamistik (genislet).
-- Simdi kodu yeni tablolara gecirip, en sonda eski sutunlari silecegiz (daralt).
-- ############################################################################

CREATE OR ALTER PROCEDURE sp_RegisterUser
    @Username NVARCHAR(50),
    @Email NVARCHAR(100),
    @PasswordHash NVARCHAR(256),
    @PasswordSalt NVARCHAR(256),
    @RoleName NVARCHAR(50) = 'Player',
    @NewUserId INT OUTPUT,
    @ErrorMessage NVARCHAR(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @ErrorMessage = NULL;
    SET @NewUserId = 0;

    IF EXISTS (SELECT 1 FROM Users WHERE Username = @Username)
    BEGIN
        SET @ErrorMessage = N'Bu kullanıcı adı zaten kullanılmaktadır.';
        RETURN -1;
    END

    IF EXISTS (SELECT 1 FROM Users WHERE Email = @Email)
    BEGIN
        SET @ErrorMessage = N'Bu e-posta adresi zaten kayıtlıdır.';
        RETURN -2;
    END

    BEGIN TRANSACTION;
    BEGIN TRY
        -- 1. Kullanici kaydi
        INSERT INTO Users (Username, Email, PasswordHash, PasswordSalt, IsActive)
        VALUES (@Username, @Email, @PasswordHash, @PasswordSalt, 1);

        SET @NewUserId = SCOPE_IDENTITY();

        -- 2. Rol atamasi
        DECLARE @RoleId INT;
        SELECT @RoleId = Id FROM Roles WHERE Name = @RoleName;
        IF @RoleId IS NULL
            SELECT @RoleId = Id FROM Roles WHERE Name = 'Player';

        INSERT INTO UserRoles (UserId, RoleId) VALUES (@NewUserId, @RoleId);

        -- ------------------------------------------------------------------
        -- 3. OYUN BASLANGIC DURUMU
        -- Eskiden tek satirlik PlayerProfiles yaziyorduk. Artik oyun durumu
        -- birden fazla tabloya dagilmis durumda; hepsi AYNI transaction icinde
        -- yazilir. Biri basarisiz olursa kullanici da olusmaz — yarim oyuncu kalmaz.
        -- ------------------------------------------------------------------

        -- 3a. Her kaynaktan bir satir. Baslangic sermayesi: 100 Kristal.
        --     Satirlari simdi olusturmak, sonraki tum islemlerde "satir var mi?"
        --     kontrolunu gereksiz kilar; sadece UPDATE yeter.
        INSERT INTO PlayerResources (UserId, ResourceTypeId, Amount)
        SELECT @NewUserId, rt.Id,
               CASE WHEN rt.Code = N'KRISTAL' THEN 100 ELSE 0 END
        FROM ResourceTypes rt;

        -- 3b. Herkes Demir Ocagi ile baslar (1. seviye)
        INSERT INTO PlayerFacilities (UserId, FacilityTypeId, Level)
        SELECT @NewUserId, Id, 1 FROM FacilityTypes WHERE Code = N'DEMIR_OCAGI';

        -- 3c. 1 sn'lik kazma bastan aciktir
        INSERT INTO PlayerClickUnlocks (UserId, ClickTypeId)
        SELECT @NewUserId, Id FROM ClickTypes WHERE Code = N'CLICK_1';

        -- 3d. Sahip olunan tesis x acik tiklama icin bekleme takip satiri
        INSERT INTO PlayerFacilityClicks (UserId, FacilityTypeId, ClickTypeId)
        SELECT pf.UserId, pf.FacilityTypeId, pcu.ClickTypeId
        FROM PlayerFacilities pf
        JOIN PlayerClickUnlocks pcu ON pcu.UserId = pf.UserId
        WHERE pf.UserId = @NewUserId;

        COMMIT TRANSACTION;
        RETURN 0;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SET @ErrorMessage = ERROR_MESSAGE();
        RETURN -99;
    END CATCH
END
GO

-- ############################################################################
-- BOLUM 2: sp_Mine — TIKLAMA (bu dosyanin kalbi)
--
-- Istemciden gelen: "su tesiste, su tiklama turuyle kazma yaptim"
-- Sunucunun yaptigi:
--   1. Bu tiklama turu bu oyuncuda acik mi?
--   2. Bu tesise sahip mi?
--   3. Bekleme suresi doldu mu?          <- HILE ONLEME
--   4. Uretim NE KADAR?                  <- SUNUCU HESAPLAR
--   5. Kaynagi ekle, zamani guncelle, gunluge yaz  <- TEK TRANSACTION
-- ############################################################################

CREATE OR ALTER PROCEDURE sp_Mine
    @UserId INT,
    @FacilityTypeId INT,
    @ClickTypeId INT,
    @ErrorMessage NVARCHAR(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- XACT_ABORT ON: Beklenmeyen bir hata olursa transaction OTOMATIK geri alinir.
    -- Bu olmadan bazi hata turlerinde transaction acik kalabilir ve satirlar
    -- kilitli kalir. Veri degistiren her SP'de acilmasi iyi bir aliskanliktir.
    SET XACT_ABORT ON;

    SET @ErrorMessage = NULL;

    -- ----------------------------------------------------------------------
    -- ZAMAN SUNUCUDAN ALINIR.
    -- Istemci "saat kac" bilgisini gonderemez; gonderse de kullanmayiz.
    -- Aksi halde oyuncu bilgisayarinin saatini ileri alip bekleme suresini
    -- atlardi. Tek dogru referans sunucunun UTC saatidir.
    -- ----------------------------------------------------------------------
    DECLARE @Now DATETIME2 = SYSUTCDATETIME();

    ----------------------------------------------------------------------
    -- 1. Tiklama turu bu oyuncuda acik mi?
    ----------------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1 FROM PlayerClickUnlocks
        WHERE UserId = @UserId AND ClickTypeId = @ClickTypeId
    )
    BEGIN
        SET @ErrorMessage = N'Bu kazma türü henüz açılmamış.';
        RETURN -1;
    END

    ----------------------------------------------------------------------
    -- 2. Tesise sahip mi? Seviyesi kac?
    ----------------------------------------------------------------------
    DECLARE @Level INT;
    SELECT @Level = Level
    FROM PlayerFacilities
    WHERE UserId = @UserId AND FacilityTypeId = @FacilityTypeId;

    IF @Level IS NULL
    BEGIN
        SET @ErrorMessage = N'Bu tesise sahip değilsiniz.';
        RETURN -2;
    END

    ----------------------------------------------------------------------
    -- 3. BEKLEME SURESI KONTROLU — en kritik adim
    --
    -- Once kontrol edip sonra guncelleseydik yaris durumu (race condition)
    -- olusurdu: oyuncu ayni anda 10 istek gonderirse 10'u da kontrolu gecer
    -- ve 10 kat kaynak kazanirdi.
    --
    -- Bunun yerine kosulu UPDATE'in WHERE'ine gomuyoruz. UPDATE atomiktir:
    -- ayni satiri ayni anda yalnizca BIR istek guncelleyebilir. Digerleri
    -- @@ROWCOUNT = 0 alir ve reddedilir.
    --
    -- Ayni deseni sp_RegisterUser ve ilerideki satin alma islemlerinde de
    -- kullanacagiz: "kontrol et sonra yaz" degil, "kosullu yaz sonra bak".
    ----------------------------------------------------------------------
    DECLARE @CooldownSeconds INT, @YieldMultiplier DECIMAL(10,2);

    SELECT @CooldownSeconds = CooldownSeconds,
           @YieldMultiplier = YieldMultiplier
    FROM ClickTypes WHERE Id = @ClickTypeId;

    BEGIN TRANSACTION;

    UPDATE PlayerFacilityClicks
    SET LastClickAt = @Now
    WHERE UserId = @UserId
      AND FacilityTypeId = @FacilityTypeId
      AND ClickTypeId = @ClickTypeId
      AND (
            LastClickAt IS NULL                                          -- hic tiklanmamis
            OR DATEADD(SECOND, @CooldownSeconds, LastClickAt) <= @Now    -- sure dolmus
          );

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK TRANSACTION;
        SET @ErrorMessage = N'Kazma henüz hazır değil, biraz bekleyin.';
        RETURN -3;
    END

    ----------------------------------------------------------------------
    -- 4. URETIM HESABI — tamamen sunucuda
    --
    --   uretim = seviyedeki uretim x tiklama carpani x guclendirme carpani
    --
    -- Seviyedeki uretim FacilityLevels denge tablosundan HAZIR okunur;
    -- POWER() ile hesaplanmaz. Boylece SP, API ve Angular ayni sayiyi gorur.
    ----------------------------------------------------------------------
    DECLARE @BaseProduction BIGINT;

    SELECT @BaseProduction = Production
    FROM FacilityLevels
    WHERE FacilityTypeId = @FacilityTypeId AND Level = @Level;

    IF @BaseProduction IS NULL
    BEGIN
        ROLLBACK TRANSACTION;
        SET @ErrorMessage = N'Denge tablosunda bu seviye bulunamadı.';
        RETURN -99;
    END

    -- CLICK_POWER turundeki guclendirmelerin toplam etkisi.
    -- Hic guclendirme yoksa ISNULL sayesinde carpan 1.0 olur.
    DECLARE @UpgradeMultiplier DECIMAL(10,3) = 1.0;

    SELECT @UpgradeMultiplier = 1.0 + ISNULL(SUM(ut.EffectValue * pu.Level), 0)
    FROM PlayerUpgrades pu
    JOIN UpgradeTypes ut ON ut.Id = pu.UpgradeTypeId
    WHERE pu.UserId = @UserId AND ut.EffectType = N'CLICK_POWER';

    -- FLOOR ile tam sayiya iniyoruz, ama en az 1 kazanilsin
    -- (aksi halde cok dusuk carpanlarda tiklama hicbir sey vermezdi).
    DECLARE @Gained BIGINT =
        CAST(FLOOR(@BaseProduction * @YieldMultiplier * @UpgradeMultiplier) AS BIGINT);

    IF @Gained < 1 SET @Gained = 1;

    ----------------------------------------------------------------------
    -- 5. Kaynagi ekle
    ----------------------------------------------------------------------
    DECLARE @ResourceTypeId INT;
    SELECT @ResourceTypeId = ResourceTypeId FROM FacilityTypes WHERE Id = @FacilityTypeId;

    UPDATE PlayerResources
    SET Amount = Amount + @Gained,
        UpdatedAt = @Now
    WHERE UserId = @UserId AND ResourceTypeId = @ResourceTypeId;

    DECLARE @NewBalance BIGINT;
    SELECT @NewBalance = Amount
    FROM PlayerResources
    WHERE UserId = @UserId AND ResourceTypeId = @ResourceTypeId;

    ----------------------------------------------------------------------
    -- 6. Olay gunlugu
    -- Her kazanc kaydedilir. "Bu oyuncu 3 saniyede 1 milyon kazanmis"
    -- sorgusunu ancak bu tabloyla yazabiliriz.
    ----------------------------------------------------------------------
    INSERT INTO Transactions (UserId, ResourceTypeId, Amount, BalanceAfter, Reason, ReferenceId, CreatedAt)
    VALUES (@UserId, @ResourceTypeId, @Gained, @NewBalance, N'CLICK', @FacilityTypeId, @Now);

    COMMIT TRANSACTION;

    ----------------------------------------------------------------------
    -- 7. Sonucu dondur
    -- NextAvailableAt: arayuz geri sayimi buna gore gosterir. Sunucu saatini
    -- de gonderiyoruz ki istemci kendi saatiyle arasindaki farki duzeltebilsin.
    ----------------------------------------------------------------------
    SELECT
        @Gained            AS Gained,
        @NewBalance        AS NewBalance,
        @ResourceTypeId    AS ResourceTypeId,
        DATEADD(SECOND, @CooldownSeconds, @Now) AS NextAvailableAt,
        @Now               AS ServerTime;

    RETURN 0;
END
GO

-- ############################################################################
-- BOLUM 3: sp_GetPlayerState — oyun ekraninin ihtiyaci olan her sey
--
-- Dort ayri sonuc kumesi (result set) donduruyoruz. Dapper'in QueryMultiple
-- metodu bunlari tek veritabani gidis-donusunde okur.
--
-- Neden dort ayri sorgu yerine tek SP? Her sorgu ayri bir ag gidis-donusu
-- demektir. Oyun ekrani sik yenilenecegi icin bunu tek cagriya indiriyoruz.
-- ############################################################################

CREATE OR ALTER PROCEDURE sp_GetPlayerState
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();

    -- --- 1) Kaynaklar ---
    SELECT
        rt.Id AS ResourceTypeId,
        rt.Code,
        rt.Name,
        pr.Amount,
        rt.SellValue,
        rt.IsCurrency
    FROM PlayerResources pr
    JOIN ResourceTypes rt ON rt.Id = pr.ResourceTypeId
    WHERE pr.UserId = @UserId
    ORDER BY rt.DisplayOrder;

    -- --- 2) Tesisler ---
    -- Bir sonraki seviyenin maliyeti ve suresi de geliyor: arayuz "Yukselt"
    -- butonunu bu bilgiyle cizecek (Gun 3).
    SELECT
        ft.Id AS FacilityTypeId,
        ft.Code,
        ft.Name,
        ft.MaxLevel,
        rt.Code AS ResourceCode,
        rt.Name AS ResourceName,
        pf.Level,
        fl.Production            AS CurrentProduction,
        nxt.Cost                 AS NextLevelCost,      -- son seviyedeyse NULL
        nxt.UpgradeMinutes       AS NextLevelMinutes,
        pf.UpgradeCompletesAt,
        pf.LastCollectedAt
    FROM PlayerFacilities pf
    JOIN FacilityTypes ft ON ft.Id = pf.FacilityTypeId
    JOIN ResourceTypes rt ON rt.Id = ft.ResourceTypeId
    JOIN FacilityLevels fl ON fl.FacilityTypeId = pf.FacilityTypeId AND fl.Level = pf.Level
    LEFT JOIN FacilityLevels nxt ON nxt.FacilityTypeId = pf.FacilityTypeId AND nxt.Level = pf.Level + 1
    WHERE pf.UserId = @UserId
    ORDER BY ft.DisplayOrder;

    -- --- 3) Tiklama turleri (acik olan + acilabilecek olanlar) ---
    SELECT
        ct.Id AS ClickTypeId,
        ct.Code,
        ct.Name,
        ct.CooldownSeconds,
        ct.YieldMultiplier,
        ct.UnlockCost,
        CAST(CASE WHEN pcu.UserId IS NULL THEN 0 ELSE 1 END AS BIT) AS IsUnlocked
    FROM ClickTypes ct
    LEFT JOIN PlayerClickUnlocks pcu
           ON pcu.ClickTypeId = ct.Id AND pcu.UserId = @UserId
    ORDER BY ct.DisplayOrder;

    -- --- 4) Tesis x tiklama bekleme durumlari ---
    -- Bekleme tesis bazlidir: Demir Ocagi'nda kazdiktan hemen sonra
    -- Altin Damari'nda da kazabilirsin.
    SELECT
        pfc.FacilityTypeId,
        pfc.ClickTypeId,
        pfc.LastClickAt,
        CASE
            WHEN pfc.LastClickAt IS NULL THEN @Now
            ELSE DATEADD(SECOND, ct.CooldownSeconds, pfc.LastClickAt)
        END AS NextAvailableAt
    FROM PlayerFacilityClicks pfc
    JOIN ClickTypes ct ON ct.Id = pfc.ClickTypeId
    WHERE pfc.UserId = @UserId;

    -- --- 5) Sunucu saati ---
    -- Istemcinin saati yanlis olabilir. Arayuz geri sayimi hesaplarken
    -- kendi saatiyle sunucu saati arasindaki farki duzeltmek icin bunu kullanir.
    SELECT @Now AS ServerTime;
END
GO

PRINT N'04_game_procedures.sql tamamlandi.';
GO
