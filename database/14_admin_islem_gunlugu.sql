-- ============================================================================
-- PROJE: MinerInMine
-- ADIM 14: Yonetici Islem Gunlugu (denetim izinin okunmasi)
--
--   sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i 14_admin_islem_gunlugu.sql
--
-- NEDEN BU SCRIPT VAR?
-- 12. adimda AdminActions tablosunu olusturduk ve yonetim eylemlerini oraya
-- yazmaya basladik. Ama YAZILAN hicbir yerde OKUNMUYORDU. Denetim izi,
-- okunamiyorsa denetim izi degildir; sadece yer kaplayan bir tablodur.
--
-- IKI KAYNAK, TEK LISTE
-- Yonetici mudahaleleri iki ayri yerde duruyor ve bunun iyi bir sebebi var:
--   * Kaynak duzeltmeleri -> Transactions (Reason = ADMIN_ADJUST)
--     Cunku bir KAYNAK HAREKETIDIR; bakiye gecmisinin parcasi olmak zorunda.
--   * Diger eylemler      -> AdminActions
--     Cunku dondurma/rol verme islemlerinin ResourceTypeId ve Amount
--     karsiligi yok; Transactions'a zorlamak tabloyu kirletirdi.
--
-- Insan gozu icin ikisi TEK LISTE olmali. Cozum: UNION ALL ile ortak bir
-- sekilde birlestirip tarihe gore siralamak. Veriyi tek tabloda tutmak yerine
-- SORGUDA birlestiriyoruz — her tablo kendi isine sadik kaliyor.
-- ============================================================================

USE MinerInMineDb;
GO

-- ============================================================================
-- sp_AdminGetActionLog — son yonetici mudahaleleri
--
-- UNION ALL vs UNION: UNION tekrar eden satirlari ayiklamak icin fazladan
-- siralama/karsilastirma yapar. Burada iki kaynakta ayni satir olamaz,
-- o yuzden UNION ALL hem dogru hem ucuz.
-- ============================================================================
CREATE OR ALTER PROCEDURE sp_AdminGetActionLog
    @Top INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF @Top < 1 OR @Top > 200 SET @Top = 50;

    SELECT TOP (@Top) *
    FROM (
        -- 1. Kaynak disi eylemler
        SELECT
            a.CreatedAt,
            ad.Username AS AdminUsername,
            t.Id        AS TargetUserId,
            t.Username  AS TargetUsername,
            a.Action,
            a.Detail
        FROM AdminActions a
        JOIN Users ad ON ad.Id = a.AdminUserId
        JOIN Users t  ON t.Id  = a.TargetUserId

        UNION ALL

        -- 2. Kaynak duzeltmeleri (islemi yapan admin ReferenceId'de tutuluyor)
        SELECT
            tr.CreatedAt,
            ISNULL(ad.Username, N'(bilinmiyor)') AS AdminUsername,
            u.Id       AS TargetUserId,
            u.Username AS TargetUsername,
            N'ADJUST'  AS Action,
            CASE WHEN tr.Amount > 0 THEN N'+' ELSE N'' END
                + CAST(tr.Amount AS NVARCHAR(20)) + N' ' + rt.Name AS Detail
        FROM Transactions tr
        JOIN Users u ON u.Id = tr.UserId
        JOIN ResourceTypes rt ON rt.Id = tr.ResourceTypeId
        LEFT JOIN Users ad ON ad.Id = tr.ReferenceId
        WHERE tr.Reason = N'ADMIN_ADJUST'
    ) AS Birlesik
    ORDER BY CreatedAt DESC;
END
GO

PRINT '14_admin_islem_gunlugu.sql tamamlandi. sp_AdminGetActionLog hazir.';
GO
