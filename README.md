# MinerInMine

Madencilik temalı bir oyun projesi. Oyuncular kayıt olup giriş yapıyor, her oyuncuya
seviye, altın ve kazım gücü değerlerini tutan bir profil açılıyor.

Bu aşamada projenin kimlik doğrulama ve yetkilendirme altyapısı tamamlanmış durumda:
kayıt olma, giriş yapma, JWT ile korunan uçlar ve rol bazlı erişim çalışıyor.
Oyun mekaniği geliştirme aşamasında.

## Teknolojiler

**Veritabanı**
- SQL Server Express
- Stored procedure (tüm veritabanı erişimi SP üzerinden)

**Backend**
- .NET 8 / ASP.NET Core Web API
- Dapper
- JWT Bearer authentication
- Swagger

**Frontend**
- Angular 21 (standalone, zoneless)
- TypeScript
- Reactive Forms
- RxJS
