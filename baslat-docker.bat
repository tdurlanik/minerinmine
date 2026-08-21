@echo off
REM ============================================================================
REM  MinerInMine - Docker ile tum sistemi baslatir
REM
REM  Bu dosyaya cift tiklamak yeterlidir. Uc parca da (veritabani, API,
REM  arayuz) ayaga kalkar ve uygulama http://localhost:8080 adresinde acilir.
REM
REM  ONKOSUL: Docker Desktop kurulu ve calisir durumda olmali.
REM
REM  NOT: Bu dosyada Turkce ozel karakter KULLANILMIYOR; cmd.exe .bat
REM  dosyalarini ANSI kod sayfasiyla okur ve UTF-8 karakterler bozulur.
REM ============================================================================

cd /d "%~dp0"

echo.
echo  ==========================================
echo    MinerInMine Docker ile baslatiliyor...
echo  ==========================================
echo.

REM Ilk calistirmada imajlar indirilir/derlenir; birkac dakika surebilir.
REM --build : kod degistiyse imajlari yeniden derler
REM -d      : arka planda calistirir
docker compose up -d --build
if errorlevel 1 (
    echo.
    echo  HATA: Docker calismiyor olabilir. Docker Desktop acik mi?
    pause
    exit /b 1
)

echo.
echo  Veritabani kurulumu izleniyor (db-init)...
echo  "TAMAM: tum scriptler uygulandi" yazisini gorunce hazir demektir.
echo.
docker compose logs -f --tail=20 db-init

echo.
echo  ==========================================
echo    Uygulama: http://localhost:8080
echo  ==========================================
echo.
echo  Durdurmak icin       : docker compose down
echo  Veriyi de silmek icin: docker compose down -v
echo.
pause
