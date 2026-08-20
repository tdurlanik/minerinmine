-- ============================================================================
-- PROJE: MinerInMine
-- ADIM 13: Yonetim Paneli - Ekonomi Sagligi
--
--   sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i 13_admin_ekonomi.sql
--
-- NEDEN BU EKRAN?
-- tools/denge-simulasyonu.js oyunun nasil oynanabilecegini TAHMIN eder.
-- Bu ekran oyuncularin gercekte ne yaptigini OLCER. Ikisi ayrisiyorsa
-- ya simulasyondaki oyuncu modeli yanlistir ya da denge beklenmedik bir
-- yerden kaciyordur.
--
-- OYUN EKONOMISININ TEMEL METRIGI: FAUCET / SINK DENGESI
--   faucet (musluk) = ekonomiye giren para  (satis, reklam odulu)
--   sink   (gider)  = ekonomiden cikan para (gelistirme, madenci, atlama)
-- Faucet surekli sink'i asiyorsa para birikir, fiyatlar anlamsizlasir ve
-- oyunun ilerleme hissi olur. Bu iki sayiyi yan yana gormeden denge
-- konusulamaz.
--
-- Bu sorgularin TAMAMI Transactions gunlugunden turetilir. Bakiye tablolari
-- yalnizca SON durumu bilir; "dun ne kadar Kristal uretildi" sorusunun cevabi
-- yalnizca olay gunlugunde vardir.
-- ============================================================================

USE MinerInMineDb;
GO

-- ============================================================================
-- sp_AdminGetEconomy — ekonomi sagligi raporu
--
-- BES SONUC KUMESI:
--   1) Ozet            : oyuncu sayilari, dolasimdaki Kristal, toplam servet
--   2) Gunluk akis     : gun gun faucet / sink / net / aktif oyuncu
--   3) Sebep bazinda   : hangi mekanik ne kadar para uretiyor/yakiyor
--   4) Tesis dagilimi  : oyuncular hangi tesiste, hangi seviyede takiliyor
--   5) Kazma acilma    : hangi kazma turu kac oyuncu tarafindan acilmis
--
-- SIRA ONEMLIDIR: AdminRepository icindeki okuma sirasi birebir ayni olmali.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_AdminGetEconomy
    @Days INT = 7
AS
BEGIN
    SET NOCOUNT ON;

    IF @Days < 1 OR @Days > 90 SET @Days = 7;

    DECLARE @KristalId INT = (SELECT Id FROM ResourceTypes WHERE Code = N'KRISTAL');
    DECLARE @Baslangic DATETIME2 = DATEADD(DAY, -@Days, SYSUTCDATETIME());
    DECLARE @BugunBasi DATETIME2 = CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATETIME2);

    -- ------------------------------------------------------------------
    -- 1) OZET
    --
    -- "Aktif oyuncu" = o donemde EN AZ BIR ISLEM yapmis oyuncu. Giris yapip
    -- hicbir sey yapmayani saymiyoruz; oyunu oynayan sayisi bu.
    -- ------------------------------------------------------------------
    SELECT
        (SELECT COUNT(*) FROM Users WHERE IsActive = 1) AS TotalPlayers,

        (SELECT COUNT(DISTINCT t.UserId) FROM Transactions t
         WHERE t.CreatedAt >= @BugunBasi) AS ActiveToday,

        (SELECT COUNT(DISTINCT t.UserId) FROM Transactions t
         WHERE t.CreatedAt >= @Baslangic) AS ActiveInPeriod,

        (SELECT COUNT(*) FROM Users WHERE CreatedAt >= @Baslangic) AS NewPlayers,

        -- Dolasimdaki Kristal: oyuncularin elinde duran toplam para.
        -- Surekli buyuyorsa enflasyon var demektir.
        ISNULL((SELECT SUM(Amount) FROM PlayerResources
                WHERE ResourceTypeId = @KristalId), 0) AS CirculatingKristal,

        ISNULL((SELECT SUM(pr.Amount * CASE WHEN rt.IsCurrency = 1 THEN 1 ELSE rt.SellValue END)
                FROM PlayerResources pr JOIN ResourceTypes rt ON rt.Id = pr.ResourceTypeId), 0)
            AS TotalWealth,

        -- Donem geneli faucet ve sink
        ISNULL((SELECT SUM(t.Amount) FROM Transactions t
                WHERE t.ResourceTypeId = @KristalId AND t.Amount > 0
                  AND t.CreatedAt >= @Baslangic), 0) AS PeriodFaucet,

        ISNULL((SELECT SUM(ABS(t.Amount)) FROM Transactions t
                WHERE t.ResourceTypeId = @KristalId AND t.Amount < 0
                  AND t.CreatedAt >= @Baslangic), 0) AS PeriodSink,

        @Days AS Days;

    -- ------------------------------------------------------------------
    -- 2) GUNLUK AKIS
    --
    -- CAST(... AS DATE) ile gune indirgeyip grupluyoruz. Zaman UTC'dir;
    -- arayuz de UTC gosterir (yerel saate cevirmek gun sinirini kaydirirdi).
    -- ------------------------------------------------------------------
    SELECT
        CAST(t.CreatedAt AS DATE) AS Gun,
        SUM(CASE WHEN t.Amount > 0 THEN t.Amount ELSE 0 END) AS Faucet,
        SUM(CASE WHEN t.Amount < 0 THEN ABS(t.Amount) ELSE 0 END) AS Sink,
        SUM(t.Amount) AS Net,
        COUNT(DISTINCT t.UserId) AS ActivePlayers
    FROM Transactions t
    WHERE t.ResourceTypeId = @KristalId AND t.CreatedAt >= @Baslangic
    GROUP BY CAST(t.CreatedAt AS DATE)
    ORDER BY Gun;

    -- ------------------------------------------------------------------
    -- 3) SEBEP BAZINDA AKIS
    --
    -- Hangi mekanik para uretiyor, hangisi yakiyor? PlayerCount sutunu
    -- onemli: toplam buyuk ama PlayerCount 1 ise bu tek bir oyuncunun
    -- davranisidir, genel egilim degil.
    -- ------------------------------------------------------------------
    SELECT
        t.Reason,
        CASE WHEN SUM(t.Amount) >= 0 THEN 1 ELSE -1 END AS Direction,
        SUM(ABS(t.Amount)) AS Total,
        COUNT(*) AS Times,
        COUNT(DISTINCT t.UserId) AS PlayerCount
    FROM Transactions t
    WHERE t.ResourceTypeId = @KristalId AND t.CreatedAt >= @Baslangic
    GROUP BY t.Reason
    ORDER BY Total DESC;

    -- ------------------------------------------------------------------
    -- 4) TESIS DAGILIMI — oyuncular nerede takiliyor?
    --
    -- LEFT JOIN: hic oyuncusu olmayan tesis de listede gorunsun. Sifir
    -- satirinin kendisi bir bulgudur ("kimse bu tesise ulasamiyor").
    -- ------------------------------------------------------------------
    SELECT
        ft.Id AS FacilityTypeId,
        ft.Name AS FacilityName,
        COUNT(pf.UserId) AS OwnerCount,
        ISNULL(AVG(CAST(pf.Level AS FLOAT)), 0) AS AvgLevel,
        ISNULL(MAX(pf.Level), 0) AS MaxLevel,
        ft.MaxLevel AS CapLevel
    FROM FacilityTypes ft
    LEFT JOIN PlayerFacilities pf ON pf.FacilityTypeId = ft.Id
    GROUP BY ft.Id, ft.Name, ft.MaxLevel, ft.DisplayOrder
    ORDER BY ft.DisplayOrder;

    -- ------------------------------------------------------------------
    -- 5) KAZMA TURU ACILMA ORANI
    --
    -- Hic acilmayan bir kazma turu ya cok pahalidir ya da kazanci
    -- ikna edici degildir. Bu satir dogrudan bir denge sinyali.
    -- ------------------------------------------------------------------
    SELECT
        ct.Id AS ClickTypeId,
        ct.Name AS ClickName,
        ct.UnlockCost,
        COUNT(puc.UserId) AS UnlockedBy,
        (SELECT COUNT(*) FROM Users WHERE IsActive = 1) AS TotalPlayers
    FROM ClickTypes ct
    LEFT JOIN PlayerClickUnlocks puc ON puc.ClickTypeId = ct.Id
    GROUP BY ct.Id, ct.Name, ct.UnlockCost, ct.DisplayOrder
    ORDER BY ct.DisplayOrder;
END
GO

PRINT '13_admin_ekonomi.sql tamamlandi. sp_AdminGetEconomy hazir.';
GO
