// Dirty fixture — intentional violations for test assertions
public class ViolationService
{
    private string _password = "SuperSecret123";            // critical: hardcoded credential
    private string _conn = "Server=prod-sql;Database=PolicyDB;User=sa;Password=abc123"; // error: DB conn string

    public async Task<string> GetDataAsync()               // warning: async without CancellationToken
    {
        // TODO: fix this later
        return await Task.FromResult("data");
    }
}