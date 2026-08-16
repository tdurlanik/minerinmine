@echo off
REM ============================================================================
REM  MinerInMine - Tam yigin baslatici (Backend + Frontend)
REM
REM  Bu dosyaya cift tiklayin: API ve Angular AYRI AYRI pencerelerde acilir.
REM  Her ikisini de kapatmak icin ilgili pencerelerde Ctrl+C tuslayin.
REM ============================================================================

echo.
echo  MinerInMine baslatiliyor...
echo.

REM start "Baslik" komut  -> yeni bir konsol penceresi acar ve komutu orada calistirir.
REM Boylece iki sunucu birbirini beklemeden es zamanli calisir.
REM Ilk tirnak icindeki metin pencerenin BASLIGIDIR (start komutunun kurali:
REM ilk tirnakli parametreyi her zaman baslik sayar - bu yuzden bos birakilamaz).
start "MinerInMine API" "%~dp0baslat-api.bat"

REM Angular'i biraz gecikmeli baslatiyoruz: API once ayaga kalksin ki
REM tarayici acildiginda ilk istek bosa gitmesin.
REM
REM Neden "timeout" degil de "ping"? timeout komutu klavyeyi dinledigi icin
REM girdisi yonlendirilmis ortamlarda "Input redirection is not supported"
REM hatasi verip patlar. ping -n 4 = 3 saniye bekler ve her yerde calisir.
ping -n 4 127.0.0.1 >nul

start "MinerInMine Client" "%~dp0baslat-client.bat"

echo  Iki pencere acildi:
echo    - API      : http://localhost:5080/swagger
echo    - Uygulama : http://localhost:4200
echo.
echo  Bu pencereyi kapatabilirsiniz.
ping -n 6 127.0.0.1 >nul
