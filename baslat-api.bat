@echo off
REM ============================================================================
REM  MinerInMine - Backend (.NET 8 Web API) baslatici
REM
REM  Bu dosyaya cift tiklayarak API'yi ayaga kaldirabilirsiniz.
REM  Kapatmak icin: acilan pencerede Ctrl+C tuslayin veya pencereyi kapatin.
REM
REM  NOT: Bu dosyada Turkce ozel karakter (i, s, g, o, u ustu isaretli)
REM  KULLANILMIYOR. Sebebi: cmd.exe .bat dosyalarini varsayilan olarak ANSI
REM  kod sayfasiyla okur ve UTF-8 kaydedilmis Turkce karakterler bozuk gorunur.
REM ============================================================================

REM %~dp0 = bu .bat dosyasinin bulundugu klasor.
REM Boylece proje nereye tasinirsa tasinsin dosya calisir; sabit yol yazmiyoruz.
cd /d "%~dp0MinerInMine.Api"

echo.
echo  ==========================================
echo    MinerInMine API baslatiliyor...
echo    Swagger: http://localhost:5080/swagger
echo  ==========================================
echo.

REM --launch-profile http : Properties/launchSettings.json icindeki "http"
REM profilini kullanir -> port 5080 + Development ortami + Swagger otomatik acilir.
dotnet run --launch-profile http

REM Program hata verip kapanirsa pencere aninda yok olmasin,
REM hata mesajini okuyabilelim diye bekletiyoruz.
echo.
echo  API durdu.
pause
