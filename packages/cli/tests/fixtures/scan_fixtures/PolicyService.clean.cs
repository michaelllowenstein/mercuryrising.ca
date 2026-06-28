// Clean fixture — no scan rule violations
public class PolicyService
{
    private readonly IConfiguration _config;
    public PolicyService(IConfiguration config) => _config = config;

    public async Task<Policy> BindAsync(int policyId, CancellationToken ct = default)
    {
        var connectionString = _config["ConnectionStrings:Default"];
        return await _repository.GetAsync(policyId, ct);
    }
}