# ============================================================================
#  MinerInMine istemcisi — Docker imajı
#
#  API'deki ile aynı mantık: derleyen imaj ile çalıştıran imaj ayrı.
#    1. node   -> Angular'ı derler (node_modules ~400 MB, sonuçta gerekmez)
#    2. nginx  -> derlenmiş statik dosyaları sunar (~50 MB)
#
#  ÖNEMLİ AYRIM: Angular bir "sunucu" değildir. `ng serve` yalnızca
#  geliştirme aracıdır; üretimde ortada çalışan bir Node süreci yoktur.
#  Elimizde sadece HTML/CSS/JS dosyaları kalır ve onları herhangi bir
#  statik dosya sunucusu (burada nginx) sunabilir.
# ============================================================================

# --------------------------------------------------------------------------
# 1. AŞAMA — derleme
# --------------------------------------------------------------------------
FROM node:20-alpine AS build
WORKDIR /app

# Önce sadece paket dosyaları (Dockerfile önbelleği için — API'dekiyle aynı
# gerekçe: kaynak kod değişince npm ci baştan çalışmasın).
COPY package.json package-lock.json ./

# npm ci, npm install'ın kurulum sürümü: package-lock.json'a birebir uyar,
# sürümleri kendiliğinden yükseltmez. Yeniden üretilebilir derleme için şart.
RUN npm ci

COPY . .
RUN npm run build

# --------------------------------------------------------------------------
# 2. AŞAMA — sunma
# --------------------------------------------------------------------------
FROM nginx:alpine AS final

# Varsayılan yapılandırmayı kendi ayarımızla değiştiriyoruz
# (API vekilliği + SPA yönlendirmesi + WebSocket başlıkları).
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Angular 21 çıktıyı dist/<proje-adi>/browser altına koyar.
COPY --from=build /app/dist/minerinmine-client/browser /usr/share/nginx/html

EXPOSE 80
