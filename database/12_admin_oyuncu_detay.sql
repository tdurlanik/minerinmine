-- ============================================================================
-- PROJE: MinerInMine
-- ADIM 12: Yonetim Paneli - Oyuncu Detayi ve Yonetim Eylemleri
--
--   sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i 12_admin_oyuncu_detay.sql
--
-- NEDEN BU SCRIPT VAR?
-- Yonetim paneli su ana kadar yalnizca BAKIYORDU: oyuncu listesi ve supheli
-- kazanc listesi. Bir sikayet geldiginde "bu oyuncunun kaynaklari nereye gitti"
-- sorusunu cevaplayacak ekran yoktu — oysa Transactions gunlugu Gun 3'ten beri
-- tam da bunun icin tutuluyordu.
--
-- IKI KONU:
--   1. Tek oyuncunun tum durumunu okuyan detay prosedura
--   2. Yonetim EYLEMLERI (dondur, rol ver, oturum dusur) ve denetim izi
-- ============================================================================

USE MinerInMineDb;
GO

-- ============================================================================
-- 1. AdminActions — yonetim eylemleri denetim izi
--
-- NEDEN AYRI TABLO?
-- Kaynak duzeltmesi zaten Transactions'a yaziliyor (Reason = ADMIN_ADJUST,
-- islemi yapan admin ReferenceId'de). Ama "hesabi dondurdu", "rol verdi",
-- "oturumlarini dusurdu" gibi eylemlerin bir KAYNAK KARSILIGI YOK; Transactions
-- satiri ResourceTypeId ve Amount istiyor. Bu eylemleri oraya zorlamak tabloyu
-- kirletirdi.
--
-- SONRADAN EKLENEMEZ: "gecen ay bu hesabi kim dondurdu?" sorusunun cevabi,
-- ancak eylem anında yazildiysa vardir.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'AdminActions')
BEGIN
    CREATE TABLE AdminActions (
        Id BIGINT IDENTITY(1,1) PRIMARY KEY,
        AdminUserId INT NOT NULL,               -- eylemi YAPAN
        TargetUserId INT NOT NULL,              -- eylemin UYGULANDIGI
        Action NVARCHAR(30) NOT NULL,
        Detail NVARCHAR(200) NULL,              -- insan okuyacak kisa aciklama
        CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),

        CONSTRAINT FK_AdminActions_Admin
            FOREIGN KEY (AdminUserId) REFERENCES Users(Id),
        CONSTRAINT FK_AdminActions_Target
            FOREIGN KEY (TargetUserId) REFERENCES Users(Id),
        CONSTRAINT CK_AdminActions_Action CHECK (Action IN (
            N'DEACTIVATE', N'ACTIVATE', N'GRANT_ROLE', N'REVOKE_ROLE', N'REVOKE_SESSIONS'
        ))
    );

    CREATE NONCLUSTERED INDEX IX_AdminActions_Target_Date
        ON AdminActions(TargetUserId, CreatedAt DESC);
END
GO

-- ============================================================================
-- 2. sp_AdminGetPlayerDetail — tek oyuncunun tum durumu
--
-- BES SONUC KUMESI (Dapper QueryMultiple ile tek gidis-donuste okunur):
--   1) Kimlik + ozet   2) Kaynaklar   3) Tesisler   4) Madenciler
--   5) Son 50 islem (Transactions)
--
-- SIRA ONEMLIDIR: AdminRepository icindeki okuma sirasi birebir ayni olmali.
--
-- Neden 50 islem? Gunluk cok hizli buyur; "son ne oldu" sorusu icin 50 satir
-- yeter. Tamami gerekirse ayri, sayfalanan bir uc yazilir.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_AdminGetPlayerDetail
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;

    -- 1) Kimlik ve ozet
    SELECT
        u.Id AS UserId,
        u.Username,
        u.Email,
        u.IsActive,
        u.CreatedAt,
        u.LastLoginAt,
        STUFF((SELECT ', ' + r.Name FROM UserRoles ur JOIN Roles r ON r.Id = ur.RoleId
               WHERE ur.UserId = u.Id FOR XML PATH('')), 1, 2, '') AS Roles,

        ISNULL((SELECT SUM(pr.Amount * CASE WHEN rt.IsCurrency = 1 THEN 1 ELSE rt.SellValue END)
                FROM PlayerResources pr JOIN ResourceTypes rt ON rt.Id = pr.ResourceTypeId
                WHERE pr.UserId = u.Id), 0) AS TotalWealth,

        -- Acik oturum sayisi: iptal edilmemis ve suresi dolmamis refresh token'lar
        (SELECT COUNT(*) FROM RefreshTokens rtk
         WHERE rtk.UserId = u.Id AND rtk.RevokedAt IS NULL AND rtk.ExpiresAt > SYSUTCDATETIME())
            AS ActiveSessions,

        (SELECT COUNT(*) FROM Transactions t WHERE t.UserId = u.Id) AS TransactionCount
    FROM Users u
    WHERE u.Id = @UserId;

    -- 2) Kaynaklar
    SELECT rt.Id AS ResourceTypeId, rt.Code, rt.Name, pr.Amount, rt.IsCurrency, rt.SellValue
    FROM PlayerResources pr
    JOIN ResourceTypes rt ON rt.Id = pr.ResourceTypeId
    WHERE pr.UserId = @UserId
    ORDER BY rt.DisplayOrder;

    -- 3) Tesisler
    SELECT
        ft.Id AS FacilityTypeId,
        ft.Name AS FacilityName,
        pf.Level,
        ft.MaxLevel,
        rt.Name AS ResourceName,
        pf.UpgradeCompletesAt,
        ISNULL((SELECT SUM(pm.Count) FROM PlayerMiners pm
                WHERE pm.UserId = @UserId AND pm.FacilityTypeId = ft.Id), 0) AS MinerCount
    FROM PlayerFacilities pf
    JOIN FacilityTypes ft ON ft.Id = pf.FacilityTypeId
    JOIN ResourceTypes rt ON rt.Id = ft.ResourceTypeId
    WHERE pf.UserId = @UserId
    ORDER BY ft.DisplayOrder;

    -- 4) Madenciler (yalnizca ise alinmis olanlar)
    SELECT
        mt.Id AS MinerTypeId,
        mt.Name AS MinerName,
        ft.Name AS FacilityName,
        pm.Count
    FROM PlayerMiners pm
    JOIN MinerTypes mt ON mt.Id = pm.MinerTypeId
    JOIN FacilityTypes ft ON ft.Id = pm.FacilityTypeId
    WHERE pm.UserId = @UserId AND pm.Count > 0
    ORDER BY ft.DisplayOrder, mt.DisplayOrder;

    -- 5) Son 50 islem — "kaynaklarin nereye gitti" sorusunun cevabi
    SELECT TOP (50)
        t.Id,
        rt.Name AS ResourceName,
        t.Amount,
        t.BalanceAfter,
        t.Reason,
        t.ReferenceId,
        t.CreatedAt
    FROM Transactions t
    JOIN ResourceTypes rt ON rt.Id = t.ResourceTypeId
    WHERE t.UserId = @UserId
    ORDER BY t.CreatedAt DESC, t.Id DESC;
END
GO

-- ============================================================================
-- 3. sp_AdminSetActive — hesabi dondur / ac
--
-- KALICI SILME YOK. Users.IsActive = 0 yeterlidir:
--   - Transactions gecmisi durur, hile tespiti calismaya devam eder
--   - Yanlislikla dondurulan hesap geri acilabilir
--   - Siralamadaki gecmis kayitlar tutarli kalir
--
-- IKI KORUMA (veritabaninda, arayuzde degil):
--   1. Admin kendi hesabini donduramaz  -> kendini kilitleyemez
--   2. Hesap dondurulurken acik oturumlar da dusurulur -> elindeki refresh
--      token'la oyuna devam edemesin. Aksi halde "dondurdum ama hala oynuyor"
--      olurdu: access token 15 dakika daha gecerli, refresh token 7 gun.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_AdminSetActive
    @AdminUserId INT,
    @TargetUserId INT,
    @IsActive BIT,
    @ErrorMessage NVARCHAR(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ErrorMessage = NULL;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();

    IF @AdminUserId = @TargetUserId
    BEGIN
        SET @ErrorMessage = N'Kendi hesabinizin durumunu degistiremezsiniz.';
        RETURN -1;
    END

    IF NOT EXISTS (SELECT 1 FROM Users WHERE Id = @TargetUserId)
    BEGIN
        SET @ErrorMessage = N'Oyuncu bulunamadi.';
        RETURN -2;
    END

    BEGIN TRANSACTION;

    -- Kosulu WHERE'e gomuyoruz: durum zaten istenen degerdeyse @@ROWCOUNT = 0
    -- olur ve gereksiz denetim izi kaydi olusmaz.
    UPDATE Users SET IsActive = @IsActive
    WHERE Id = @TargetUserId AND IsActive <> @IsActive;

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK TRANSACTION;
        SET @ErrorMessage = N'Hesap zaten bu durumda.';
        RETURN -3;
    END

    DECLARE @RevokedSessions INT = 0;

    IF @IsActive = 0
    BEGIN
        UPDATE RefreshTokens SET RevokedAt = @Now
        WHERE UserId = @TargetUserId AND RevokedAt IS NULL AND ExpiresAt > @Now;
        SET @RevokedSessions = @@ROWCOUNT;
    END

    INSERT INTO AdminActions (AdminUserId, TargetUserId, Action, Detail, CreatedAt)
    VALUES (@AdminUserId, @TargetUserId,
            CASE WHEN @IsActive = 1 THEN N'ACTIVATE' ELSE N'DEACTIVATE' END,
            CASE WHEN @IsActive = 1 THEN N'Hesap yeniden acildi.'
                 ELSE N'Hesap donduruldu, ' + CAST(@RevokedSessions AS NVARCHAR(10)) + N' oturum dusuruldu.'
            END,
            @Now);

    COMMIT TRANSACTION;

    SELECT @IsActive AS IsActive, @RevokedSessions AS RevokedSessions, @Now AS ServerTime;
    RETURN 0;
END
GO

-- ============================================================================
-- 4. sp_AdminSetRole — rol ver / al
--
-- UC KORUMA:
--   1. Admin kendi rolunu degistiremez (kendini yetkisiz birakamaz)
--   2. SISTEMDEKI SON ADMIN'IN rolu alinamaz -> sistem yonetimsiz kalmaz.
--      Bu kontrol UPDATE degil SELECT ... COUNT ile yapiliyor ve transaction
--      icinde; iki admin es zamanda birbirinin rolunu almaya calisirsa
--      ikincisi bu kontrole takilir.
--   3. Rol adi Roles tablosunda olmali (yazim hatasiyla hayali rol olusmasin)
--
-- MERGE degil INSERT/DELETE: islem yonu (ver/al) zaten parametrede belli.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_AdminSetRole
    @AdminUserId INT,
    @TargetUserId INT,
    @RoleName NVARCHAR(50),
    @Grant BIT,                      -- 1 = rolu ver, 0 = rolu al
    @ErrorMessage NVARCHAR(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ErrorMessage = NULL;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();

    IF @AdminUserId = @TargetUserId
    BEGIN
        SET @ErrorMessage = N'Kendi rolunuzu degistiremezsiniz.';
        RETURN -1;
    END

    DECLARE @RoleId INT = (SELECT Id FROM Roles WHERE Name = @RoleName);

    IF @RoleId IS NULL
    BEGIN
        SET @ErrorMessage = N'Boyle bir rol yok: ' + @RoleName;
        RETURN -2;
    END

    IF NOT EXISTS (SELECT 1 FROM Users WHERE Id = @TargetUserId)
    BEGIN
        SET @ErrorMessage = N'Oyuncu bulunamadi.';
        RETURN -3;
    END

    BEGIN TRANSACTION;

    IF @Grant = 1
    BEGIN
        -- Zaten varsa tekrar ekleme (birincil anahtar zaten engellerdi,
        -- ama hata firlatmak yerine sessizce gecmek daha dogru).
        INSERT INTO UserRoles (UserId, RoleId, AssignedAt)
        SELECT @TargetUserId, @RoleId, @Now
        WHERE NOT EXISTS (SELECT 1 FROM UserRoles WHERE UserId = @TargetUserId AND RoleId = @RoleId);
    END
    ELSE
    BEGIN
        -- Son admin korumasi
        IF @RoleName = N'Admin'
        BEGIN
            DECLARE @AdminSayisi INT = (
                SELECT COUNT(*) FROM UserRoles ur
                JOIN Users u ON u.Id = ur.UserId
                WHERE ur.RoleId = @RoleId AND u.IsActive = 1
            );

            IF @AdminSayisi <= 1
            BEGIN
                ROLLBACK TRANSACTION;
                SET @ErrorMessage = N'Sistemdeki son yoneticinin rolu alinamaz.';
                RETURN -4;
            END
        END

        DELETE FROM UserRoles WHERE UserId = @TargetUserId AND RoleId = @RoleId;
    END

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK TRANSACTION;
        SET @ErrorMessage = N'Rol zaten bu durumda.';
        RETURN -5;
    END

    INSERT INTO AdminActions (AdminUserId, TargetUserId, Action, Detail, CreatedAt)
    VALUES (@AdminUserId, @TargetUserId,
            CASE WHEN @Grant = 1 THEN N'GRANT_ROLE' ELSE N'REVOKE_ROLE' END,
            @RoleName, @Now);

    COMMIT TRANSACTION;

    SELECT @RoleName AS RoleName, @Grant AS IsGranted, @Now AS ServerTime;
    RETURN 0;
END
GO

-- ============================================================================
-- 5. sp_AdminRevokeSessions — oyuncunun tum oturumlarini dusur
--
-- Hesabi dondurmadan "cikis yaptir": sifresi calinmis olabilecek bir oyuncu
-- icin dogru mudahale. Refresh token'lar iptal edilir; elindeki access token
-- en fazla 15 dakika daha calisir, sonrasinda yenileyemez.
--
-- Token'lar SILINMIYOR, RevokedAt isaretleniyor: iptal edilmis bir token
-- tekrar kullanilmaya calisilirsa bunu gorebilelim (token hirsizligi belirtisi).
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_AdminRevokeSessions
    @AdminUserId INT,
    @TargetUserId INT,
    @ErrorMessage NVARCHAR(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ErrorMessage = NULL;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();

    IF NOT EXISTS (SELECT 1 FROM Users WHERE Id = @TargetUserId)
    BEGIN
        SET @ErrorMessage = N'Oyuncu bulunamadi.';
        RETURN -1;
    END

    BEGIN TRANSACTION;

    UPDATE RefreshTokens SET RevokedAt = @Now
    WHERE UserId = @TargetUserId AND RevokedAt IS NULL AND ExpiresAt > @Now;

    DECLARE @Sayi INT = @@ROWCOUNT;

    INSERT INTO AdminActions (AdminUserId, TargetUserId, Action, Detail, CreatedAt)
    VALUES (@AdminUserId, @TargetUserId, N'REVOKE_SESSIONS',
            CAST(@Sayi AS NVARCHAR(10)) + N' oturum dusuruldu.', @Now);

    COMMIT TRANSACTION;

    SELECT @Sayi AS RevokedSessions, @Now AS ServerTime;
    RETURN 0;
END
GO

PRINT '12_admin_oyuncu_detay.sql tamamlandi. AdminActions + 4 prosedur hazir.';
GO
