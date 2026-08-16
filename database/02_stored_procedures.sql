-- ============================================================================
-- PROJE: MinerInMine
-- ADIM 2: Stored Procedure'ler (Tüm Veritabanı İşlemleri)
-- Neden Stored Procedure?
-- 1. SQL Injection saldırılarına karşı en yüksek korumayı sağlar.
-- 2. Sorgular veritabanında önceden derlendiği (pre-compiled) için daha hızlıdır.
-- 3. Ağ trafiğini azaltır (tek bir SP çağrısı ile birden fazla tablo güncellenir).
-- 4. İş mantığını ve transaction yönetimini veritabanı seviyesinde garanti eder.
--
-- !!! BU DOSYAYI ÇALIŞTIRIRKEN DİKKAT !!!
-- Dosya UTF-8 kodlamasındadır. sqlcmd varsayılan olarak ANSI kod sayfasıyla okur
-- ve Türkçe karakterler bozulur ("kullanıcı" -> "kullanÄ±cÄ±").
-- Bu yüzden -f 65001 (UTF-8 giriş kod sayfası) parametresi ZORUNLUDUR:
--
--   sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i 02_stored_procedures.sql
--
-- Ayrıca içerideki Türkçe metin sabitleri N'...' öneki ile Unicode olarak yazılır.
-- ============================================================================

USE MinerInMineDb;
GO

-- ============================================================================
-- 1. SP: sp_RegisterUser (Yeni Kullanıcı Kaydı - Transaction ile Atomik)
-- Açıklama: Kullanıcıyı ekler, 'Player' rolünü atar ve oyun profilini başlatır.
-- Herhangi biri başarısız olursa ROLLBACK yapılarak veritabanı tutarlı kalır.
-- ============================================================================
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

    -- Kullanıcı adı veya E-posta kontrolü
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
        -- 1. Users Tablosuna Ekleme
        INSERT INTO Users (Username, Email, PasswordHash, PasswordSalt, IsActive)
        VALUES (@Username, @Email, @PasswordHash, @PasswordSalt, 1);

        SET @NewUserId = SCOPE_IDENTITY();

        -- 2. Rol Bulma ve UserRoles Tablosuna Ekleme
        DECLARE @RoleId INT;
        SELECT @RoleId = Id FROM Roles WHERE Name = @RoleName;
        
        IF @RoleId IS NULL
        BEGIN
            SELECT @RoleId = Id FROM Roles WHERE Name = 'Player';
        END

        INSERT INTO UserRoles (UserId, RoleId)
        VALUES (@NewUserId, @RoleId);

        -- 3. Oyun Başlangıç Profili Oluşturma (MinerInMine)
        INSERT INTO PlayerProfiles (UserId, Level, Gold, MiningPower)
        VALUES (@NewUserId, 1, 100, 1);

        COMMIT TRANSACTION;
        RETURN 0; -- Başarılı
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SET @ErrorMessage = ERROR_MESSAGE();
        RETURN -99; -- Hata
    END CATCH
END
GO

-- ============================================================================
-- 2. SP: sp_GetUserByLogin (Kullanıcı Adı veya E-Posta ile Kullanıcı Getirme)
-- Açıklama: Giriş yaparken kullanıcının adı veya e-postası girildiğinde çalışır.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_GetUserByLogin
    @LoginInput NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        Id,
        Username,
        Email,
        PasswordHash,
        PasswordSalt,
        IsActive,
        CreatedAt,
        LastLoginAt
    FROM Users
    WHERE Username = @LoginInput OR Email = @LoginInput;
END
GO

-- ============================================================================
-- 3. SP: sp_GetUserRoles (Kullanıcının Rollerını Getirme)
-- Açıklama: JWT Token oluştururken kullanıcının rollerini (Claim) yüklemek için kullanılır.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_GetUserRoles
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        r.Id,
        r.Name,
        r.Description
    FROM Roles r
    INNER JOIN UserRoles ur ON r.Id = ur.RoleId
    WHERE ur.UserId = @UserId;
END
GO

-- ============================================================================
-- 4. SP: sp_SaveRefreshToken (Refresh Token Kaydetme)
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_SaveRefreshToken
    @UserId INT,
    @Token NVARCHAR(200),
    @ExpiresAt DATETIME2
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO RefreshTokens (UserId, Token, ExpiresAt)
    VALUES (@UserId, @Token, @ExpiresAt);
END
GO

-- ============================================================================
-- 5. SP: sp_GetRefreshToken (Refresh Token Doğrulama)
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_GetRefreshToken
    @Token NVARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        rt.Id,
        rt.UserId,
        rt.Token,
        rt.ExpiresAt,
        rt.CreatedAt,
        rt.RevokedAt,
        rt.ReplacedByToken,
        u.Username,
        u.Email,
        u.IsActive
    FROM RefreshTokens rt
    INNER JOIN Users u ON rt.UserId = u.Id
    WHERE rt.Token = @Token;
END
GO

-- ============================================================================
-- 6. SP: sp_RevokeRefreshToken (Token İptal Etme - Güvenli Çıkış)
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_RevokeRefreshToken
    @Token NVARCHAR(200),
    @ReplacedByToken NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE RefreshTokens
    SET RevokedAt = SYSUTCDATETIME(),
        ReplacedByToken = @ReplacedByToken
    WHERE Token = @Token AND RevokedAt IS NULL;
END
GO

-- ============================================================================
-- 7. SP: sp_UpdateLastLogin (Son Giriş Zamanını Güncelleme)
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_UpdateLastLogin
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE Users
    SET LastLoginAt = SYSUTCDATETIME()
    WHERE Id = @UserId;
END
GO
