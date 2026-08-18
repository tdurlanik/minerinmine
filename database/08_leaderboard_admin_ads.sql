-- ============================================================================
-- PROJE: MinerInMine
-- ADIM 8: Leaderboard, Admin Paneli ve Reklam Odulu (v1 tamamlanisi)
--
--   sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i 08_leaderboard_admin_ads.sql
--
-- UC KONU:
--   1. Siralama sorgulari ve pencere fonksiyonlari (RANK)
--   2. Rol bazli yonetim islemleri ve denetim izi
--   3. Reklam odulunun neden istemciye BIRAKILAMAYACAGI (SSV)
-- ============================================================================

USE MinerInMineDb;
GO

-- ============================================================================
-- 1. AdRewardClaims — reklam odulu talepleri
--
-- NEDEN AYRI TABLO? TEKRAR ODEMEYI ONLEMEK ICIN.
--
-- Reklam agi (AdMob, Unity Ads) izleme bittiginde sunucumuza bir bildirim
-- gonderir. Ag hatasi olursa AYNI bildirimi tekrar gonderebilir — bu normaldir
-- ve "at least once delivery" denir. Odulu her bildirimde versek oyuncu ayni
-- reklamdan defalarca kazanirdi.
--
-- Cozum: her bildirimin benzersiz bir islem kimligi (TransactionId) vardir ve
-- bunu BIRINCIL ANAHTAR yapariz. Ayni kimlik ikinci kez gelirse veritabani
-- reddeder. Bu ozellige IDEMPOTENCY (ayni istegi tekrarlamanin zarar vermemesi)
-- denir ve odeme/odul sistemlerinin temel gereksinimidir.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'AdRewardClaims')
BEGIN
    CREATE TABLE AdRewardClaims (
        TransactionId NVARCHAR(100) NOT NULL PRIMARY KEY,   -- reklam aginin verdigi benzersiz kimlik
        UserId INT NOT NULL,
        Amount BIGINT NOT NULL,
        CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),

        CONSTRAINT FK_AdRewardClaims_Users
            FOREIGN KEY (UserId) REFERENCES Users(Id) ON DELETE CASCADE,
        CONSTRAINT CK_AdRewardClaims_Amount CHECK (Amount > 0)
    );

    CREATE NONCLUSTERED INDEX IX_AdRewardClaims_User_Date
        ON AdRewardClaims(UserId, CreatedAt DESC);
END
GO

MERGE INTO GameSettings AS h
USING (VALUES
    (N'AD_REWARD_KRISTAL', N'250', N'Bir reklam izlemenin kazandirdigi Kristal'),
    (N'AD_DAILY_LIMIT', N'20', N'Gunde en fazla kac reklam odulu alinabilecegi')
) AS k (SettingKey, SettingValue, Description)
    ON h.SettingKey = k.SettingKey
WHEN MATCHED THEN UPDATE SET h.SettingValue = k.SettingValue, h.Description = k.Description
WHEN NOT MATCHED THEN INSERT (SettingKey, SettingValue, Description)
    VALUES (k.SettingKey, k.SettingValue, k.Description);
GO

-- ============================================================================
-- 2. Leaderboard icin indeks
--
-- Siralama sorgusu TUM oyuncularin TUM kaynaklarini toplar. Bu, PlayerResources
-- tablosunun tamamini taramak demektir.
--
-- Asagidaki indeks "kapsayici" (covering) bir indekstir: sorgunun ihtiyac duydugu
-- tum sutunlari icerdigi icin SQL Server ana tabloya hic gitmez. Satirlar daha
-- dar oldugundan ayni sayfa sayisinda daha cok satir okunur.
--
-- DURUSTCE: Bu indeks taramayi hizlandirir ama ORTADAN KALDIRMAZ. Oyuncu sayisi
-- yuz binlere ciktiginda dogru cozum, siralamayi her istekte hesaplamak yerine
-- periyodik olarak bir ozet tabloya yazmaktir (materialized view / snapshot).
-- Bu projenin olcegi icin canli hesap fazlasiyla yeterli.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_PlayerResources_Leaderboard')
BEGIN
    CREATE NONCLUSTERED INDEX IX_PlayerResources_Leaderboard
        ON PlayerResources(ResourceTypeId)
        INCLUDE (UserId, Amount);
END
GO

-- ============================================================================
-- 3. sp_GetLeaderboard — servet siralamasi
--
-- SERVET = Kristal + (her madenin miktari x birim degeri)
-- Boylece madenini satmamis oyuncu da hak ettigi yerde gorunur.
--
-- RANK() PENCERE FONKSIYONU (window function)
-- Siradan bir ORDER BY sadece siralar; RANK() her satira SIRA NUMARASI verir.
--   RANK()       : esitlikte ayni numara, sonraki numara atlanir (1,2,2,4)
--   DENSE_RANK() : esitlikte ayni numara, atlama yok             (1,2,2,3)
--   ROW_NUMBER() : esitlik olsa bile herkese farkli numara       (1,2,3,4)
-- Servette esitlik olabilecegi icin RANK dogru secim.
--
-- Iki sonuc kumesi doner: ilk N oyuncu ve istekte bulunan oyuncunun kendi sirasi.
-- Oyuncu ilk 100'de degilse bile kacinci oldugunu gorebilsin diye.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_GetLeaderboard
    @UserId INT,
    @Top INT = 25
AS
BEGIN
    SET NOCOUNT ON;

    -- Once herkesin servetini hesapla ve sirala.
    -- CTE (Common Table Expression): sorguyu adimlara bolup okunakli kilar.
    WITH Servet AS (
        SELECT
            pr.UserId,
            SUM(pr.Amount * CASE WHEN rt.IsCurrency = 1 THEN 1 ELSE rt.SellValue END) AS TotalWealth
        FROM PlayerResources pr
        JOIN ResourceTypes rt ON rt.Id = pr.ResourceTypeId
        GROUP BY pr.UserId
    ),
    Sirali AS (
        SELECT
            s.UserId,
            s.TotalWealth,
            RANK() OVER (ORDER BY s.TotalWealth DESC) AS Position
        FROM Servet s
    )
    SELECT TOP (@Top)
        sr.Position,
        u.Username,
        sr.TotalWealth,
        (SELECT ISNULL(SUM(pf.Level), 0) FROM PlayerFacilities pf WHERE pf.UserId = sr.UserId) AS TotalLevels,
        (SELECT ISNULL(SUM(pm.Count), 0) FROM PlayerMiners pm WHERE pm.UserId = sr.UserId) AS TotalMiners,
        CAST(CASE WHEN sr.UserId = @UserId THEN 1 ELSE 0 END AS BIT) AS IsMe
    FROM Sirali sr
    JOIN Users u ON u.Id = sr.UserId
    WHERE u.IsActive = 1
    ORDER BY sr.Position;

    -- Istekte bulunan oyuncunun kendi sirasi (ilk N'de olmasa bile)
    WITH Servet AS (
        SELECT pr.UserId,
               SUM(pr.Amount * CASE WHEN rt.IsCurrency = 1 THEN 1 ELSE rt.SellValue END) AS TotalWealth
        FROM PlayerResources pr
        JOIN ResourceTypes rt ON rt.Id = pr.ResourceTypeId
        GROUP BY pr.UserId
    ),
    Sirali AS (
        SELECT s.UserId, s.TotalWealth, RANK() OVER (ORDER BY s.TotalWealth DESC) AS Position
        FROM Servet s
    )
    SELECT sr.Position, u.Username, sr.TotalWealth,
           (SELECT COUNT(*) FROM Users WHERE IsActive = 1) AS TotalPlayers
    FROM Sirali sr
    JOIN Users u ON u.Id = sr.UserId
    WHERE sr.UserId = @UserId;
END
GO

-- ============================================================================
-- 4. sp_GrantAdReward — reklam odulu yatir (IDEMPOTENT)
--
-- Bu SP'nin en onemli ozelligi: AYNI @TransactionId ile ikinci kez cagrilirsa
-- odul TEKRAR VERILMEZ ve hata da donmez, sadece "zaten islenmis" bilgisi doner.
--
-- Neden hata dondurmuyoruz? Cunku tekrar gonderim reklam aginin NORMAL
-- davranisidir; hata donersek ag tekrar tekrar denemeye devam eder.
-- Dogru cevap "bu istegi zaten isledim, her sey yolunda"dir.
--
-- Gunluk limit de burada kontrol edilir: istemci "sinira ulastim" demez,
-- sunucu sayar.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_GrantAdReward
    @UserId INT,
    @TransactionId NVARCHAR(100),
    @ErrorMessage NVARCHAR(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ErrorMessage = NULL;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();

    -- Bu bildirim daha once islendi mi?
    IF EXISTS (SELECT 1 FROM AdRewardClaims WHERE TransactionId = @TransactionId)
    BEGIN
        SELECT CAST(1 AS BIT) AS AlreadyProcessed, 0 AS Amount,
               (SELECT Amount FROM PlayerResources
                WHERE UserId = @UserId
                  AND ResourceTypeId = (SELECT Id FROM ResourceTypes WHERE Code = N'KRISTAL')) AS NewBalance,
               @Now AS ServerTime;
        RETURN 0;
    END

    IF NOT EXISTS (SELECT 1 FROM Users WHERE Id = @UserId AND IsActive = 1)
    BEGIN
        SET @ErrorMessage = N'Kullanici bulunamadi veya devre disi.';
        RETURN -1;
    END

    DECLARE @Reward BIGINT =
        (SELECT CAST(SettingValue AS BIGINT) FROM GameSettings WHERE SettingKey = N'AD_REWARD_KRISTAL');
    DECLARE @DailyLimit INT =
        (SELECT CAST(SettingValue AS INT) FROM GameSettings WHERE SettingKey = N'AD_DAILY_LIMIT');

    DECLARE @Today INT =
        (SELECT COUNT(*) FROM AdRewardClaims
         WHERE UserId = @UserId AND CreatedAt >= DATEADD(HOUR, -24, @Now));

    IF @Today >= @DailyLimit
    BEGIN
        SET @ErrorMessage = N'Gunluk reklam odulu sinirina ulastiniz.';
        RETURN -2;
    END

    DECLARE @KristalId INT = (SELECT Id FROM ResourceTypes WHERE Code = N'KRISTAL');

    BEGIN TRANSACTION;
    BEGIN TRY
        -- Once talebi kaydet. Ayni anda iki ayni bildirim gelirse ikincisi
        -- BIRINCIL ANAHTAR ihlaline duser ve CATCH blogunda yakalanir.
        INSERT INTO AdRewardClaims (TransactionId, UserId, Amount, CreatedAt)
        VALUES (@TransactionId, @UserId, @Reward, @Now);

        UPDATE PlayerResources
        SET Amount = Amount + @Reward, UpdatedAt = @Now
        WHERE UserId = @UserId AND ResourceTypeId = @KristalId;

        DECLARE @NewBalance BIGINT =
            (SELECT Amount FROM PlayerResources WHERE UserId = @UserId AND ResourceTypeId = @KristalId);

        INSERT INTO Transactions (UserId, ResourceTypeId, Amount, BalanceAfter, Reason, ReferenceId, CreatedAt)
        VALUES (@UserId, @KristalId, @Reward, @NewBalance, N'AD_REWARD', NULL, @Now);

        COMMIT TRANSACTION;

        SELECT CAST(0 AS BIT) AS AlreadyProcessed, @Reward AS Amount,
               @NewBalance AS NewBalance, @Now AS ServerTime;
        RETURN 0;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        -- 2627 = birincil anahtar ihlali: ayni bildirim es zamanli geldi.
        -- Bu bir hata degil, idempotency'nin calistiginin isareti.
        IF ERROR_NUMBER() = 2627
        BEGIN
            SELECT CAST(1 AS BIT) AS AlreadyProcessed, 0 AS Amount,
                   (SELECT Amount FROM PlayerResources
                    WHERE UserId = @UserId AND ResourceTypeId = @KristalId) AS NewBalance,
                   @Now AS ServerTime;
            RETURN 0;
        END

        SET @ErrorMessage = ERROR_MESSAGE();
        RETURN -99;
    END CATCH
END
GO

-- ============================================================================
-- 5. sp_AdminGetPlayers — oyuncu listesi (arama + sayfalama)
--
-- SAYFALAMA NEDEN ONEMLI?
-- 10.000 oyuncuyu tek seferde dondurmek hem veritabanini hem agi hem tarayiciyi
-- bogar. OFFSET/FETCH ile yalnizca istenen sayfa okunur.
--
-- DIKKAT: OFFSET buyudukce yavaslar (1000. sayfa icin oncesindeki tum satirlar
-- taranir). Sonsuz kaydirmalarda "keyset pagination" (son gorulen Id'den devam)
-- tercih edilir. Admin panelinde sayfa numarasi gerektigi icin OFFSET uygundur.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_AdminGetPlayers
    @Search NVARCHAR(100) = NULL,
    @Page INT = 1,
    @PageSize INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    IF @Page < 1 SET @Page = 1;
    IF @PageSize < 1 OR @PageSize > 100 SET @PageSize = 20;

    DECLARE @KristalId INT = (SELECT Id FROM ResourceTypes WHERE Code = N'KRISTAL');

    SELECT
        u.Id AS UserId,
        u.Username,
        u.Email,
        u.IsActive,
        u.CreatedAt,
        u.LastLoginAt,
        ISNULL((SELECT SUM(pr.Amount * CASE WHEN rt.IsCurrency = 1 THEN 1 ELSE rt.SellValue END)
                FROM PlayerResources pr JOIN ResourceTypes rt ON rt.Id = pr.ResourceTypeId
                WHERE pr.UserId = u.Id), 0) AS TotalWealth,
        ISNULL((SELECT Amount FROM PlayerResources
                WHERE UserId = u.Id AND ResourceTypeId = @KristalId), 0) AS Kristal,
        ISNULL((SELECT SUM(Level) FROM PlayerFacilities WHERE UserId = u.Id), 0) AS TotalLevels,
        ISNULL((SELECT SUM(Count) FROM PlayerMiners WHERE UserId = u.Id), 0) AS TotalMiners,
        STUFF((SELECT ', ' + r.Name FROM UserRoles ur JOIN Roles r ON r.Id = ur.RoleId
               WHERE ur.UserId = u.Id FOR XML PATH('')), 1, 2, '') AS Roles
    FROM Users u
    WHERE (@Search IS NULL OR u.Username LIKE '%' + @Search + '%' OR u.Email LIKE '%' + @Search + '%')
    ORDER BY u.Id
    OFFSET (@Page - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;

    -- Toplam kayit sayisi: arayuz kac sayfa oldugunu bilsin diye
    SELECT COUNT(*) AS TotalCount
    FROM Users u
    WHERE (@Search IS NULL OR u.Username LIKE '%' + @Search + '%' OR u.Email LIKE '%' + @Search + '%');
END
GO

-- ============================================================================
-- 6. sp_AdminAdjustResource — oyuncunun kaynagini duzelt
--
-- Destek talebi ("kaynagim kayboldu") veya test amaciyla kullanilir.
--
-- HER ISLEM GUNLUGE YAZILIR (Reason = ADMIN_ADJUST) ve hangi adminin yaptigi
-- ReferenceId'de tutulur. Yonetici yetkisi denetlenebilir olmalidir; aksi halde
-- "kim verdi bu kaynagi?" sorusu cevapsiz kalir. Buna DENETIM IZI (audit trail) denir.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_AdminAdjustResource
    @AdminUserId INT,
    @TargetUserId INT,
    @ResourceTypeId INT,
    @Delta BIGINT,
    @ErrorMessage NVARCHAR(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ErrorMessage = NULL;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();

    IF @Delta = 0
    BEGIN
        SET @ErrorMessage = N'Degisim miktari sifir olamaz.';
        RETURN -1;
    END

    IF NOT EXISTS (SELECT 1 FROM PlayerResources WHERE UserId = @TargetUserId AND ResourceTypeId = @ResourceTypeId)
    BEGIN
        SET @ErrorMessage = N'Oyuncu veya kaynak bulunamadi.';
        RETURN -2;
    END

    BEGIN TRANSACTION;

    -- Eksiltme yapiliyorsa bakiye yetmeli: negatif bakiye olusmasin.
    UPDATE PlayerResources
    SET Amount = Amount + @Delta, UpdatedAt = @Now
    WHERE UserId = @TargetUserId
      AND ResourceTypeId = @ResourceTypeId
      AND Amount + @Delta >= 0;

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK TRANSACTION;
        SET @ErrorMessage = N'Islem bakiyeyi negatife dusururdu.';
        RETURN -3;
    END

    DECLARE @NewBalance BIGINT =
        (SELECT Amount FROM PlayerResources WHERE UserId = @TargetUserId AND ResourceTypeId = @ResourceTypeId);

    INSERT INTO Transactions (UserId, ResourceTypeId, Amount, BalanceAfter, Reason, ReferenceId, CreatedAt)
    VALUES (@TargetUserId, @ResourceTypeId, @Delta, @NewBalance, N'ADMIN_ADJUST', @AdminUserId, @Now);

    COMMIT TRANSACTION;

    SELECT @NewBalance AS NewBalance, @Delta AS Delta, @Now AS ServerTime;
    RETURN 0;
END
GO

-- ============================================================================
-- 7. sp_AdminGetSuspicious — supheli kazanc taramasi
--
-- Transactions tablosunu en bastan tuttugumuz icin bu sorgu mumkun.
-- Kisa surede olagandisi kazanc elde eden oyuncular listelenir.
--
-- Gercek bir hile tespiti degil, bir ISARET listesi: yuksek kazanc mesru de
-- olabilir. Amac, incelenecek hesaplari daraltmak.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_AdminGetSuspicious
    @Minutes INT = 60,
    @MinGain BIGINT = 100000
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 50
        u.Id AS UserId,
        u.Username,
        rt.Code AS ResourceCode,
        SUM(t.Amount) AS Gain,
        COUNT(*) AS TransactionCount,
        MIN(t.CreatedAt) AS FirstAt,
        MAX(t.CreatedAt) AS LastAt
    FROM Transactions t
    JOIN Users u ON u.Id = t.UserId
    JOIN ResourceTypes rt ON rt.Id = t.ResourceTypeId
    WHERE t.CreatedAt >= DATEADD(MINUTE, -@Minutes, SYSUTCDATETIME())
      AND t.Amount > 0
      AND t.Reason <> N'ADMIN_ADJUST'
    GROUP BY u.Id, u.Username, rt.Code
    HAVING SUM(t.Amount) >= @MinGain
    ORDER BY SUM(t.Amount) DESC;
END
GO

PRINT N'08_leaderboard_admin_ads.sql tamamlandi.';
GO
