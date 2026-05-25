---
name: dotnet-core-expert
description: Use when building modern .NET 10 services with HotChocolate GraphQL, versioned REST controllers, EF Core + PostgreSQL (Npgsql), NodaTime, Dapr sidecar (pub/sub, state, secrets, jobs), DbUp SQL migrations, FusionCache, and BackgroundService workers. Tests with xUnit + NSubstitute + AutoFixture.
license: MIT
metadata:
  author: https://github.com/mindsandco
  version: "2.1.0"
  domain: backend
  triggers: .NET 10, ASP.NET Core, C# 14, HotChocolate, GraphQL, Dapr, EF Core, Npgsql, PostgreSQL, NodaTime, DbUp, FusionCache, Asp.Versioning, BackgroundService
  role: specialist
  scope: implementation
  output-format: code
  related-skills: testcontainers-dotnet, dotnet-code-analyzer, dotnet-csharp-async-patterns, dotnet-csharp-configuration, dotnet-csharp-dependency-injection, dotnet-http-client, dotnet-resilience, jetbrains-lint-pro, devops-engineer
---

# .NET Core Expert

A specialist for building and modifying .NET 10 backend services around a specific stack:

- **HotChocolate 16 GraphQL** as the primary read/write surface, with versioned REST controllers (Asp.Versioning) for external integrations and Dapr endpoints.
- **EF Core 10 on Npgsql** with **NodaTime** for all time types and **strongly-typed IDs** throughout.
- **DbUp** SQL migrations (not EF migrations) tracked in a dedicated `Db` project.
- **Dapr** sidecar for configuration, secrets, pub/sub, state, jobs, and encryption.
- **FusionCache** for L1/L2 caching, with the EF second-level cache interceptor.
- **BackgroundService workers** scheduled with **Cronos**.
- **xUnit + NSubstitute + AutoFixture.Xunit2** for testing, plus EF Core InMemory for unit-level repository tests and `WebApplicationFactory` for integration tests.

This skill is opinionated — every "MUST" and "MUST NOT" reflects a deliberate choice. Diverge from the pattern only with a documented reason.

## Solution shape

Each service follows this layout:

```
src/
  MyService.Api/                # web host: Controllers, GraphQL, Workers, Services, Repository, Persistence, Models
  MyService.Db/                 # numbered .sql files, applied by DbUp
  MyService.Infrastructure/     # external system adapters (identity, blob, etc.)
  Directory.Build.props         # shared build settings
  global.json                   # pinned SDK
  Tests/
    MyService.Api.Tests/        # unit tests
    MyService.Api.Integration.Tests/
```

Services and repositories live **inside the Api project**. The `Infrastructure` project is reserved for adapters around third-party systems. There is **no MediatR**, no CQRS bus, and no separate Application/Domain assembly — just plain service interfaces with repositories.

## Core workflow

1. **Anchor in existing code** — open the nearest matching `*Service.cs`, `*Repository.cs`, `*Queries.cs`, `*Controller.cs`, or `*Worker.cs` and mirror its structure, naming, primary-constructor style, and `CancellationToken` plumbing.
2. **Design the contract** — pick the right surface: GraphQL (preferred for domain entities), REST controller (versioned, for external integrations and Dapr endpoints), or Worker (background/scheduled).
3. **Implement the slice** — strongly-typed IDs, NodaTime for time, `IDbContextFactory<AppDbContext>` for data access, `IClock` for the current instant. Build with `dotnet build`. With `TreatWarningsAsErrors=true`, any analyzer warning fails the build.
4. **Wire it up** — register services in a single `AddServices` extension, add health checks for new external dependencies, validate options with `IValidateOptions<T>` + `ValidateOnStart()`.
5. **Test** — xUnit + NSubstitute + AutoFixture. Run `dotnet test` and fix every failure before continuing.
6. **Migrate the database** — add a new numbered `.sql` file to the `Db` project. Do **not** create EF migrations.

## Reference guide

Load detailed guidance on demand:

| Topic | Reference | Load when |
|-------|-----------|-----------|
| GraphQL | `references/graphql.md` | Adding queries, mutations, types, DataLoaders, cursor pagination |
| Data access | `references/data-access.md` | EF Core + Npgsql, NodaTime, strongly-typed IDs, 2nd-level cache, execution strategies |
| Database migrations | `references/migrations.md` | Adding/renaming SQL scripts in the `Db` project, DbUp wiring |
| Dapr & configuration | `references/dapr.md` | Pub/sub, state, secrets, jobs, encryption, Options pattern, UserSecrets |
| Workers | `references/workers.md` | BackgroundService, Cronos schedules, Dapr Jobs, startup filters |
| Authentication & rate limiting | `references/authentication.md` | JWT Bearer + Dapr auth, per-user rate limits, authorization policies and HotChocolate roles |
| Testing | `references/testing.md` | xUnit + NSubstitute + AutoFixture, EF Core InMemory, integration tests |

## MUST DO

- Target `net10.0`. Pin the SDK in `src/global.json`.
- Keep `<Nullable>enable</Nullable>` and `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>` in `Directory.Build.props`. Prefer `<ImplicitUsings>disable</ImplicitUsings>` so every `using` is explicit.
- Use **strongly-typed IDs** (e.g. `OrderId`, `UserId`, `TenantId`) defined as `readonly record struct` instead of `Guid` or `int`. Place them under `Models/Ids/`.
- Use **NodaTime** for time: `Instant`, `LocalDate`, `Duration`, `IClock`. Inject `IClock` — never call `SystemClock.Instance` directly. Configure JSON via `ConfigureForNodaTime(DateTimeZoneProviders.Tzdb)`.
- Inject `IDbContextFactory<AppDbContext>` and create a context per operation: `await using var db = await contextFactory.CreateDbContextAsync(token);`. Never inject `DbContext` directly.
- Wrap multi-step writes in `db.Database.CreateExecutionStrategy().ExecuteAsync(...)` plus an explicit transaction — Npgsql's retry policy can replay the delegate.
- Name `CancellationToken` parameters `token` (not `ct` or `cancellationToken`), pass them everywhere, and accept them in every public async method.
- Prefer **primary constructors** for services, repositories, and workers: `public class OrderService(IOrderRepository repo, IClock clock) : IOrderService`.
- Use **records** for DTOs/inputs/outputs and **`readonly record struct`** for strongly-typed IDs.
- GraphQL types: write `[QueryType]` / `[MutationType]` `public static partial class` with `static` methods that take dependencies via `[Service]`. The `HotChocolate.Types.Analyzers` source generator wires them up.
- Cursor pagination via `PagingArguments` + `QueryContext<T>` + `PageConnection<T>` (HotChocolate.Data + GreenDonut.Data). Never use `[UseOffsetPaging]`.
- Validate options with `AddOptions<T>().Bind(section).ValidateDataAnnotations().ValidateOnStart()` and a dedicated `IValidateOptions<T>` for cross-field rules.
- Migrations are **DbUp SQL files** in the `Db` project. Name them `NNN - description.sql` (zero-padded, ordered). Make each file idempotent (`IF NOT EXISTS`, etc.).
- Configuration comes from **UserSecrets locally** and **Dapr in deployed environments**. Add an MSBuild target that fails the build if `appsettings*.json` is committed.
- Tests use **xUnit + NSubstitute + AutoFixture.Xunit2**, parameterised with `[Theory]` + an AutoFixture data attribute and `[Frozen]` for the dependency under test. No Moq, no FluentAssertions, no FakeItEasy.

## MUST NOT DO

- Don't introduce **MediatR**, CQRS handlers, or a separate domain/application assembly. The stack uses plain service interfaces with repositories.
- Don't write **minimal APIs**. Use Controllers (versioned via Asp.Versioning) for REST surfaces, GraphQL for everything else.
- Don't add **EF Core migrations** (`dotnet ef migrations add`). Schema changes go through DbUp `.sql` files in the `Db` project.
- Don't commit `appsettings*.json`. Use UserSecrets locally and Dapr configuration providers in deployed environments.
- Don't return EF **entity types** (`*Entity`) from services or GraphQL. Map to the domain model (`Order`, `User`, etc.) defined under `Models/`.
- Don't inject `DbContext` directly — always use `IDbContextFactory<AppDbContext>`.
- Don't use `DateTime` / `DateTimeOffset` for new fields. Use NodaTime `Instant`/`LocalDate`/`Duration`. Legacy fields can stay until refactored.
- Don't use `Guid` or `int` for entity identifiers in new code. Define a strongly-typed ID.
- Don't suppress analyzer warnings ad hoc. Fix the code, or add a documented project-wide `NoWarn` in `Directory.Build.props`.
- Don't bypass the rate limiter or auth policies. New endpoints inherit the global limiter and must opt into `[Authorize]` or `[Authorize(Roles = [...])]`.
- Don't test against EF Core InMemory **and then claim integration coverage**. InMemory belongs in unit tests; real-database scenarios go in the integration test project.

## Canonical patterns (read these first)

### GraphQL query

```csharp
[QueryType]
[Authorize]
public static partial class OrderQueries
{
    /// <summary>Get an Order by id.</summary>
    public static Task<Order?> GetOrderAsync(
        [Service] IOrderService orderService,
        OrderId id,
        CancellationToken token) =>
        orderService.GetOrderAsync(id, token);

    /// <summary>Get a paged list of Orders.</summary>
    [UseFiltering]
    [UseSorting]
    [Authorize(Roles = [Roles.OrdersRead])]
    public static async Task<PageConnection<Order>> GetOrdersAsync(
        [Service] IOrderService orderService,
        PagingArguments pagingArguments,
        QueryContext<Order>? queryContext,
        CancellationToken token)
    {
        var page = await orderService.GetOrdersAsync(pagingArguments, queryContext, token);
        return new PageConnection<Order>(page);
    }
}
```

### Service + repository

```csharp
public interface IOrderService
{
    Task<Order?> GetOrderAsync(OrderId id, CancellationToken token);
    Task<Page<Order>> GetOrdersAsync(PagingArguments pagingArguments,
                                     QueryContext<Order>? queryContext,
                                     CancellationToken token);
}

public class OrderService(IOrderRepository repository, IClock clock) : IOrderService
{
    public Task<Order?> GetOrderAsync(OrderId id, CancellationToken token) =>
        repository.GetOrderAsync(id, token);

    public Task<Page<Order>> GetOrdersAsync(PagingArguments pagingArguments,
                                            QueryContext<Order>? queryContext,
                                            CancellationToken token) =>
        repository.GetOrdersAsync(pagingArguments, queryContext, token);
}
```

### Repository against `IDbContextFactory`

```csharp
public class OrderRepository(IDbContextFactory<AppDbContext> contextFactory, IClock clock)
    : IOrderRepository
{
    public async Task<Order?> GetOrderAsync(OrderId id, CancellationToken token)
    {
        await using var db = await contextFactory.CreateDbContextAsync(token);
        return await db.Set<OrderEntity>()
                       .AsNoTracking()
                       .Where(o => o.Id == id)
                       .Select(o => o.ToDomain())
                       .FirstOrDefaultAsync(token);
    }
}
```

### Strongly-typed ID

```csharp
public readonly record struct OrderId(Guid Value)
{
    public static OrderId New() => new(Guid.NewGuid());
    public override string ToString() => Value.ToString();
}
```

### Test

```csharp
public class OrderServiceTests
{
    [Theory, AutoNSubstituteData]
    public async Task GetOrderAsync_ReturnsOrder_WhenRepositoryHasIt(
        [Frozen] IOrderRepository repository,
        OrderService sut,
        OrderId id,
        Order expected,
        CancellationToken token)
    {
        repository.GetOrderAsync(id, token).Returns(expected);

        var result = await sut.GetOrderAsync(id, token);

        Assert.Same(expected, result);
    }
}
```

`AutoNSubstituteData` is a thin `AutoDataAttribute` that registers `AutoFixture.AutoNSubstitute.AutoNSubstituteCustomization` — see `references/testing.md` for the one-time setup.

## Output template

When implementing a feature, deliver in this order:

1. **Domain model** — record under `Models/`, strongly-typed ID under `Models/Ids/`, EF entity under `Models/Entities/` if persisted, mapping between them.
2. **Repository** — interface + implementation under `Repository/`, against `IDbContextFactory<AppDbContext>`.
3. **Service** — interface + implementation under `Services/`, orchestrating repositories, `IClock`, Dapr, etc.
4. **API surface** — GraphQL `Queries`/`Mutations` (preferred) and/or `Controllers/V1/...` for REST.
5. **DI wiring** — register in the existing `AddServices` extension method.
6. **Database migration** — new `NNN - description.sql` file in the `Db` project if schema changes.
7. **Tests** — unit tests in `*.Api.Tests` mirroring the service folder structure; integration tests in `*.Api.Integration.Tests` when needed.
8. **Short rationale** — note any deviations from the canonical patterns and why.
