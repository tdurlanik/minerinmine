@echo off
REM ============================================================================
REM  MinerInMine - Frontend (Angular 21) baslatici
REM
REM  Bu dosyaya cift tiklayarak Angular gelistirme sunucusunu baslatabilirsiniz.
REM  Kapatmak icin: acilan pencerede Ctrl+C tuslayin veya pencereyi kapatin.
REM
REM  DIKKAT: Uygulamanin veri cekebilmesi icin API'nin de calisiyor olmasi
REM  gerekir. Ikisini birden baslatmak icin: baslat-hepsi.bat
REM ============================================================================

cd /d "%~dp0minerinmine-client"

REM Ilk kurulumda node_modules klasoru olmaz; paketleri otomatik yukleyelim ki
REM kullanici "npm install unuttum" hatasiyla ugrasmasin.
if not exist "node_modules" (
    echo.
    echo  Paketler ilk kez yukleniyor, bu birkac dakika surebilir...
    echo.
    call npm install
    if errorlevel 1 (
        echo.
        echo  HATA: npm install basarisiz oldu.
        pause
        exit /b 1
    )
)

echo.
echo  ==========================================
echo    MinerInMine istemcisi baslatiliyor...
echo    Uygulama: http://localhost:4200
echo  ==========================================
echo.

REM "npm start" -> "ng serve" demektir (package.json icinde tanimli).
REM -- --open : cift tire, "bundan sonraki parametreleri ng serve'e ilet" demektir.
REM             --open tarayiciyi otomatik acar.
call npm start -- --open

echo.
echo  Istemci durdu.
pause
