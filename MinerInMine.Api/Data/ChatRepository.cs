using System.Data;
using Dapper;
using MinerInMine.Api.Dtos;

namespace MinerInMine.Api.Data;

/// <summary>sp_SendChatMessage ham ciktisi: RETURN kodu + OUTPUT mesaj + yayinlanacak satir.</summary>
public record ChatSendDbResult(int ReturnCode, string? ErrorMessage, ChatMessageDto? Data);

public interface IChatRepository
{
    Task<ChatSendDbResult> SendAsync(int userId, string body);
    Task<List<ChatMessageDto>> GetHistoryAsync(int? top = null);
}

/// <summary>
/// Sohbet veri erisimi. Projenin geri kalaninda oldugu gibi yalnizca
/// stored procedure cagriliyor; ham SQL yok.
/// </summary>
public class ChatRepository : IChatRepository
{
    private readonly ISqlConnectionFactory _factory;

    public ChatRepository(ISqlConnectionFactory factory) => _factory = factory;

    /// <summary>
    /// Mesaji kaydeder ve yayinlanacak tam halini doner.
    ///
    /// Spam siniri ve bos mesaj kontrolu SP icinde: arayuz atlanabilir
    /// (Postman, curl), veritabani atlanamaz.
    /// </summary>
    public async Task<ChatSendDbResult> SendAsync(int userId, string body)
    {
        using var connection = _factory.CreateConnection();

        var p = new DynamicParameters();
        p.Add("@UserId", userId, DbType.Int32);
        p.Add("@Body", body, DbType.String, size: 300);
        p.Add("@ErrorMessage", dbType: DbType.String, size: 255, direction: ParameterDirection.Output);
        p.Add("@ReturnValue", dbType: DbType.Int32, direction: ParameterDirection.ReturnValue);

        var data = await connection.QuerySingleOrDefaultAsync<ChatMessageDto>(
            "sp_SendChatMessage", p, commandType: CommandType.StoredProcedure);

        return new ChatSendDbResult(
            p.Get<int>("@ReturnValue"), p.Get<string?>("@ErrorMessage"), data);
    }

    /// <summary>Son N mesaj, eskiden yeniye sirali (ekranda dogru sirada dizilsin).</summary>
    public async Task<List<ChatMessageDto>> GetHistoryAsync(int? top = null)
    {
        using var connection = _factory.CreateConnection();

        var rows = await connection.QueryAsync<ChatMessageDto>(
            "sp_GetChatHistory",
            new { Top = top },
            commandType: CommandType.StoredProcedure);

        return rows.ToList();
    }
}
