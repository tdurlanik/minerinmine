-- ============================================================================
-- PROJE: MinerInMine
-- ADIM 15: Maden Sohbeti (SignalR icin veri katmani)
--
--   sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i 15_sohbet.sql
--
-- SOHBET UC AYRI PROBLEMDIR:
--   1. SAKLAMA  -> veritabani (bu dosya)
--   2. ILETIM   -> WebSocket / SignalR (API katmani)
--   3. DAGITIM  -> birden fazla sunucu varsa broker (bizde tek sunucu, gerek yok)
--
-- Kuyruk (RabbitMQ gibi) bir POSTA KUTUSU DEGILDIR: mesaj bir kez tuketilince
-- gider, gecmis sorgulanamaz. Sohbet gecmisi KALICI VERIDIR ve tablosu olur.
--
-- MESAJLAR NEDEN SAKLANIR?
--   - Oyuncu sonradan girdiginde son konusulanlari gorsun
--   - Moderasyon: sikayet geldiginde ne yazildigi bakilabilsin
--   - Sunucu yeniden baslayinca sohbet bos kalmasin
-- ============================================================================

USE MinerInMineDb;
GO

-- ============================================================================
-- 1. ChatMessages — mesaj gecmisi
--
-- Tek odali sohbet oldugu icin "oda" sutunu YOK. Ileride birden fazla oda
-- gerekirse RoomId eklenir; simdiden eklemek kullanilmayan bir sutun tasimak
-- olurdu (YAGNI).
--
-- IsDeleted: moderasyon icin. Mesaji SILMIYORUZ, isaretliyoruz — kimin ne
-- yazdigi kayitli kalsin. Ayni gerekce Users.IsActive'de de gecerliydi.
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'ChatMessages')
BEGIN
    CREATE TABLE ChatMessages (
        Id BIGINT IDENTITY(1,1) PRIMARY KEY,     -- cok satir birikir: BIGINT
        UserId INT NOT NULL,
        Body NVARCHAR(300) NOT NULL,
        CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        IsDeleted BIT NOT NULL DEFAULT 0,

        CONSTRAINT FK_ChatMessages_Users
            FOREIGN KEY (UserId) REFERENCES Users(Id) ON DELETE CASCADE,
        CONSTRAINT CK_ChatMessages_Body CHECK (LEN(Body) > 0)
    );

    -- "Son mesajlar" en sik sorgu: tarihe gore azalan indeks.
    CREATE NONCLUSTERED INDEX IX_ChatMessages_Date
        ON ChatMessages(CreatedAt DESC);

    -- Spam kontrolu "bu oyuncunun son N saniyedeki mesajlari" diye sorar.
    CREATE NONCLUSTERED INDEX IX_ChatMessages_User_Date
        ON ChatMessages(UserId, CreatedAt DESC);
END
GO

MERGE INTO GameSettings AS h
USING (VALUES
    (N'CHAT_MAX_PER_10SEC', N'5', N'Bir oyuncunun 10 saniyede gonderebilecegi en fazla mesaj'),
    (N'CHAT_HISTORY_SIZE', N'50', N'Sohbete girildiginde gosterilen gecmis mesaj sayisi')
) AS k (SettingKey, SettingValue, Description)
    ON h.SettingKey = k.SettingKey
WHEN MATCHED THEN UPDATE SET h.SettingValue = k.SettingValue, h.Description = k.Description
WHEN NOT MATCHED THEN INSERT (SettingKey, SettingValue, Description)
    VALUES (k.SettingKey, k.SettingValue, k.Description);
GO

-- ============================================================================
-- 2. sp_SendChatMessage — mesaj gonder
--
-- SUNUCU OTORITESI, SOHBETTE DE GECERLI
-- Istemci yalnizca METNI gonderir. Kim oldugunu SOYLEMEZ; UserId token'dan
-- okunur. Aksi halde oyuncu baskasinin adina mesaj yazabilirdi.
--
-- SPAM SINIRI NEDEN BURADA?
-- Arayuzde de sinirlayabilirdik ama arayuz atlanabilir (Postman, curl).
-- Kural veritabaninda olursa hicbir yoldan asilamaz. Ayni gerekce oyunun
-- geri kalaninda da gecerliydi.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_SendChatMessage
    @UserId INT,
    @Body NVARCHAR(300),
    @ErrorMessage NVARCHAR(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ErrorMessage = NULL;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();

    -- Bastaki/sondaki bosluklari at; "   " gibi mesajlar bos sayilsin.
    SET @Body = LTRIM(RTRIM(@Body));

    IF @Body IS NULL OR LEN(@Body) = 0
    BEGIN
        SET @ErrorMessage = N'Bos mesaj gonderilemez.';
        RETURN -1;
    END

    -- Hesabi dondurulmus oyuncu yazamaz.
    IF NOT EXISTS (SELECT 1 FROM Users WHERE Id = @UserId AND IsActive = 1)
    BEGIN
        SET @ErrorMessage = N'Hesabiniz sohbete katilamaz.';
        RETURN -2;
    END

    DECLARE @Sinir INT = TRY_CAST(
        (SELECT SettingValue FROM GameSettings WHERE SettingKey = N'CHAT_MAX_PER_10SEC') AS INT);
    IF @Sinir IS NULL SET @Sinir = 5;

    DECLARE @SonMesajlar INT = (
        SELECT COUNT(*) FROM ChatMessages
        WHERE UserId = @UserId AND CreatedAt >= DATEADD(SECOND, -10, @Now)
    );

    IF @SonMesajlar >= @Sinir
    BEGIN
        SET @ErrorMessage = N'Cok hizli yaziyorsun, biraz yavasla.';
        RETURN -3;
    END

    INSERT INTO ChatMessages (UserId, Body, CreatedAt)
    VALUES (@UserId, @Body, @Now);

    -- Yayinlanacak mesajin tam hali: Hub bunu tum istemcilere gonderecek.
    SELECT
        SCOPE_IDENTITY() AS Id,
        @UserId AS UserId,
        u.Username,
        @Body AS Body,
        @Now AS CreatedAt
    FROM Users u
    WHERE u.Id = @UserId;

    RETURN 0;
END
GO

-- ============================================================================
-- 3. sp_GetChatHistory — son N mesaj
--
-- TOP ile azalan cekip sonra artan siralayan bir sarmal kullaniyoruz:
-- "en son 50 mesaj" istiyoruz ama ekranda ESKIDEN YENIYE dizilmeliler.
-- Once DESC ile son 50'yi aliyoruz (indeks bu siraya gore), sonra disarida
-- ASC ile ters ceviriyoruz. Bunun tersi (once ASC siralayip son 50'yi almak)
-- butun tabloyu taratirdi.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_GetChatHistory
    @Top INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Top IS NULL
        SET @Top = TRY_CAST(
            (SELECT SettingValue FROM GameSettings WHERE SettingKey = N'CHAT_HISTORY_SIZE') AS INT);

    IF @Top IS NULL OR @Top < 1 OR @Top > 200 SET @Top = 50;

    SELECT Id, UserId, Username, Body, CreatedAt
    FROM (
        SELECT TOP (@Top)
            c.Id, c.UserId, u.Username, c.Body, c.CreatedAt
        FROM ChatMessages c
        JOIN Users u ON u.Id = c.UserId
        WHERE c.IsDeleted = 0
        ORDER BY c.CreatedAt DESC, c.Id DESC
    ) AS Son
    ORDER BY CreatedAt ASC, Id ASC;
END
GO

PRINT '15_sohbet.sql tamamlandi. ChatMessages + 2 prosedur hazir.';
GO
