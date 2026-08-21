# ============================================================================
#  MinerInMine API — Docker imajı
#
#  ÇOK AŞAMALI (multi-stage) YAPI
#  İki ayrı imaj kullanıyoruz:
#    1. sdk     -> derlemek için. Derleyici, NuGet, tüm araçlar var (~800 MB)
#    2. aspnet  -> çalıştırmak için. Sadece çalışma zamanı var (~220 MB)
#
#  Neden? Derleyiciye YALNIZCA derlerken ihtiyaç var. Sonuç imajın içinde
#  taşımak, her sunucuya gereksiz yüz megabaytlar göndermek demektir.
#  "FROM ... AS build" ile derler, sonuç dosyaları son aşamaya kopyalarız;
#  ara aşama sonuç imaja girmez.
# ============================================================================

# --------------------------------------------------------------------------
# 1. AŞAMA — derleme
# --------------------------------------------------------------------------
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# ÖNCE SADECE .csproj KOPYALANIYOR. Neden?
# Docker her satırı önbelleğe alır ve bir satır değişmediyse tekrar çalıştırmaz.
# Paket listesi (csproj) değişmediği sürece "restore" adımı önbellekten gelir.
# Bütün kodu baştan kopyalasaydık, tek bir satır kod değişince NuGet paketleri
# de baştan indirilirdi — her derlemede dakikalar.
COPY MinerInMine.Api/MinerInMine.Api.csproj MinerInMine.Api/
RUN dotnet restore MinerInMine.Api/MinerInMine.Api.csproj

# Şimdi kodun geri kalanı
COPY MinerInMine.Api/ MinerInMine.Api/
RUN dotnet publish MinerInMine.Api/MinerInMine.Api.csproj -c Release -o /app/publish

# --------------------------------------------------------------------------
# 2. AŞAMA — çalıştırma
# --------------------------------------------------------------------------
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app

# Yalnızca derleme çıktısını alıyoruz; kaynak kod ve SDK geride kalıyor.
COPY --from=build /app/publish .

# Container içinde 8080'i dinle.
# Geliştirmede 5080 kullanıyorduk; o port launchSettings.json'a aitti ve
# container içinde geçerli değil. Dışarıya hangi portla açılacağına
# docker-compose.yml karar verir.
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "MinerInMine.Api.dll"]
