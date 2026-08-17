-- ============================================================================
-- PROJE: MinerInMine
-- ADIM 3: Oyun Mekaniği Tabloları
--
-- !!! CALISTIRMA SEKLI !!!
--   sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i 03_game_tables.sql
-- -f 65001 (UTF-8) olmadan Turkce karakterler bozulur.
--
-- TEMEL TASARIM KURALI: KATALOG vs OYUNCU DURUMU
--
-- Bu dosyadaki tablolar iki gruba ayrilir:
--
--   1) KATALOG (...Types)  : Oyunu TASARIMCI belirler. Tum oyuncular icin aynidir.
--                            "Demir Ocagi diye bir tesis vardir, temel uretimi 1'dir."
--                            10 oyuncu da olsa 10.000 oyuncu da olsa 3 satirdir.
--
--   2) OYUNCU DURUMU (Player...) : Oyuncu OYNAYARAK olusturur.
--                            "Tayfur'un Demir Ocagi 4. seviyede."
--                            Oyuncu x tesis kadar satirdir.
--
-- Neden ayiriyoruz? Dengeyi degistirmek istedigimizde (uretim cok yavas) katalogda
-- TEK SATIR guncelleriz; 10.000 oyuncunun satirina dokunmayiz.
-- ============================================================================

USE MinerInMineDb;
GO

-- ############################################################################
-- BOLUM 1: KATALOG TABLOLARI
-- ############################################################################

-- ============================================================================
-- 1.1 ResourceTypes — Oyundaki kaynaklar
--
-- Demir, Altin, Elmas madenlerdir; satilinca Kristal'e donusur.
-- Kristal para birimidir: tesis gelistirme, madenci, guclendirme, aninda bitirme.
--
-- NEDEN AYRI TABLO?
-- Users tablosuna "Demir INT, Altin INT, Elmas INT" sutunlari eklemek cazip gelir.
-- Ama 4. madeni ekledigin gun SEMAYI degistirmen, tum SP'leri guncellemen gerekir.
-- Bu tasarimda yeni maden eklemek tek INSERT'tir; hicbir kod degismez.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'ResourceTypes')
BEGIN
    CREATE TABLE ResourceTypes (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        Code NVARCHAR(20) NOT NULL UNIQUE,      -- Kodla ararız: 'DEMIR'. Ad degisse bile kod sabit kalir.
        Name NVARCHAR(50) NOT NULL,             -- Ekranda gorunen ad
        SellValue INT NOT NULL DEFAULT 0,       -- 1 birimi kac Kristal eder (Kristal'in kendisi icin 0)
        IsCurrency BIT NOT NULL DEFAULT 0,      -- Para birimi mi? (satilamaz, harcanir)
        DisplayOrder INT NOT NULL DEFAULT 0,

        CONSTRAINT CK_ResourceTypes_SellValue CHECK (SellValue >= 0)
    );
END
GO

-- ============================================================================
-- 1.2 ClickTypes — Tiklama turleri
--
-- Oyuncu 1 sn'lik tiklama ile baslar; Kristal odeyerek 5/15/30 sn'lik tiklamalari acar.
--
-- KRITIK DENGE KURALI:
-- 30 sn'lik tiklama, 1 sn'liginin tam 30 katini verirse ikisi de saniyede AYNI
-- uretir ve yukseltmenin hicbir anlami kalmaz (dominant strateji problemi).
-- Bu yuzden YieldMultiplier, CooldownSeconds'tan DAHA HIZLI artar:
--
--   1 sn ->  1 birim -> saniyede 1.00
--   5 sn ->  7 birim -> saniyede 1.40
--  15 sn -> 30 birim -> saniyede 2.00
--  30 sn -> 90 birim -> saniyede 3.00
--
-- Her tiklama turunun KENDI bekleme suresi vardir; hepsi ayni anda kullanilabilir.
-- Boylece aktif oynayan oyuncu odullendirilir.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'ClickTypes')
BEGIN
    CREATE TABLE ClickTypes (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        Code NVARCHAR(20) NOT NULL UNIQUE,          -- 'CLICK_1'
        Name NVARCHAR(50) NOT NULL,
        CooldownSeconds INT NOT NULL,               -- Iki tiklama arasi beklenmesi gereken sure
        YieldMultiplier DECIMAL(10,2) NOT NULL,     -- Uretim carpani
        UnlockCost BIGINT NOT NULL DEFAULT 0,       -- Acilis bedeli (Kristal)
        DisplayOrder INT NOT NULL DEFAULT 0,

        CONSTRAINT CK_ClickTypes_Cooldown CHECK (CooldownSeconds > 0),
        CONSTRAINT CK_ClickTypes_Yield CHECK (YieldMultiplier > 0),
        CONSTRAINT CK_ClickTypes_UnlockCost CHECK (UnlockCost >= 0)
    );
END
GO

-- ============================================================================
-- 1.3 FacilityTypes — Tesisler
--
-- Her tesis TEK bir kaynak uretir (ResourceTypeId).
-- Maliyet ustel artar: maliyet(seviye) = BaseCost * CostMultiplier ^ seviye
--
-- CostMultiplier = 1.15 idle oyun turunun fiili standardidir: her seviye %15
-- pahalilasir. Boylece ilerleme hic durmaz ama giderek yavaslar.
-- Rakamlari tek tek elle girseydik oyun ya 5 dakikada biterdi ya hic ilerlemezdi.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'FacilityTypes')
BEGIN
    CREATE TABLE FacilityTypes (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        Code NVARCHAR(30) NOT NULL UNIQUE,              -- 'DEMIR_OCAGI'
        Name NVARCHAR(50) NOT NULL,
        ResourceTypeId INT NOT NULL,                    -- Hangi kaynagi uretir
        BaseProduction INT NOT NULL DEFAULT 1,          -- Seviye basina uretim
        BaseCost BIGINT NOT NULL,                       -- 1. seviyenin maliyeti (Kristal)
        CostMultiplier DECIMAL(5,3) NOT NULL DEFAULT 1.150,
        MaxLevel INT NOT NULL DEFAULT 50,               -- Son seviye (tesis bazli, kodda sabit degil)
        DisplayOrder INT NOT NULL DEFAULT 0,

        CONSTRAINT FK_FacilityTypes_ResourceTypes
            FOREIGN KEY (ResourceTypeId) REFERENCES ResourceTypes(Id),
        CONSTRAINT CK_FacilityTypes_BaseProduction CHECK (BaseProduction > 0),
        CONSTRAINT CK_FacilityTypes_BaseCost CHECK (BaseCost > 0),
        CONSTRAINT CK_FacilityTypes_CostMultiplier CHECK (CostMultiplier > 1),
        CONSTRAINT CK_FacilityTypes_MaxLevel CHECK (MaxLevel >= 1)
    );
END
GO

-- MaxLevel sutunu tabloya sonradan eklendi. Yukaridaki CREATE bloku "tablo yoksa"
-- kosuluyla korundugu icin var olan veritabaninda calismaz; bu yuzden ayrica
-- ALTER ediyoruz. COL_LENGTH kontrolu bunu da idempotent yapar.
IF COL_LENGTH('FacilityTypes', 'MaxLevel') IS NULL
BEGIN
    ALTER TABLE FacilityTypes ADD MaxLevel INT NOT NULL DEFAULT 50;
END
GO

-- ============================================================================
-- 1.3b FacilityLevels — DENGE TABLOSU (balance table)
--
-- Her tesisin her seviyesi icin maliyet, uretim ve gelistirme suresi BURADA
-- HAZIR DURUR. Calisma aninda POWER() ile hesaplanmaz.
--
-- NEDEN? KAYAN NOKTA TUTARSIZLIGI.
-- 50 * 1.15^33 ifadesi ortamdan ortama farkli sonuc verir:
--     SQL Server FLOAT      -> 5034
--     SQL Server DECIMAL    -> 5035   <-- ayrisma!
--     C# double / JavaScript-> 5034
--
-- Elinde tam 5034 Kristal olan oyuncu, arayuzde aktif gorunen "Yukselt"
-- butonuna basar ve sunucudan "yetersiz bakiye" yer. Sadece 33. seviyede olur,
-- tekrar uretmesi zordur, log'da iz birakmaz. (heisenbug)
--
-- Cozum: degeri BIR KEZ hesapla, tam sayi olarak sakla. Artik SP de API de
-- Angular da AYNI sayiyi okur; ayrisma imkansiz hale gelir.
--
-- Ek faydalari:
--   - Sorgu POWER() yerine tek satir okuma olur (hizli ve okunakli)
--   - Tasarimci tek bir seviyeyi formulu bozmadan elle ayarlayabilir
--   - Admin panelinde denge tablosu dogrudan gosterilebilir
--
-- Tablo formulden URETILIR (asagida), elle yazilmaz. Yani formul kaybolmuyor;
-- sadece her istekte degil, bir kez calisiyor.
--
-- SATIR ANLAMI: "Level = N" satiri, N. SEVIYEYE ULASMANIN bedelini ve suresini,
-- ayrica N. seviyedeki uretimi tutar. Level 1 tesisin satin alma bedelidir
-- (sure 0 — insaat beklemesi yok).
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'FacilityLevels')
BEGIN
    CREATE TABLE FacilityLevels (
        FacilityTypeId INT NOT NULL,
        Level INT NOT NULL,
        Cost BIGINT NOT NULL,               -- Bu seviyeye ulasmanin bedeli (Kristal)
        Production BIGINT NOT NULL,         -- Bu seviyedeki tiklama basina uretim
        UpgradeMinutes INT NOT NULL,        -- Bu seviyeye yukselme suresi (Level 1 icin 0)

        CONSTRAINT PK_FacilityLevels PRIMARY KEY (FacilityTypeId, Level),
        CONSTRAINT FK_FacilityLevels_FacilityTypes
            FOREIGN KEY (FacilityTypeId) REFERENCES FacilityTypes(Id) ON DELETE CASCADE,
        CONSTRAINT CK_FacilityLevels_Level CHECK (Level >= 1),
        CONSTRAINT CK_FacilityLevels_Cost CHECK (Cost >= 0),
        CONSTRAINT CK_FacilityLevels_Production CHECK (Production > 0),
        CONSTRAINT CK_FacilityLevels_Minutes CHECK (UpgradeMinutes >= 0)
    );
END
GO

-- ============================================================================
-- 1.4 MinerTypes — Madenci kademeleri
--
-- ANA FIKIR: Her madenci kademesi BIR TIKLAMA TURUNU otomatiklestirir.
--   Cirak Madenci -> 1 sn'lik tiklamayi surekli yapar
--   Sef Madenci   -> 30 sn'lik tiklamayi surekli yapar
--
-- Bu tasarim iki sistemi tek formulde birlestirir: madenci ayri bir guc degil,
-- bir tiklamanin otomatik halidir. Boylece ikisini ayri ayri dengelemek gerekmez.
--
-- ClickTypeId UNIQUE: her tiklama turunu tam olarak bir madenci kademesi otomatiklestirir.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'MinerTypes')
BEGIN
    CREATE TABLE MinerTypes (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        Code NVARCHAR(30) NOT NULL UNIQUE,          -- 'CIRAK'
        Name NVARCHAR(50) NOT NULL,
        ClickTypeId INT NOT NULL UNIQUE,            -- Otomatiklestirdigi tiklama turu
        HireCost BIGINT NOT NULL,                   -- Ise alma bedeli (Kristal)
        DisplayOrder INT NOT NULL DEFAULT 0,

        CONSTRAINT FK_MinerTypes_ClickTypes
            FOREIGN KEY (ClickTypeId) REFERENCES ClickTypes(Id),
        CONSTRAINT CK_MinerTypes_HireCost CHECK (HireCost > 0)
    );
END
GO

-- ============================================================================
-- 1.5 UpgradeDurations — Tesis gelistirme sureleri (aralik tablosu)
--
-- Gelistirme suresi seviyeye gore artar: 5 dk -> 15 dk -> 30 dk -> 60 dk.
--
-- NEDEN ARALIK TABLOSU?
-- Her seviye icin ayri satir tutmak (1->5dk, 2->5dk, 3->5dk...) gereksiz tekrardir
-- ve 100. seviyeye cikarsak 100 satir gerekir. Bunun yerine "su seviyeden itibaren
-- su sure" deriz ve aradaki tum seviyeler ust satirdan degerini alir.
--
-- Sorgusu:  SELECT TOP 1 DurationMinutes FROM UpgradeDurations
--           WHERE MinLevel <= @hedefSeviye ORDER BY MinLevel DESC;
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'UpgradeDurations')
BEGIN
    CREATE TABLE UpgradeDurations (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        MinLevel INT NOT NULL UNIQUE,               -- Bu seviyeden itibaren gecerli
        DurationMinutes INT NOT NULL,

        CONSTRAINT CK_UpgradeDurations_MinLevel CHECK (MinLevel >= 1),
        CONSTRAINT CK_UpgradeDurations_Duration CHECK (DurationMinutes > 0)
    );
END
GO

-- ============================================================================
-- 1.6 UpgradeTypes — Kalici guclendirmeler
--
-- EffectType, guclendirmenin NEYI etkiledigini soyler. Kodda buna gore dallanacagiz:
--   'CLICK_POWER'  -> tiklama kazancini artirir
--   'MINER_SPEED'  -> madenci uretimini artirir
--   'SELL_BONUS'   -> satis gelirini artirir
--
-- EffectValue seviye basina EK carpandir: 0.10 = her seviyede %10.
-- Yani 5. seviyede toplam carpan = 1 + (0.10 * 5) = 1.50
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'UpgradeTypes')
BEGIN
    CREATE TABLE UpgradeTypes (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        Code NVARCHAR(30) NOT NULL UNIQUE,
        Name NVARCHAR(50) NOT NULL,
        Description NVARCHAR(200) NULL,
        EffectType NVARCHAR(30) NOT NULL,               -- CLICK_POWER | MINER_SPEED | SELL_BONUS
        EffectValue DECIMAL(10,3) NOT NULL,             -- Seviye basina ek carpan
        BaseCost BIGINT NOT NULL,
        CostMultiplier DECIMAL(5,3) NOT NULL DEFAULT 1.500,
        MaxLevel INT NOT NULL,
        DisplayOrder INT NOT NULL DEFAULT 0,

        CONSTRAINT CK_UpgradeTypes_EffectType
            CHECK (EffectType IN (N'CLICK_POWER', N'MINER_SPEED', N'SELL_BONUS')),
        CONSTRAINT CK_UpgradeTypes_EffectValue CHECK (EffectValue > 0),
        CONSTRAINT CK_UpgradeTypes_MaxLevel CHECK (MaxLevel > 0)
    );
END
GO

-- ############################################################################
-- BOLUM 2: OYUNCU DURUMU TABLOLARI
-- ############################################################################

-- ============================================================================
-- 2.1 PlayerResources — Oyuncunun kaynaklari
--
-- Demir de Kristal de AYNI tabloda durur; ikisi de "bir kaynagin miktari"dir.
-- Boylece "kaynak ekle / kaynak dus" mantigini BIR KEZ yazip her seye uygulariz.
--
-- BIRINCIL ANAHTAR NEDEN (UserId, ResourceTypeId)?
-- Bir oyuncunun her kaynaktan EN FAZLA BIR satiri olabilir. Bu bilesik anahtar,
-- "ayni oyuncuya iki demir satiri" hatasini veritabani seviyesinde imkansiz kilar.
-- Ayri bir Id sutunu koysaydik bu garantiyi kaybeder, UNIQUE kisit eklemek zorunda kalirdik.
--
-- CHECK (Amount >= 0): Bakiyenin eksiye dusmesini VERITABANI engeller.
-- C# tarafinda bir hata yapsak bile negatif altin olusamaz — son savunma hatti.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'PlayerResources')
BEGIN
    CREATE TABLE PlayerResources (
        UserId INT NOT NULL,
        ResourceTypeId INT NOT NULL,
        Amount BIGINT NOT NULL DEFAULT 0,
        UpdatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_PlayerResources PRIMARY KEY (UserId, ResourceTypeId),
        CONSTRAINT FK_PlayerResources_Users
            FOREIGN KEY (UserId) REFERENCES Users(Id) ON DELETE CASCADE,
        CONSTRAINT FK_PlayerResources_ResourceTypes
            FOREIGN KEY (ResourceTypeId) REFERENCES ResourceTypes(Id),
        CONSTRAINT CK_PlayerResources_Amount CHECK (Amount >= 0)
    );
END
GO

-- ============================================================================
-- 2.2 PlayerFacilities — Oyuncunun tesisleri
--
-- ZAMAN SUTUNLARI EN KRITIK KISIM:
--
-- UpgradeCompletesAt : Gelistirme ne zaman bitecek. NULL ise gelistirme yok.
--   Kalan sureyi ISTEMCIDEN ALMIYORUZ; sunucu SYSUTCDATETIME() ile kendisi hesaplar.
--   Aksi halde oyuncu saatini ileri alip gelistirmeyi aninda bitirirdi.
--
-- LastCollectedAt : Madencilerin urettigi en son ne zaman toplandi.
--   Arka planda saniyede bir calisan bir servis YAZMIYORUZ (1.000 oyuncu = saniyede
--   1.000 guncelleme, cokerdi). Bunun yerine oyuncu istek attiginda
--   "simdi - LastCollectedAt" kadar uretimi o an hesapliyoruz.
--   Bu yaklasim offline kazanci da bedavaya veriyor.
--
-- Tum zamanlar UTC'dir. Sunucu Turkiye'de, oyuncu Almanya'da olabilir; tek dogru
-- referans UTC'dir. Yerel saate cevirme isi arayuzun sorumlulugudur.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'PlayerFacilities')
BEGIN
    CREATE TABLE PlayerFacilities (
        UserId INT NOT NULL,
        FacilityTypeId INT NOT NULL,
        Level INT NOT NULL DEFAULT 1,
        UpgradeStartedAt DATETIME2 NULL,
        UpgradeCompletesAt DATETIME2 NULL,
        LastCollectedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_PlayerFacilities PRIMARY KEY (UserId, FacilityTypeId),
        CONSTRAINT FK_PlayerFacilities_Users
            FOREIGN KEY (UserId) REFERENCES Users(Id) ON DELETE CASCADE,
        CONSTRAINT FK_PlayerFacilities_FacilityTypes
            FOREIGN KEY (FacilityTypeId) REFERENCES FacilityTypes(Id),
        CONSTRAINT CK_PlayerFacilities_Level CHECK (Level >= 1),

        -- Iki zaman sutunu ya IKISI BIRDEN dolu ya IKISI BIRDEN bos olmali.
        -- Yarim durum (basladi ama bitis yok) mantiksizdir; veritabani engellesin.
        CONSTRAINT CK_PlayerFacilities_Upgrade CHECK (
            (UpgradeStartedAt IS NULL AND UpgradeCompletesAt IS NULL)
            OR (UpgradeStartedAt IS NOT NULL AND UpgradeCompletesAt IS NOT NULL)
        )
    );
END
GO

-- ============================================================================
-- 2.3 PlayerClickUnlocks — Oyuncunun actigi tiklama turleri
--
-- Tiklama turu acmak GENELDIR: CLICK_5'i bir kez acarsin, tum tesislerde kullanirsin.
-- Bu yuzden burada tesis yok.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'PlayerClickUnlocks')
BEGIN
    CREATE TABLE PlayerClickUnlocks (
        UserId INT NOT NULL,
        ClickTypeId INT NOT NULL,
        UnlockedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_PlayerClickUnlocks PRIMARY KEY (UserId, ClickTypeId),
        CONSTRAINT FK_PlayerClickUnlocks_Users
            FOREIGN KEY (UserId) REFERENCES Users(Id) ON DELETE CASCADE,
        CONSTRAINT FK_PlayerClickUnlocks_ClickTypes
            FOREIGN KEY (ClickTypeId) REFERENCES ClickTypes(Id)
    );
END
GO

-- ============================================================================
-- 2.4 PlayerFacilityClicks — Bekleme suresi takibi
--
-- Acilis GENEL ama BEKLEME SURESI tesis bazlidir. Yani Demir Ocagi'nda 1 sn'lik
-- tiklamayi yaptiktan hemen sonra Altin Damari'nda da yapabilirsin.
--
-- Neden boyle? Aksi halde 3 tesise sahip olmak tiklama gelirini hic artirmazdi ve
-- yeni tesis acmanin anlami kalmazdi. Bu tasarim genislemeyi odullendirir.
--
-- Iste bu yuzden bu tablo (UserId, FacilityTypeId, ClickTypeId) uclusuyle anahtarlanir.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'PlayerFacilityClicks')
BEGIN
    CREATE TABLE PlayerFacilityClicks (
        UserId INT NOT NULL,
        FacilityTypeId INT NOT NULL,
        ClickTypeId INT NOT NULL,
        LastClickAt DATETIME2 NULL,             -- NULL = hic tiklanmadi, hemen tiklanabilir

        CONSTRAINT PK_PlayerFacilityClicks PRIMARY KEY (UserId, FacilityTypeId, ClickTypeId),
        CONSTRAINT FK_PlayerFacilityClicks_Users
            FOREIGN KEY (UserId) REFERENCES Users(Id) ON DELETE CASCADE,
        CONSTRAINT FK_PlayerFacilityClicks_FacilityTypes
            FOREIGN KEY (FacilityTypeId) REFERENCES FacilityTypes(Id),
        CONSTRAINT FK_PlayerFacilityClicks_ClickTypes
            FOREIGN KEY (ClickTypeId) REFERENCES ClickTypes(Id)
    );
END
GO

-- ============================================================================
-- 2.5 PlayerMiners — Hangi tesiste kac madenci
--
-- Madenci bir TESISE atanir: Demir Ocagi'ndaki Cirak demir uretir.
-- Count sutunu tutuyoruz, her madenci icin ayri satir DEGIL. 500 madenci = 1 satir.
-- Madencilerin birbirinden ayirt edilmesi gereken bir ozelligi olmadigi icin dogrusu budur.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'PlayerMiners')
BEGIN
    CREATE TABLE PlayerMiners (
        UserId INT NOT NULL,
        FacilityTypeId INT NOT NULL,
        MinerTypeId INT NOT NULL,
        Count INT NOT NULL DEFAULT 0,
        UpdatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_PlayerMiners PRIMARY KEY (UserId, FacilityTypeId, MinerTypeId),
        CONSTRAINT FK_PlayerMiners_Users
            FOREIGN KEY (UserId) REFERENCES Users(Id) ON DELETE CASCADE,
        CONSTRAINT FK_PlayerMiners_FacilityTypes
            FOREIGN KEY (FacilityTypeId) REFERENCES FacilityTypes(Id),
        CONSTRAINT FK_PlayerMiners_MinerTypes
            FOREIGN KEY (MinerTypeId) REFERENCES MinerTypes(Id),
        CONSTRAINT CK_PlayerMiners_Count CHECK (Count >= 0)
    );
END
GO

-- ============================================================================
-- 2.6 PlayerUpgrades — Alinan guclendirmeler
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'PlayerUpgrades')
BEGIN
    CREATE TABLE PlayerUpgrades (
        UserId INT NOT NULL,
        UpgradeTypeId INT NOT NULL,
        Level INT NOT NULL DEFAULT 1,
        UpdatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_PlayerUpgrades PRIMARY KEY (UserId, UpgradeTypeId),
        CONSTRAINT FK_PlayerUpgrades_Users
            FOREIGN KEY (UserId) REFERENCES Users(Id) ON DELETE CASCADE,
        CONSTRAINT FK_PlayerUpgrades_UpgradeTypes
            FOREIGN KEY (UpgradeTypeId) REFERENCES UpgradeTypes(Id),
        CONSTRAINT CK_PlayerUpgrades_Level CHECK (Level >= 1)
    );
END
GO

-- ============================================================================
-- 2.7 Transactions — Olay gunlugu (ledger)
--
-- Her kazanc ve harcama buraya BIR SATIR olarak yazilir. Amount pozitif ise kazanc,
-- negatif ise harcamadir.
--
-- NEDEN BU TABLO COK DEGERLI?
--  1. HILE TESPITI: "Bu oyuncu 3 saniyede 1 milyon Kristal kazanmis" sorgusu
--     ancak boyle bir gunlukle yazilabilir.
--  2. ADMIN PANELI: Sikayet geldiginde "kaynaklarin nereye gitti" cevaplanabilir.
--  3. DENGE ANALIZI: Oyuncular Kristal'i en cok nereye harciyor? Hangi mekanik
--     hic kullanilmiyor? Bu veriler olmadan oyun dengelemesi tahmine dayanir.
--
-- SONRADAN EKLENEMEZ: gecmis veri kaybolmustur. Bu yuzden en bastan koyuyoruz.
--
-- BalanceAfter: Islem SONRASI bakiye. Teknik olarak tekrar (redundant) bir bilgidir
-- ama kasitlidir: bakiyeyi bastan toplamadan o anki durumu gorebilmeyi saglar ve
-- tutarsizlik olursa (bakiye != toplam) hemen anlasilir.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Transactions')
BEGIN
    CREATE TABLE Transactions (
        Id BIGINT IDENTITY(1,1) PRIMARY KEY,        -- Cok satir birikecek: BIGINT
        UserId INT NOT NULL,
        ResourceTypeId INT NOT NULL,
        Amount BIGINT NOT NULL,                     -- + kazanc, - harcama
        BalanceAfter BIGINT NOT NULL,
        Reason NVARCHAR(30) NOT NULL,               -- CLICK | COLLECT | SELL | ...
        ReferenceId INT NULL,                       -- Ilgili tesis/madenci/guclendirme Id'si
        CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),

        CONSTRAINT FK_Transactions_Users
            FOREIGN KEY (UserId) REFERENCES Users(Id) ON DELETE CASCADE,
        CONSTRAINT FK_Transactions_ResourceTypes
            FOREIGN KEY (ResourceTypeId) REFERENCES ResourceTypes(Id),
        CONSTRAINT CK_Transactions_Reason CHECK (Reason IN (
            N'CLICK', N'COLLECT', N'SELL', N'FACILITY_UPGRADE', N'HIRE_MINER',
            N'BUY_UPGRADE', N'UNLOCK_CLICK', N'INSTANT_FINISH', N'AD_REWARD', N'ADMIN_ADJUST'
        ))
    );

    -- "Bu oyuncunun son islemleri" en sik sorgu olacak: ikisini birlikte indeksliyoruz.
    -- CreatedAt DESC: en yeniler basta gelsin, siralama maliyeti olmasin.
    CREATE NONCLUSTERED INDEX IX_Transactions_User_Date
        ON Transactions(UserId, CreatedAt DESC);
END
GO

-- ############################################################################
-- BOLUM 3: SEED VERISI (Oyun tasarimi rakamlari)
--
-- MERGE kullaniyoruz: script tekrar tekrar calistirilabilir (idempotent).
-- Var olan satirlar guncellenir, olmayanlar eklenir. Boylece dengeyi degistirmek
-- istedigimizde bu dosyayi yeniden calistirmak yeterli olur.
-- ############################################################################

-- --- Kaynaklar ---
MERGE INTO ResourceTypes AS h
USING (VALUES
    (N'DEMIR',   N'Demir',   1,   0, 1),
    (N'ALTIN',   N'Altın',   15,  0, 2),
    (N'ELMAS',   N'Elmas',   300, 0, 3),
    (N'KRISTAL', N'Kristal', 0,   1, 4)
) AS k (Code, Name, SellValue, IsCurrency, DisplayOrder)
    ON h.Code = k.Code
WHEN MATCHED THEN UPDATE SET
    h.Name = k.Name, h.SellValue = k.SellValue,
    h.IsCurrency = k.IsCurrency, h.DisplayOrder = k.DisplayOrder
WHEN NOT MATCHED THEN
    INSERT (Code, Name, SellValue, IsCurrency, DisplayOrder)
    VALUES (k.Code, k.Name, k.SellValue, k.IsCurrency, k.DisplayOrder);
GO

-- --- Tiklama turleri ---
MERGE INTO ClickTypes AS h
USING (VALUES
    (N'CLICK_1',  N'Hızlı Kazma',    1,   1.00,     0, 1),
    (N'CLICK_5',  N'Derin Kazma',    5,   7.00,   500, 2),
    (N'CLICK_15', N'Patlatma',      15,  30.00,  5000, 3),
    (N'CLICK_30', N'Büyük Patlatma', 30,  90.00, 40000, 4)
) AS k (Code, Name, CooldownSeconds, YieldMultiplier, UnlockCost, DisplayOrder)
    ON h.Code = k.Code
WHEN MATCHED THEN UPDATE SET
    h.Name = k.Name, h.CooldownSeconds = k.CooldownSeconds,
    h.YieldMultiplier = k.YieldMultiplier, h.UnlockCost = k.UnlockCost,
    h.DisplayOrder = k.DisplayOrder
WHEN NOT MATCHED THEN
    INSERT (Code, Name, CooldownSeconds, YieldMultiplier, UnlockCost, DisplayOrder)
    VALUES (k.Code, k.Name, k.CooldownSeconds, k.YieldMultiplier, k.UnlockCost, k.DisplayOrder);
GO

-- --- Tesisler ---
MERGE INTO FacilityTypes AS h
USING (VALUES
    (N'DEMIR_OCAGI',      N'Demir Ocağı',      N'DEMIR', 1,     50, 50, 1),
    (N'ALTIN_DAMARI',     N'Altın Damarı',     N'ALTIN', 1,   2000, 50, 2),
    (N'KIMBERLIT_BACASI', N'Kimberlit Bacası', N'ELMAS', 1, 100000, 50, 3)
) AS k (Code, Name, ResourceCode, BaseProduction, BaseCost, MaxLevel, DisplayOrder)
    ON h.Code = k.Code
WHEN MATCHED THEN UPDATE SET
    h.Name = k.Name, h.BaseProduction = k.BaseProduction,
    h.BaseCost = k.BaseCost, h.MaxLevel = k.MaxLevel, h.DisplayOrder = k.DisplayOrder
WHEN NOT MATCHED THEN
    INSERT (Code, Name, ResourceTypeId, BaseProduction, BaseCost, MaxLevel, DisplayOrder)
    VALUES (k.Code, k.Name,
            (SELECT Id FROM ResourceTypes WHERE Code = k.ResourceCode),
            k.BaseProduction, k.BaseCost, k.MaxLevel, k.DisplayOrder);
GO

-- --- Madenciler (her biri bir tiklama turunu otomatiklestirir) ---
MERGE INTO MinerTypes AS h
USING (VALUES
    (N'CIRAK', N'Çırak Madenci', N'CLICK_1',    100, 1),
    (N'USTA',  N'Usta Madenci',  N'CLICK_5',   1200, 2),
    (N'UZMAN', N'Uzman Madenci', N'CLICK_15', 12000, 3),
    (N'SEF',   N'Şef Madenci',   N'CLICK_30', 90000, 4)
) AS k (Code, Name, ClickCode, HireCost, DisplayOrder)
    ON h.Code = k.Code
WHEN MATCHED THEN UPDATE SET
    h.Name = k.Name, h.HireCost = k.HireCost, h.DisplayOrder = k.DisplayOrder
WHEN NOT MATCHED THEN
    INSERT (Code, Name, ClickTypeId, HireCost, DisplayOrder)
    VALUES (k.Code, k.Name,
            (SELECT Id FROM ClickTypes WHERE Code = k.ClickCode),
            k.HireCost, k.DisplayOrder);
GO

-- --- Gelistirme sureleri ---
MERGE INTO UpgradeDurations AS h
USING (VALUES
    (1, 5), (5, 15), (10, 30), (20, 60)
) AS k (MinLevel, DurationMinutes)
    ON h.MinLevel = k.MinLevel
WHEN MATCHED THEN UPDATE SET h.DurationMinutes = k.DurationMinutes
WHEN NOT MATCHED THEN INSERT (MinLevel, DurationMinutes) VALUES (k.MinLevel, k.DurationMinutes);
GO

-- --- DENGE TABLOSUNUN URETILMESI -------------------------------------------
-- FacilityLevels tablosu tamamen TURETILMIS bir tablodur: FacilityTypes ve
-- UpgradeDurations'tan hesaplanir. Denge rakamlarini degistirdiginde bu blogu
-- tekrar calistirmak yeterlidir.
--
-- Kullanilan formuller:
--   Cost(n)       = BaseCost * CostMultiplier ^ (n - 1)      -- n=1 satin alma bedeli
--   Production(n) = BaseProduction * n
--   Minutes(n)    = UpgradeDurations icinde n'i kapsayan aralik (n=1 icin 0)
--
-- POWER'i FLOAT ile hesapliyoruz: C# double ve JavaScript ile ayni IEEE-754
-- aritmetigini kullanir. Sonuc FLOOR ile tam sayiya inip TABLOYA YAZILDIGI icin
-- bundan sonra hicbir yerde yeniden hesaplanmayacak.
--
-- Ozyinelemeli CTE (recursive CTE): 1'den baslayip MaxLevel'a kadar sayi uretir.
-- Ayri bir "sayilar tablosu" tutmaya gerek kalmaz.
WITH Seviyeler AS (
    SELECT 1 AS Level
    UNION ALL
    SELECT Level + 1 FROM Seviyeler WHERE Level < 1000     -- ust guvenlik siniri
)
MERGE INTO FacilityLevels AS h
USING (
    SELECT
        ft.Id AS FacilityTypeId,
        s.Level,
        CAST(FLOOR(ft.BaseCost * POWER(CAST(ft.CostMultiplier AS FLOAT), s.Level - 1)) AS BIGINT) AS Cost,
        CAST(ft.BaseProduction * s.Level AS BIGINT) AS Production,
        CASE
            WHEN s.Level = 1 THEN 0      -- satin alma: insaat beklemesi yok
            ELSE (
                SELECT TOP 1 ud.DurationMinutes
                FROM UpgradeDurations ud
                WHERE ud.MinLevel <= s.Level
                ORDER BY ud.MinLevel DESC
            )
        END AS UpgradeMinutes
    FROM FacilityTypes ft
    JOIN Seviyeler s ON s.Level <= ft.MaxLevel
) AS k
    ON h.FacilityTypeId = k.FacilityTypeId AND h.Level = k.Level
WHEN MATCHED THEN UPDATE SET
    h.Cost = k.Cost, h.Production = k.Production, h.UpgradeMinutes = k.UpgradeMinutes
WHEN NOT MATCHED BY TARGET THEN
    INSERT (FacilityTypeId, Level, Cost, Production, UpgradeMinutes)
    VALUES (k.FacilityTypeId, k.Level, k.Cost, k.Production, k.UpgradeMinutes)
-- MaxLevel dusurulurse artik gecersiz olan satirlar temizlenir.
WHEN NOT MATCHED BY SOURCE THEN DELETE
OPTION (MAXRECURSION 1000);
GO

-- --- Guclendirmeler ---
MERGE INTO UpgradeTypes AS h
USING (VALUES
    (N'KESKIN_KAZMA',    N'Keskin Kazma',      N'Tıklama kazancını seviye başına %10 artırır.',   N'CLICK_POWER', 0.100,  1000, 20, 1),
    (N'MADENCI_EGITIMI', N'Madenci Eğitimi',   N'Madenci üretimini seviye başına %10 artırır.',   N'MINER_SPEED', 0.100,  5000, 20, 2),
    (N'TUCCAR_BAGLANTI', N'Tüccar Bağlantısı', N'Satış gelirini seviye başına %5 artırır.',       N'SELL_BONUS',  0.050,  3000, 10, 3)
) AS k (Code, Name, Description, EffectType, EffectValue, BaseCost, MaxLevel, DisplayOrder)
    ON h.Code = k.Code
WHEN MATCHED THEN UPDATE SET
    h.Name = k.Name, h.Description = k.Description, h.EffectType = k.EffectType,
    h.EffectValue = k.EffectValue, h.BaseCost = k.BaseCost,
    h.MaxLevel = k.MaxLevel, h.DisplayOrder = k.DisplayOrder
WHEN NOT MATCHED THEN
    INSERT (Code, Name, Description, EffectType, EffectValue, BaseCost, MaxLevel, DisplayOrder)
    VALUES (k.Code, k.Name, k.Description, k.EffectType, k.EffectValue, k.BaseCost, k.MaxLevel, k.DisplayOrder);
GO

-- ############################################################################
-- BOLUM 4: MEVCUT OYUNCULARIN TASINMASI (MIGRATION)
--
-- PlayerProfiles tablosunda kimlik dogrulama asamasindan kalma Gold, MiningPower
-- ve LastMinedAt sutunlari var. Bunlarin karsiligi artik yeni tablolarda.
--
-- "GENISLET / DARALT" (expand / contract) DESENI:
-- Bu sutunlari SIMDI SILMIYORUZ. Cunku sp_RegisterUser hala onlara yaziyor;
-- silersek kayit olma aninda bozulur. Dogru sira:
--
--   1. GENISLET  : Yeni tablolari olustur, veriyi kopyala      <- BUGUN BURADAYIZ
--   2. GECIS     : Kodu (SP'leri ve API'yi) yeni tablolara gecir  <- Gun 2
--   3. DARALT    : Artik kimse kullanmayinca eski sutunlari sil   <- Gun 2 sonu
--
-- Bu, calisan sistemlerde sema degistirmenin standart yontemidir. Tek adimda
-- "sil ve yenisini yaz" yapilsaydi, kod ile sema arasinda uyumsuz bir an olusur
-- ve o anda gelen her istek hata alirdi.
-- ############################################################################

-- 4.1 Her oyuncuya her kaynaktan bir satir. Eski Gold degeri Kristal'e tasinir.
INSERT INTO PlayerResources (UserId, ResourceTypeId, Amount)
SELECT u.Id, rt.Id,
       CASE WHEN rt.Code = N'KRISTAL' THEN ISNULL(pp.Gold, 0) ELSE 0 END
FROM Users u
CROSS JOIN ResourceTypes rt                      -- her kullanici x her kaynak
LEFT JOIN PlayerProfiles pp ON pp.UserId = u.Id
WHERE NOT EXISTS (
    SELECT 1 FROM PlayerResources pr
    WHERE pr.UserId = u.Id AND pr.ResourceTypeId = rt.Id
);
GO

-- 4.2 Herkes Demir Ocagi ile baslar (1. seviye).
INSERT INTO PlayerFacilities (UserId, FacilityTypeId, Level)
SELECT u.Id, ft.Id, 1
FROM Users u
CROSS JOIN FacilityTypes ft
WHERE ft.Code = N'DEMIR_OCAGI'
  AND NOT EXISTS (
      SELECT 1 FROM PlayerFacilities pf
      WHERE pf.UserId = u.Id AND pf.FacilityTypeId = ft.Id
  );
GO

-- 4.3 Herkeste 1 sn'lik tiklama bastan aciktir.
INSERT INTO PlayerClickUnlocks (UserId, ClickTypeId)
SELECT u.Id, ct.Id
FROM Users u
CROSS JOIN ClickTypes ct
WHERE ct.Code = N'CLICK_1'
  AND NOT EXISTS (
      SELECT 1 FROM PlayerClickUnlocks pcu
      WHERE pcu.UserId = u.Id AND pcu.ClickTypeId = ct.Id
  );
GO

-- 4.4 Sahip olunan her tesis x acilmis her tiklama icin bekleme takip satiri.
INSERT INTO PlayerFacilityClicks (UserId, FacilityTypeId, ClickTypeId)
SELECT pf.UserId, pf.FacilityTypeId, pcu.ClickTypeId
FROM PlayerFacilities pf
JOIN PlayerClickUnlocks pcu ON pcu.UserId = pf.UserId
WHERE NOT EXISTS (
    SELECT 1 FROM PlayerFacilityClicks pfc
    WHERE pfc.UserId = pf.UserId
      AND pfc.FacilityTypeId = pf.FacilityTypeId
      AND pfc.ClickTypeId = pcu.ClickTypeId
);
GO

PRINT N'03_game_tables.sql tamamlandi.';
GO
