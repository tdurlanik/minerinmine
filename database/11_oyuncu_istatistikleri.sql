-- ============================================================================
-- PROJE: MinerInMine
-- ADIM 11: Oyuncu Istatistikleri (Dashboard'un yeni isi)
--
--   sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i 11_oyuncu_istatistikleri.sql
--
-- NEDEN BU SCRIPT VAR?
-- /dashboard ekrani Gun 0'dan kalma bir "kimlik dogrulama kaniti" sayfasiydi;
-- oyunla ilgisi kalmamisti. Yerine oyuncunun kendi oynanis ozetini gosteren
-- bir sayfa koyuyoruz.
--
-- BURADAKI ASIL DERS: BU SORGULARIN HICBIRI SONRADAN "URETILEMEZDI".
-- "Kristal'i en cok neye harcadin?" sorusunun cevabi hicbir yerde YAZMIYOR;
-- yalnizca Transactions gunlugunu EN BASTAN tuttugumuz icin hesaplanabiliyor.
-- Bakiye tablosu (PlayerResources) sadece SON durumu bilir, gecmisi bilmez.
-- Gunluk tutulmasaydi bu ozellik icin gecmis veri uretilemez, ozellik ancak
-- "bugunden itibaren" calisabilirdi.
-- ============================================================================

USE MinerInMineDb;
GO

-- ============================================================================
-- sp_GetPlayerStats — oyuncunun oynanis ozeti
--
-- BES SONUC KUMESI dondurur (Dapper QueryMultiple ile tek gidis-donuste okunur):
--   1) Ozet          : tek satir — toplam kazanc/harcama, tiklama sayisi vb.
--   2) Harcama dagilimi : Kristal'in nereye gittigi (sebep bazinda)
--   3) Kazanc dagilimi  : Kristal'in nereden geldigi (sebep bazinda)
--   4) Tesis ozeti      : hangi tesis ne kadar maden cikardi
--   5) Siralama         : servet sirasi ve toplam oyuncu sayisi
--
-- SIRA ONEMLIDIR: GameRepository icindeki okuma sirasi birebir ayni olmali.
--
-- SORGULAR NEDEN SADECE KRISTAL UZERINDEN?
-- Kristal oyunun para birimi; harcamalarin tamami onunla yapiliyor. Demir/Altin
-- gibi madenler ise 4. sonuc kumesinde tesis bazinda ayrica raporlaniyor.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_GetPlayerStats
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @KristalId INT = (SELECT Id FROM ResourceTypes WHERE Code = N'KRISTAL');

    -- ------------------------------------------------------------------
    -- 1) OZET (tek satir)
    --
    -- CASE WHEN ... THEN Amount ELSE 0 END uzerinden SUM: tek tablo taramasiyla
    -- hem kazanci hem harcamayi hesaplar. Iki ayri sorgu yazmaya gerek yok.
    -- ABS(): harcamalar negatif kayitli oldugu icin pozitife cevriliyor.
    -- ------------------------------------------------------------------
    SELECT
        u.Username,
        u.CreatedAt AS JoinedAt,

        ISNULL((SELECT SUM(CASE WHEN t.Amount > 0 THEN t.Amount ELSE 0 END)
                FROM Transactions t
                WHERE t.UserId = @UserId AND t.ResourceTypeId = @KristalId), 0) AS TotalEarned,

        ISNULL((SELECT SUM(CASE WHEN t.Amount < 0 THEN ABS(t.Amount) ELSE 0 END)
                FROM Transactions t
                WHERE t.UserId = @UserId AND t.ResourceTypeId = @KristalId), 0) AS TotalSpent,

        ISNULL((SELECT pr.Amount FROM PlayerResources pr
                WHERE pr.UserId = @UserId AND pr.ResourceTypeId = @KristalId), 0) AS CurrentKristal,

        (SELECT COUNT(*) FROM Transactions t
         WHERE t.UserId = @UserId AND t.Reason = N'CLICK') AS ClickCount,

        (SELECT COUNT(*) FROM Transactions t
         WHERE t.UserId = @UserId AND t.Reason = N'COLLECT') AS CollectCount,

        (SELECT COUNT(*) FROM Transactions t
         WHERE t.UserId = @UserId AND t.Reason = N'AD_REWARD') AS AdCount,

        ISNULL((SELECT SUM(pf.Level) FROM PlayerFacilities pf WHERE pf.UserId = @UserId), 0) AS TotalLevels,
        ISNULL((SELECT SUM(pm.Count) FROM PlayerMiners pm WHERE pm.UserId = @UserId), 0) AS TotalMiners,
        (SELECT COUNT(*) FROM PlayerFacilities pf WHERE pf.UserId = @UserId) AS FacilityCount,

        (SELECT MAX(t.CreatedAt) FROM Transactions t WHERE t.UserId = @UserId) AS LastActionAt
    FROM Users u
    WHERE u.Id = @UserId;

    -- ------------------------------------------------------------------
    -- 2) HARCAMA DAGILIMI — Kristal nereye gitti?
    -- ------------------------------------------------------------------
    SELECT
        t.Reason,
        SUM(ABS(t.Amount)) AS Total,
        COUNT(*) AS Times
    FROM Transactions t
    WHERE t.UserId = @UserId
      AND t.ResourceTypeId = @KristalId
      AND t.Amount < 0
    GROUP BY t.Reason
    ORDER BY Total DESC;

    -- ------------------------------------------------------------------
    -- 3) KAZANC DAGILIMI — Kristal nereden geldi?
    -- ------------------------------------------------------------------
    SELECT
        t.Reason,
        SUM(t.Amount) AS Total,
        COUNT(*) AS Times
    FROM Transactions t
    WHERE t.UserId = @UserId
      AND t.ResourceTypeId = @KristalId
      AND t.Amount > 0
    GROUP BY t.Reason
    ORDER BY Total DESC;

    -- ------------------------------------------------------------------
    -- 4) TESIS OZETI — hangi tesis ne kadar uretti?
    --
    -- Uretim kaydi tesis bazinda degil KAYNAK bazinda tutuluyor; her tesis
    -- kendi kaynagini urettigi icin kaynak uzerinden tesise baglanabiliyoruz.
    -- CLICK ve COLLECT: madenin iki gelis yolu (elle kazma ve madenci toplama).
    -- ------------------------------------------------------------------
    SELECT
        ft.Id AS FacilityTypeId,
        ft.Name AS FacilityName,
        pf.Level,
        rt.Name AS ResourceName,

        ISNULL((SELECT SUM(t.Amount) FROM Transactions t
                WHERE t.UserId = @UserId
                  AND t.ResourceTypeId = ft.ResourceTypeId
                  AND t.Reason IN (N'CLICK', N'COLLECT')), 0) AS TotalMined,

        ISNULL((SELECT SUM(pm.Count) FROM PlayerMiners pm
                WHERE pm.UserId = @UserId AND pm.FacilityTypeId = ft.Id), 0) AS MinerCount
    FROM PlayerFacilities pf
    JOIN FacilityTypes ft ON ft.Id = pf.FacilityTypeId
    JOIN ResourceTypes rt ON rt.Id = ft.ResourceTypeId
    WHERE pf.UserId = @UserId
    ORDER BY ft.DisplayOrder;

    -- ------------------------------------------------------------------
    -- 5) SIRALAMA — sp_GetLeaderboard ile ayni servet tanimi
    --    (Kristal + her madenin miktari x birim degeri)
    -- ------------------------------------------------------------------
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
    SELECT sr.Position, sr.TotalWealth,
           (SELECT COUNT(*) FROM Users WHERE IsActive = 1) AS TotalPlayers
    FROM Sirali sr
    WHERE sr.UserId = @UserId;
END
GO

PRINT '11_oyuncu_istatistikleri.sql tamamlandi. sp_GetPlayerStats hazir.';
GO
