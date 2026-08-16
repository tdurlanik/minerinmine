-- ============================================================================
-- PROJE: MinerInMine
-- ADIM 1: Veritabanı ve Tabloların Oluşturulması (3NF Normalizasyon)
-- ============================================================================

-- 1. Veritabanı Yoksa Oluştur
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'MinerInMineDb')
BEGIN
    CREATE DATABASE MinerInMineDb;
END
GO

USE MinerInMineDb;
GO

-- ============================================================================
-- TABLO 1: Roles (Sistemdeki Roller)
-- Normalizasyon Açıklaması:
-- Rol isimlerini her kullanıcının yanına string olarak yazmak (örn: "Admin", "Player")
-- veri tekrarına (redundancy) ve yazım hatalarına yol açar. Bu yüzden roller ayrı tabloda tutulur.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Roles')
BEGIN
    CREATE TABLE Roles (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        Name NVARCHAR(50) NOT NULL UNIQUE,          -- 'Admin', 'Player', 'Moderator'
        Description NVARCHAR(200) NULL,
        CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
END
GO

-- ============================================================================
-- TABLO 2: Users (Kullanıcı Temel Bilgileri)
-- Normalizasyon Açıklaması:
-- Şifreler ASLA açık metin (plaintext) saklanmaz!
-- PasswordHash: Şifrenin tek yönlü şifrelenmiş hali.
-- PasswordSalt: Her kullanıcı için rastgele üretilen tuzlama anahtarı (Rainbow table saldırılarını engeller).
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Users')
BEGIN
    CREATE TABLE Users (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        Username NVARCHAR(50) NOT NULL UNIQUE,
        Email NVARCHAR(100) NOT NULL UNIQUE,
        PasswordHash NVARCHAR(256) NOT NULL,
        PasswordSalt NVARCHAR(256) NOT NULL,
        IsActive BIT NOT NULL DEFAULT 1,
        CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        LastLoginAt DATETIME2 NULL
    );

    -- Hızlı arama için indexler
    CREATE NONCLUSTERED INDEX IX_Users_Username ON Users(Username);
    CREATE NONCLUSTERED INDEX IX_Users_Email ON Users(Email);
END
GO

-- ============================================================================
-- TABLO 3: UserRoles (Kullanıcı-Rol İlişkisi / Many-to-Many)
-- Normalizasyon Açıklaması (3NF):
-- Bir kullanıcının birden fazla rolü olabilir, bir rol birden fazla kullanıcıya verilebilir.
-- Bu ilişki köprü tablo (Junction Table) ile çözülür.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'UserRoles')
BEGIN
    CREATE TABLE UserRoles (
        UserId INT NOT NULL,
        RoleId INT NOT NULL,
        AssignedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        
        CONSTRAINT PK_UserRoles PRIMARY KEY (UserId, RoleId),
        CONSTRAINT FK_UserRoles_Users FOREIGN KEY (UserId) REFERENCES Users(Id) ON DELETE CASCADE,
        CONSTRAINT FK_UserRoles_Roles FOREIGN KEY (RoleId) REFERENCES Roles(Id) ON DELETE CASCADE
    );
END
GO

-- ============================================================================
-- TABLO 4: RefreshTokens (Güvenli Uzun Süreli Oturum Yönetimi)
-- Normalizasyon Açıklaması:
-- JWT Access Token süresi dolduğunda kullanıcının tekrar şifre girmeden yeni token
-- almasını sağlar. İptal edilen veya süresi dolan tokenlar burada takip edilir.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'RefreshTokens')
BEGIN
    CREATE TABLE RefreshTokens (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        UserId INT NOT NULL,
        Token NVARCHAR(200) NOT NULL UNIQUE,
        ExpiresAt DATETIME2 NOT NULL,
        CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        RevokedAt DATETIME2 NULL,
        ReplacedByToken NVARCHAR(200) NULL,
        
        CONSTRAINT FK_RefreshTokens_Users FOREIGN KEY (UserId) REFERENCES Users(Id) ON DELETE CASCADE
    );

    CREATE NONCLUSTERED INDEX IX_RefreshTokens_Token ON RefreshTokens(Token);
END
GO

-- ============================================================================
-- TABLO 5: PlayerProfiles (MinerInMine Oyun Verisi - 1:1 İlişki)
-- Normalizasyon Açıklaması:
-- Kullanıcı kimlik doğrulama verileri ile oyun mekaniği verileri ayrıştırılmıştır.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'PlayerProfiles')
BEGIN
    CREATE TABLE PlayerProfiles (
        UserId INT PRIMARY KEY,
        Level INT NOT NULL DEFAULT 1,
        Gold BIGINT NOT NULL DEFAULT 100,            -- Başlangıç altını
        MiningPower INT NOT NULL DEFAULT 1,          -- Saniyede kazım gücü
        LastMinedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        
        CONSTRAINT FK_PlayerProfiles_Users FOREIGN KEY (UserId) REFERENCES Users(Id) ON DELETE CASCADE
    );
END
GO

-- ============================================================================
-- VARSAYILAN ROLLERİN EKLENMESİ (Seed Data)
--
-- ÖNEMLİ - N ÖNEKİ:
-- 'Moderatör' yerine N'Moderatör' yazıyoruz. N öneki olmayan bir metin sabiti
-- SQL Server tarafından önce VARCHAR (tek byte) olarak yorumlanır ve sunucunun
-- kod sayfasına çevrilir; NVARCHAR kolona ancak ondan sonra yazılır. Bu ara
-- çevrimde Türkçe karakterler bozulabilir. N öneki metni doğrudan Unicode yapar.
--
-- Blok "ekle VEYA güncelle" şeklinde yazıldı: script tekrar tekrar çalıştırılabilir
-- (idempotent) ve daha önce bozuk yazılmış açıklamaları kendi kendine düzeltir.
-- ============================================================================
MERGE INTO Roles AS hedef
USING (VALUES
    (N'Admin',     N'Sistem Yöneticisi - Tüm yetkilere sahiptir'),
    (N'Player',    N'Standart Oyuncu - Oyunu oynama yetkisine sahiptir'),
    (N'Moderator', N'Moderatör - Oyuncu denetleme yetkisine sahiptir')
) AS kaynak (Name, Description)
    ON hedef.Name = kaynak.Name
WHEN MATCHED THEN
    UPDATE SET hedef.Description = kaynak.Description
WHEN NOT MATCHED THEN
    INSERT (Name, Description) VALUES (kaynak.Name, kaynak.Description);
GO
