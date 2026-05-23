# Testing

Two projects per service, both targeting `net10.0` with `Nullable=enable`:

- `<Product>.Api.Tests` — fast unit tests against services, repositories (with EF Core InMemory), GraphQL resolvers.
- `<Product>.Api.Integration.Tests` — full host with `WebApplicationFactory<Program>`, real PostgreSQL via testcontainers, Dapr stubbed.

## Stack

- **xUnit** (`xunit` 2.x). Don't mix in NUnit or MSTest.
- **NSubstitute** for mocking. **No Moq, no FakeItEasy.**
- **AutoFixture.Xunit2** with the custom `[AutoTestData]` attribute from `Asset.Insights.Portal.TestUtilities`.
- **EF Core InMemory** in unit tests; **real PostgreSQL** (testcontainers) in integration tests.
- Assertions: plain `Assert.*`. The codebase does not standardise on FluentAssertions — don't introduce it.

## `[AutoTestData]` + `[Frozen]`

`[AutoTestData]` is a parameterised AutoFixture attribute that supplies all method parameters. `[Frozen]` reuses the same instance for that type across the parameter list — perfect for the dependency under test.

```csharp
public class AssetServiceTests
{
    [Theory]
    [AutoTestData]
    public async Task GetAssetAsync_ReturnsDomainAsset_WhenRepositoryReturnsIt(
        [Frozen] IAssetRepository repository,
        AssetService sut,
        AssetId id,
        Asset expected,
        CancellationToken token)
    {
        repository.GetAssetAsync(id, token).Returns(expected);

        var result = await sut.GetAssetAsync(id, token);

        Assert.Same(expected, result);
        await repository.Received(1).GetAssetAsync(id, token);
    }
}
```

Rules:

- The system-under-test is named `sut` and appears as a constructor-injected parameter; AutoFixture builds it.
- Dependencies you want to control are `[Frozen]` interfaces; AutoFixture substitutes them via the customisation registered in `Asset.Insights.Portal.TestUtilities`.
- Domain inputs (`AssetId`, `Asset`, etc.) are also test data — AutoFixture creates them.
- `CancellationToken token` is always the last parameter, both in production and test signatures.

## Naming

`Method_Expectation_Condition`:

```
CreateAsync_ThrowsUpdateValidationException_WhenCustomPropertyValueIsTooLong
GetGatewayAsync_ReturnsNull_WhenGatewayDoesNotExist
UploadApplicationAsync_PersistsBlob_AndReturnsId
```

## Repository tests against EF Core InMemory

```csharp
[Theory]
[AutoTestData]
public async Task GetGatewayAsync_ReturnsDomain_WhenEntityExists(
    GatewayEntity entity,
    CancellationToken token)
{
    var options = new DbContextOptionsBuilder<ManagementDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString())
        .Options;

    var factory = new PooledDbContextFactory<ManagementDbContext>(options);

    await using (var seed = await factory.CreateDbContextAsync(token))
    {
        seed.Add(entity);
        await seed.SaveChangesAsync(token);
    }

    var sut = new GatewayRepository(factory, new FakeClock(Instant.FromUtc(2025, 1, 1, 0, 0)));

    var gateway = await sut.GetGatewayAsync(entity.Id, token);

    Assert.NotNull(gateway);
    Assert.Equal(entity.Id, gateway!.Id);
}
```

InMemory is sufficient for query shape and projection tests. Anything involving:

- PostgreSQL-specific operators (`jsonb`, full-text, `ILIKE`).
- The execution strategy / transaction code paths.
- The `CoreEntitySaveChangesInterceptor`.

belongs in the integration test project against real PostgreSQL.

## GraphQL tests

Test the underlying service, not the HotChocolate plumbing — the static `[QueryType]` methods are thin delegations. For integration-level GraphQL coverage, hit the live schema through `HttpClient` from a `WebApplicationFactory`.

## Integration tests

```csharp
public sealed class GatewayIntegrationTests : IClassFixture<ManagementApiFactory>
{
    private readonly ManagementApiFactory _factory;

    public GatewayIntegrationTests(ManagementApiFactory factory) => _factory = factory;

    [Fact]
    public async Task GET_gateways_returns_seeded_data()
    {
        var client = _factory.CreateAuthenticatedClient();
        var response = await client.GetAsync("/api/v1/gateways");

        response.EnsureSuccessStatusCode();
        var page = await response.Content.ReadFromJsonAsync<GatewayPageDto>();
        Assert.NotEmpty(page!.Items);
    }
}
```

`ManagementApiFactory` (in `*.Integration.Tests`) extends `WebApplicationFactory<Program>` and:

- Starts a PostgreSQL container, applies DbUp scripts.
- Swaps the Dapr client for a test double.
- Issues real JWTs via a test issuer for `CreateAuthenticatedClient`.

Re-use the existing factory — don't roll a new one per fixture.

## NodaTime in tests

Inject `FakeClock` from `NodaTime.Testing`:

```csharp
var clock = new FakeClock(Instant.FromUtc(2025, 1, 1, 0, 0, 0));
```

Pin time deliberately; never let tests depend on `Instant.Now` or wall-clock drift.

## Coverage and CI

`coverlet.collector` produces coverage on `dotnet test`. The NUKE build target uploads results. Don't add per-test `[Trait]` filters unless excluding a slow integration test from the inner loop.

## Do NOT

- Add Moq, FluentAssertions, or FakeItEasy. Stick with NSubstitute + xUnit assertions.
- Test directly against HotChocolate's runtime when you can exercise the underlying service.
- Use `Thread.Sleep` or arbitrary `await Task.Delay` to "let work settle". Block on the specific signal you care about.
- Mix unit and integration concerns in the same project — InMemory + WebApplicationFactory in one test class is a smell.
- Skip `CancellationToken` plumbing in tests; pass the xUnit-provided token through, just like production code.
