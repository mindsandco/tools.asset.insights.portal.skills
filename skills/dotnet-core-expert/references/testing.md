# Testing

Two projects per service, both targeting `net10.0` with `Nullable=enable`:

- `MyService.Api.Tests` — fast unit tests against services, repositories (with EF Core InMemory), GraphQL resolvers.
- `MyService.Api.Integration.Tests` — full host with `WebApplicationFactory<Program>`, real PostgreSQL via Testcontainers, Dapr stubbed.

## Required packages

```xml
<PackageReference Include="xunit" Version="2.*" />
<PackageReference Include="xunit.runner.visualstudio" Version="3.*">
  <PrivateAssets>all</PrivateAssets>
</PackageReference>
<PackageReference Include="Microsoft.NET.Test.Sdk" Version="18.*" />
<PackageReference Include="coverlet.collector" Version="10.*">
  <PrivateAssets>all</PrivateAssets>
</PackageReference>

<PackageReference Include="NSubstitute" Version="5.*" />
<PackageReference Include="AutoFixture" Version="4.*" />
<PackageReference Include="AutoFixture.Xunit2" Version="4.*" />
<PackageReference Include="AutoFixture.AutoNSubstitute" Version="4.*" />

<PackageReference Include="Microsoft.EntityFrameworkCore.InMemory" Version="10.*" />
<PackageReference Include="NodaTime.Testing" Version="3.*" />

<!-- integration tests only -->
<PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="10.*" />
<PackageReference Include="Testcontainers.PostgreSql" Version="3.*" />
```

## Stack rules

- **xUnit** (`xunit` 2.x). Don't mix in NUnit or MSTest.
- **NSubstitute** for mocking. **No Moq, no FakeItEasy.**
- **AutoFixture.Xunit2** + **AutoFixture.AutoNSubstitute** for test-data generation.
- **EF Core InMemory** in unit tests; **real PostgreSQL** (Testcontainers) in integration tests.
- Assertions: plain `Assert.*`. Don't introduce FluentAssertions.

## AutoFixture data attribute

Define a single attribute once per test project so every `[Theory]` reads the same way:

```csharp
public sealed class AutoNSubstituteDataAttribute : AutoDataAttribute
{
    public AutoNSubstituteDataAttribute()
        : base(() => new Fixture().Customize(new AutoNSubstituteCustomization
        {
            ConfigureMembers = true,
            GenerateDelegates = true
        })) { }
}

public sealed class InlineAutoNSubstituteDataAttribute(params object[] values)
    : InlineAutoDataAttribute(new AutoNSubstituteDataAttribute(), values);
```

For richer test data (NodaTime, strongly-typed IDs, etc.), wrap the fixture in a customisation:

```csharp
public sealed class DomainCustomization : ICustomization
{
    public void Customize(IFixture fixture)
    {
        fixture.Customize<Instant>(c => c.FromFactory(() => Instant.FromUnixTimeSeconds(Random.Shared.NextInt64(0, 2_000_000_000))));
        fixture.Customize<OrderId>(c => c.FromFactory(() => OrderId.New()));
        // ...
    }
}

public sealed class AutoNSubstituteDataAttribute : AutoDataAttribute
{
    public AutoNSubstituteDataAttribute()
        : base(() => new Fixture()
            .Customize(new AutoNSubstituteCustomization { ConfigureMembers = true })
            .Customize(new DomainCustomization())) { }
}
```

## `[Frozen]` + `sut` pattern

`[Frozen]` reuses the same instance for that type across the parameter list — perfect for the dependency under test.

```csharp
public class OrderServiceTests
{
    [Theory, AutoNSubstituteData]
    public async Task GetOrderAsync_ReturnsOrder_WhenRepositoryReturnsIt(
        [Frozen] IOrderRepository repository,
        OrderService sut,
        OrderId id,
        Order expected,
        CancellationToken token)
    {
        repository.GetOrderAsync(id, token).Returns(expected);

        var result = await sut.GetOrderAsync(id, token);

        Assert.Same(expected, result);
        await repository.Received(1).GetOrderAsync(id, token);
    }
}
```

Rules:

- The system-under-test is named `sut` and appears as a constructor-injected parameter; AutoFixture builds it.
- Dependencies you want to control are `[Frozen]` interfaces; AutoNSubstitute supplies the substitutes.
- Domain inputs (`OrderId`, `Order`, etc.) are also test data — AutoFixture generates them.
- `CancellationToken token` is always the last parameter, both in production and test signatures.

## Naming

`Method_Expectation_Condition`:

```
SubmitOrderAsync_ThrowsValidationException_WhenAddressIsMissing
GetOrderAsync_ReturnsNull_WhenOrderDoesNotExist
CleanupExpiredAsync_DeletesEntries_OlderThanRetention
```

## Repository tests against EF Core InMemory

```csharp
[Theory, AutoNSubstituteData]
public async Task GetOrderAsync_ReturnsDomain_WhenEntityExists(
    OrderEntity entity,
    CancellationToken token)
{
    var options = new DbContextOptionsBuilder<AppDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString())
        .Options;

    var factory = new PooledDbContextFactory<AppDbContext>(options);

    await using (var seed = await factory.CreateDbContextAsync(token))
    {
        seed.Add(entity);
        await seed.SaveChangesAsync(token);
    }

    var sut = new OrderRepository(factory, new FakeClock(Instant.FromUtc(2025, 1, 1, 0, 0)));

    var order = await sut.GetOrderAsync(entity.Id, token);

    Assert.NotNull(order);
    Assert.Equal(entity.Id, order!.Id);
}
```

InMemory is sufficient for query shape and projection tests. Anything involving:

- PostgreSQL-specific operators (`jsonb`, full-text, `ILIKE`).
- The execution strategy / transaction code paths.
- Save-changes interceptors (e.g. audit fields).

belongs in the integration test project against real PostgreSQL.

## GraphQL tests

Test the underlying service, not the HotChocolate plumbing — the static `[QueryType]` methods are thin delegations. For integration-level GraphQL coverage, hit the live schema through `HttpClient` from a `WebApplicationFactory`.

## Integration tests

```csharp
public sealed class OrderIntegrationTests : IClassFixture<AppApiFactory>
{
    private readonly AppApiFactory _factory;

    public OrderIntegrationTests(AppApiFactory factory) => _factory = factory;

    [Fact]
    public async Task GET_orders_returns_seeded_data()
    {
        var client = _factory.CreateAuthenticatedClient();
        var response = await client.GetAsync("/api/v1/orders");

        response.EnsureSuccessStatusCode();
        var page = await response.Content.ReadFromJsonAsync<OrderPageDto>();
        Assert.NotEmpty(page!.Items);
    }
}
```

`AppApiFactory` (in `*.Integration.Tests`) extends `WebApplicationFactory<Program>` and:

- Starts a PostgreSQL container via Testcontainers, applies DbUp scripts.
- Swaps the Dapr client for a test double.
- Issues real JWTs via a test issuer for `CreateAuthenticatedClient`.

Re-use a single factory per project — don't roll a new one per fixture.

## NodaTime in tests

Inject `FakeClock` from `NodaTime.Testing`:

```csharp
var clock = new FakeClock(Instant.FromUtc(2025, 1, 1, 0, 0, 0));
```

Pin time deliberately; never let tests depend on `Instant.Now` or wall-clock drift.

## Coverage and CI

`coverlet.collector` produces coverage on `dotnet test`. Wire it into your build pipeline (NUKE, GitHub Actions, etc.) to upload results. Don't add per-test `[Trait]` filters unless excluding a slow integration test from the inner loop.

## Do NOT

- Add Moq, FluentAssertions, or FakeItEasy. Stick with NSubstitute + xUnit assertions.
- Test directly against HotChocolate's runtime when you can exercise the underlying service.
- Use `Thread.Sleep` or arbitrary `await Task.Delay` to "let work settle". Block on the specific signal you care about.
- Mix unit and integration concerns in the same project — InMemory + `WebApplicationFactory` in one test class is a smell.
- Skip `CancellationToken` plumbing in tests; pass the xUnit-provided token through, just like production code.
