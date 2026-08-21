using System.Reflection;
using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using MinerInMine.Api.Data;
using MinerInMine.Api.Hubs;
using MinerInMine.Api.Options;
using MinerInMine.Api.Services;

// ============================================================================
// MinerInMine API — Uygulama Giriş Noktası
//
// .NET 6+ ile birlikte Startup.cs kaldırıldı; tüm yapılandırma bu tek dosyada
// yapılıyor. Dosya iki bölümden oluşur:
//   1) SERVİS KAYDI    (builder.Services...)  -> "hangi sınıflar var?"
//   2) MIDDLEWARE ZİNCİRİ (app.Use...)        -> "istek hangi sırayla işlenecek?"
// ============================================================================

var builder = WebApplication.CreateBuilder(args);

// ============================================================================
// 1) SERVİS KAYITLARI (Dependency Injection Container)
//
// DEPENDENCY INJECTION NEDİR?
// Sınıflar ihtiyaç duydukları nesneleri kendileri "new" ile üretmez; constructor'da
// isterler, container onlara verir. Faydası: sınıflar somut sınıflara değil
// ARAYÜZLERE bağlanır → test etmek ve değiştirmek kolaylaşır.
//
// YAŞAM SÜRELERİ:
//   Singleton -> uygulama boyunca tek nesne (durumu olmayan, ayarları sabit servisler)
//   Scoped    -> her HTTP isteği için yeni nesne (veritabanına dokunan servisler)
//   Transient -> her istendiğinde yeni nesne
// ============================================================================

// appsettings.json'daki "Jwt" bölümünü JwtSettings sınıfına bağla (Options Pattern).
builder.Services.Configure<JwtSettings>(
    builder.Configuration.GetSection(JwtSettings.SectionName));

// Durumu olmayan yardımcı servisler → Singleton yeterli ve daha performanslı.
builder.Services.AddSingleton<IPasswordHasher, PasswordHasher>();
builder.Services.AddSingleton<ITokenService, TokenService>();
builder.Services.AddSingleton<IAdSignatureService, AdSignatureService>();
builder.Services.AddSingleton<ISqlConnectionFactory, SqlConnectionFactory>();

// İstek başına çalışan, veritabanına dokunan servisler → Scoped.
builder.Services.AddScoped<IUserRepository, UserRepository>();
builder.Services.AddScoped<IAuthService, AuthService>();
builder.Services.AddScoped<IGameRepository, GameRepository>();
builder.Services.AddScoped<IAdminRepository, AdminRepository>();
builder.Services.AddScoped<IChatRepository, ChatRepository>();
builder.Services.AddScoped<IGameService, GameService>();

builder.Services.AddControllers();

// SignalR: canli sohbet icin WebSocket altyapisi.
builder.Services.AddSignalR();

// ----------------------------------------------------------------------------
// 2) JWT KİMLİK DOĞRULAMA
// Gelen her istekte Authorization header'ındaki token'ı okuyup doğrular.
// ----------------------------------------------------------------------------
var jwtSettings = builder.Configuration.GetSection(JwtSettings.SectionName).Get<JwtSettings>()
    ?? throw new InvalidOperationException("appsettings.json içinde 'Jwt' bölümü eksik!");

builder.Services
    .AddAuthentication(options =>
    {
        // Varsayılan kimlik doğrulama yöntemi: "Bearer token"
        options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
        options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
    })
    .AddJwtBearer(options =>
    {
        // --------------------------------------------------------------------
        // ÇOK ÖNEMLİ AYAR: Claim isim haritalamasını kapatıyoruz.
        //
        // SORUN: .NET varsayılan olarak token'daki KISA claim isimlerini eski
        // WS-Federation standardındaki UZUN URI'lere çevirir:
        //   "sub"  -> "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"
        //   "role" -> "http://schemas.microsoft.com/ws/2008/06/identity/claims/role"
        // Bu durumda controller'da User.FindFirst("sub") HER ZAMAN null döner,
        // çünkü claim'in adı artık "sub" değildir. (Bu tuzağa bu projede de
        // düştük: /api/users/me ilk denemede 401 verdi.)
        //
        // MapInboundClaims = false demek: "token'a ne yazdıysam claim olarak
        // aynen onu oku". Böylece kod, token'ın gerçek içeriğiyle birebir uyuşur.
        //
        // NOT: .NET 8 ile birlikte doğrulamayı JsonWebTokenHandler yapıyor.
        // Eski örneklerde göreceğiniz
        //   JwtSecurityTokenHandler.DefaultInboundClaimTypeMap.Clear();
        // satırı .NET 8'de ARTIK ETKİSİZDİR; doğru yöntem aşağıdaki ayardır.
        // --------------------------------------------------------------------
        options.MapInboundClaims = false;

        options.TokenValidationParameters = new TokenValidationParameters
        {
            // İmza doğru mu? (Token'ın değiştirilmediğinin kanıtı — EN KRİTİK kontrol)
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSettings.Key)),

            // Token'ı biz mi ürettik, bizim istemcimiz için mi üretildi?
            ValidateIssuer = true,
            ValidIssuer = jwtSettings.Issuer,
            ValidateAudience = true,
            ValidAudience = jwtSettings.Audience,

            // Süresi dolmuş mu?
            ValidateLifetime = true,

            // ClockSkew varsayılan olarak 5 DAKİKADIR: yani 15 dakikalık token
            // aslında 20 dakika geçerli olur. Sunucu saat farklarını tolere etmek için
            // vardır. Öğrenirken kafa karıştırmasın diye sıfırlıyoruz — token tam
            // 15. dakikada geçersiz olsun.
            ClockSkew = TimeSpan.Zero,

            // TokenService'te kısa claim isimleri kullandık; hangi claim'in "rol",
            // hangisinin "isim" olduğunu ASP.NET'e burada söylüyoruz.
            // [Authorize(Roles = "Admin")] tam olarak RoleClaimType'a bakar.
            RoleClaimType = "role",
            NameClaimType = "name"
        };

        // --------------------------------------------------------------------
        // SIGNALR ICIN ZORUNLU AYAR: token'i sorgu dizesinden de oku.
        //
        // SORUN: Tarayicinin WebSocket API'si ISTEK BASLIGI GONDEREMEZ.
        // Siradan HTTP isteklerinde token "Authorization: Bearer ..." basligiyla
        // gidiyor; WebSocket el sikismasinda boyle bir imkan yok. Bu yuzden
        // SignalR token'i adres satirina koyar: /hubs/chat?access_token=...
        //
        // Asagidaki olay, istek bir hub adresine gidiyorsa token'i oradan alip
        // dogrulama zincirine verir. Bu ayar olmadan hub'a yapilan her baglanti
        // 401 doner ve sohbet hic calismaz.
        //
        // GUVENLIK NOTU: Adres satirindaki token sunucu gunluklerine dusebilir.
        // Riski sinirlayan sey access token'in kisa omurlu (15 dakika) olmasi
        // ve yenileme token'inin ayri, HttpOnly cookie'de durmasi.
        // --------------------------------------------------------------------
        options.Events = new JwtBearerEvents
        {
            OnMessageReceived = context =>
            {
                var accessToken = context.Request.Query["access_token"];

                if (!string.IsNullOrEmpty(accessToken) &&
                    context.HttpContext.Request.Path.StartsWithSegments("/hubs"))
                {
                    context.Token = accessToken;
                }

                return Task.CompletedTask;
            }
        };
    });

builder.Services.AddAuthorization();

// ----------------------------------------------------------------------------
// 3) CORS (Cross-Origin Resource Sharing)
//
// Tarayıcı güvenlik kuralı gereği, http://localhost:4200 adresindeki Angular
// uygulaması http://localhost:5080 adresindeki API'ye VARSAYILAN OLARAK istek
// atamaz (farklı port = farklı origin). Bu izni burada açıkça veriyoruz.
//
// NOT: CORS bir tarayıcı korumasıdır. Postman veya Swagger'dan istek atarken
// devreye girmez — bu yüzden Postman çalışırken Angular'ın hata vermesi normaldir.
// ----------------------------------------------------------------------------
const string CorsPolicyName = "AllowAngularClient";
var allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>()
    ?? new[] { "http://localhost:4200" };

builder.Services.AddCors(options =>
{
    options.AddPolicy(CorsPolicyName, policy =>
    {
        policy.WithOrigins(allowedOrigins)
              .AllowAnyHeader()
              .AllowAnyMethod()

              // Refresh token HttpOnly cookie ile tasindigi icin tarayicinin
              // cookie'yi capraz-origin isteklerde gondermesine izin vermeliyiz.
              // DIKKAT: AllowCredentials, AllowAnyOrigin ile BIRLIKTE KULLANILAMAZ —
              // tam da bu yuzden origin listesini acikca yaziyoruz.
              .AllowCredentials();
    });
});

// ----------------------------------------------------------------------------
// 4) SWAGGER + BEARER TOKEN DESTEĞİ
// Bu yapılandırma sayesinde Swagger UI'da sağ üstte 🔒 "Authorize" butonu çıkar
// ve token'ı bir kez girip tüm korumalı uçları test edebiliriz.
// ----------------------------------------------------------------------------
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "MinerInMine API",
        Version = "v1",
        Description = "MinerInMine madencilik oyunu için kimlik doğrulama ve yetkilendirme API'si."
    });

    // a) "Bearer" adında bir güvenlik şeması tanımla → Authorize butonunu doğurur.
    options.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        In = ParameterLocation.Header,
        Description = "Login uçundan aldığınız accessToken'ı buraya yapıştırın. " +
                      "(Başına 'Bearer ' yazmanıza gerek yok, Swagger ekler.)"
    });

    // b) Bu şemayı tüm uçlara uygula → istek atarken token otomatik eklensin.
    options.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference
                {
                    Type = ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            },
            Array.Empty<string>()
        }
    });

    // c) Controller'lardaki /// <summary> yorumlarını Swagger'da göster.
    var xmlFile = $"{Assembly.GetExecutingAssembly().GetName().Name}.xml";
    var xmlPath = Path.Combine(AppContext.BaseDirectory, xmlFile);
    if (File.Exists(xmlPath))
    {
        options.IncludeXmlComments(xmlPath);
    }
});

var app = builder.Build();

// ============================================================================
// 5) MIDDLEWARE ZİNCİRİ
//
// SIRALAMA KRİTİKTİR! Her istek bu sırayla yukarıdan aşağıya işlenir.
// Örneğin UseAuthentication'ı UseAuthorization'dan SONRA yazsaydık, yetki kontrolü
// yapılırken kullanıcının kim olduğu henüz belli olmaz ve her istek 401 alırdı.
// ============================================================================

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/swagger/v1/swagger.json", "MinerInMine API v1");
        options.RoutePrefix = "swagger";     // -> http://localhost:5080/swagger
        options.DocumentTitle = "MinerInMine API";
    });
}

// Geliştirme ortamında HTTPS yönlendirmesini kapalı tutuyoruz: Angular'ın
// self-signed sertifika ile uğraşmaması için düz HTTP (5080) üzerinden çalışıyoruz.
if (!app.Environment.IsDevelopment())
{
    app.UseHttpsRedirection();
}

app.UseCors(CorsPolicyName);   // 1. Tarayıcıya "bu origin'e izin var" de
app.UseAuthentication();       // 2. Token'ı oku, "sen kimsin?" sorusunu cevapla
app.UseAuthorization();        // 3. "Bu işi yapmaya yetkin var mı?" sorusunu cevapla
app.MapControllers();          // 4. İsteği doğru controller metoduna yönlendir

// SignalR hub adresi. Sıra önemli: UseAuthentication/UseAuthorization'dan
// SONRA gelmeli ki [Authorize] hub'da da çalışsın.
app.MapHub<ChatHub>("/hubs/chat");

app.Run();
