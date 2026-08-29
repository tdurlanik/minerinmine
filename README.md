# MinerInMine

Madencilik temalı bir tarayıcı oyunu. Oyuncu maden kazar, kaynaklarını satar, madenci
işe alıp otomasyona geçer ve yeni tesisler açar. Yanında bir yönetim paneli ve SignalR
ile çalışan canlı sohbet var.

Bir yaz stajı projesi; veritabanından arayüze kadar tek geliştirici tarafından yazıldı.

```
Angular 21  →  nginx  →  ASP.NET Core  →  Stored Procedure  →  SQL Server
```

## Çalıştırma

Tek ön koşul Docker Desktop:

```bash
docker compose up -d --build
```

Veritabanı kurulumu otomatik — `db-init` servisi `database/*.sql` dosyalarını sırayla
uygular. Kurulumu izlemek için `docker compose logs -f db-init`. Uygulama hazır olunca:
**http://localhost:8080**

Durdurmak için `docker compose down`; veriyi de silmek için `-v` ekle.

### Docker olmadan

.NET 8 SDK, Node.js 20+ ve SQL Server Express gerekir.

```bash
# 1. database/ altındaki script'leri 01'den 15'e sırayla çalıştır
sqlcmd -S .\SQLEXPRESS -E -f 65001 -i database/01_create_tables.sql

# 2. API ve arayüz
dotnet run --project MinerInMine.Api --launch-profile http   # :5080/swagger
npm start --prefix minerinmine-client                        # :4200
```

Windows'ta `baslat-docker.bat` ve `baslat-hepsi.bat` aynı işi yapar.

Hazır admin hesabı yok: normal bir hesap açıp `UserRoles` tablosuna o kullanıcı için
`Admin` rolünü eklemen gerekiyor.

## Teknolojiler

| Katman | Kullanılan | Neden |
|---|---|---|
| Veri | SQL Server + stored procedure | Kural veritabanında durursa hiçbir istemciden atlanamaz |
| Erişim | Dapper | Erişim SP üzerinden olduğu için ORM'in sorgu üretimine gerek yok |
| Servis | .NET 8 Web API + DI | Katmanlar somut sınıflara değil arayüzlere bağlı |
| Kimlik | JWT + refresh token | Sunucu oturum tutmasın ama "çıkış yap" gerçekten çalışsın |
| Arayüz | Angular 21 (standalone, zoneless) | Signal tabanlı durum yönetimi |
| Gerçek zaman | SignalR | Sohbette sürekli sorgu yerine açık bağlantı |
| Dağıtım | Docker Compose + nginx | Kurulum tek komut; aynı origin sayesinde CORS yok |

## Yapı

```
MinerInMine.Api/     .NET 8 Web API (Controllers, Services, Data, Hubs)
database/            01'den 15'e sıralı SQL script'leri
minerinmine-client/  Angular 21
tools/               denge simülasyonu — node tools/denge-simulasyonu.js 24 ikisi
postman/             koleksiyon ve ortam dosyası
```

## Bilinen eksikler

- Otomatik test yok; servis birim testleri ve SP'ler için yarış durumu testleri eklenmeli
- Şifre hashleme HMACSHA512 — üretimde PBKDF2 veya Argon2 olmalı
- Gizli anahtarlar ve veritabanı parolası depoda yer tutucu, yalnızca geliştirme için
- Genel rate limiting yok; SignalR tek sunucu varsayıyor (ölçek için Redis backplane)
