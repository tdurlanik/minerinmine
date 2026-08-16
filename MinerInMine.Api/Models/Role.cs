namespace MinerInMine.Api.Models;

/// <summary>
/// Roles tablosunun C# karşılığı. sp_GetUserRoles bu şekilde bir liste döndürür.
/// JWT token üretilirken her rol, token'ın içine bir "role" claim'i olarak yazılır.
/// </summary>
public class Role
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
}
