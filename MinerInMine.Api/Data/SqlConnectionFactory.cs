using System.Data;
using Microsoft.Data.SqlClient;

namespace MinerInMine.Api.Data;

/// <summary>
/// Bağlantı üretme sorumluluğunu tek bir yere toplayan arayüz.
///
/// NEDEN FABRİKA (Factory) DESENİ?
/// Repository sınıfları connection string'i bilmek zorunda kalmasın diye.
/// Yarın veritabanı sunucusu değişse tek dosyayı değiştiririz.
/// Ayrıca test yazarken bu arayüzü sahte (mock) bir sınıfla değiştirebiliriz.
/// </summary>
public interface ISqlConnectionFactory
{
    IDbConnection CreateConnection();
}

public class SqlConnectionFactory : ISqlConnectionFactory
{
    private readonly string _connectionString;

    // IConfiguration, appsettings.json dosyasını okuyan servistir.
    // ASP.NET bunu Dependency Injection ile otomatik olarak buraya verir.
    public SqlConnectionFactory(IConfiguration configuration)
    {
        _connectionString = configuration.GetConnectionString("Default")
            ?? throw new InvalidOperationException(
                "appsettings.json içinde ConnectionStrings:Default tanımlı değil!");
    }

    /// <summary>
    /// Her çağrıda YENİ bir SqlConnection üretir.
    /// Bağlantıyı burada açmıyoruz; Dapper gerektiğinde kendisi açar.
    /// Kullanan taraf 'using' ile çağırdığı için bağlantı otomatik kapanır ve
    /// ADO.NET'in connection pool'una geri döner (bu yüzden yeni nesne üretmek ucuzdur).
    /// </summary>
    public IDbConnection CreateConnection() => new SqlConnection(_connectionString);
}
