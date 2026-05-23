---
name: dotnet-core-expert
description: Use when building Asset Insights Portal .NET 10 services. Invoke for HotChocolate GraphQL endpoints, REST controllers with Asp.Versioning, EF Core + Npgsql + NodaTime data access, DbUp SQL migrations, Dapr sidecar integration (pub/sub, state, secrets, jobs), FusionCache, Workers, and Antire-flavoured testing with xUnit + NSubstitute + AutoFixture.
license: MIT
metadata:
  author: https://github.com/mindandso
  version: "2.0.0"
  domain: backend
  triggers: .NET 10, ASP.NET Core, C# 14, HotChocolate, GraphQL, Dapr, EF Core, Npgsql, NodaTime, DbUp, FusionCache, Asp.Versioning, Workers, Asset Insights Portal
  role: specialist
  scope: implementation
  output-format: code
  related-skills: fullstack-guardian, microservices-architect, test-master
---

# .NET Core Expert (Asset Insights Portal)

A specialist for building and modifying services in the Asset Insights Portal ecosystem (e.g. `app.asset.insights.portal.management`). Patterns are derived from the existing codebase — do not invent alternatives without strong justification.

## Solution shape

Every backend service follows this layout:

```
src/
  <Product>.Api/                # web host: Controllers, GraphQL, Workers, Services, Repository, Persistence, Models
  <Product>.Application/        # React/TypeScript SPA (NOT a C# application layer)
  <Product>.Db/                 # numbered .sql files, applied by DbUp
  <Product>.Infrastructure/     # external system adapters (e.g. Keycloak, file factories)
  Directory.Build.props         # shared build settings + analyzer pack
  global.json                   # pinned SDK
  Tests/
    <Product>.Api.Tests/
    <Product>.Api.Integration.Tests/
```

Services and repositories live **inside the Api project**. The `Infrastructure` project is reserved for adapters around third-party systems (identity, blob, etc.). There is no MediatR, no CQRS bus, no separate Application/Domain assembly.

## Core workflow

1. **Anchor in existing code** — open the nearest matching `*Service.cs`, `*Repository.cs`, `*Queries.cs`, `*Controller.cs`, or `*Worker.cs` and mirror its structure, naming, primary-constructor style, and CancellationToken plumbing.
2. **Design the contract** — pick the right surface: GraphQL (preferred for read/write of domain entities), REST controller (versioned, for external integrations and Dapr endpoints), or Worker (background/scheduled).
3. **Implement the slice** — strongly-typed IDs, NodaTime for time, `IDbContextFactory<ManagementDbContext>` for data access, `IClock` for the current instant. Build with `dotnet build` — `TreatWarningsAsErrors=true` will fail on any analyzer warning.
4. **Wire it up** — register services in the `AddServices` extension, add health checks if a new external dependency is introduced, validate options with `IValidateOptions<T>` + `ValidateOnStart()`.
5. **Test** — xUnit + NSubstitute + AutoFixture with the `[AutoTestData]` attribute from `Asset.Insights.Portal.TestUtilities`. Run `dotnet test` and fix every failure before continuing.
6. **Migrate the database** — add a new numbered `.sql` file to `<Product>.Db`. Do **not** create EF migrations.

## Reference guide

Load detailed guidance on demand:

| Topic | Reference | Load when |
|-------|-----------|-----------|
| GraphQL | `references/graphql.md` | Adding queries, mutations, types, DataLoaders, cursor pagination |
| Data access | `references/data-access.md` | EF Core + Npgsql, NodaTime, strongly-typed IDs, 2nd-level cache, execution strategies |
| Database migrations | `references/migrations.md` | Adding/renaming SQL scripts in the `Db` project, DbUp wiring |
| Dapr & configuration | `references/dapr.md` | Pub/sub, state, secrets, jobs, encryption, Sidekick, Options pattern, UserSecrets |
| Workers | `references/workers.md` | BackgroundService, Cronos schedules, Dapr Jobs, startup filters |
| Authentication & rate limiting | `references/authentication.md` | JWT Bearer + Dapr auth, per-user rate limits, authorization policies and HotChocolate roles |
| Testing | `references/testing.md` | xUnit + NSubstitute + AutoFixture, `[AutoTestData]`, EF Core InMemory, integration tests |

## MUST DO

- Target `net10.0`. Match the SDK pinned in `src/global.json` (`10.0.100` rollForward `latestMinor`).
- Keep `<Nullable>enable</Nullable>` and `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`. `ImplicitUsings` is **disabled** — every `using` is explicit.
- Place the Apache-2.0 copyright header at the top of every new `.cs` file (copy from a sibling file).
- Use **strongly-typed IDs** (`ApplicationId`, `AssetId`, `GatewayId`, `RoleId`, `UserId`, …) instead of `Guid` or `int`. Define new ones under `Models/Ids/` as readonly record structs.
- Use **NodaTime** for time: `Instant`, `LocalDate`, `Duration`, `IClock` (inject, never call `SystemClock.Instance` directly). Configure JSON via `ConfigureForNodaTime(DateTimeZoneProviders.Tzdb)`.
- Inject `IDbContextFactory<ManagementDbContext>` and create a context per operation: `await using var db = await contextFactory.CreateDbContextAsync(token);`. Never inject `DbContext` directly.
- Wrap multi-step writes in `db.Database.CreateExecutionStrategy().ExecuteAsync(...)` + an explicit transaction — needed for Npgsql retry resilience.
- Name CancellationToken parameters `token` (not `ct` or `cancellationToken`), pass them through everywhere, and accept them at every public method.
- Prefer **primary constructors** for services, repositories, and workers: `public class FooService(IFooRepository repo, IClock clock) : IFooService`.
- Use **records** for DTOs/inputs/outputs and **`readonly record struct`** for strongly-typed IDs.
- GraphQL types: write `[QueryType]` / `[MutationType]` `public static partial class` with `static` methods that take dependencies via `[Service]`. The HotChocolate source generator wires them up.
- Cursor pagination via `PagingArguments` + `QueryContext<T>` + `PageConnection<T>` (HotChocolate.Data + GreenDonut.Data). Never write `[UseOffsetPaging]`.
- Validate options with `AddOptions<T>().Bind(section).ValidateDataAnnotations().ValidateOnStart()` and a dedicated `IValidateOptions<T>` for cross-field rules.
- Migrations are **DbUp SQL files** in `<Product>.Db`. Name them `NNN - description.sql` (zero-padded, ordered). Idempotency is the file's responsibility (use `IF NOT EXISTS`, etc.).
- Configuration comes from **UserSecrets locally + Dapr in deployed environments**. The MSBuild `FailOnAppSettings` target will break the build if anyone commits `appsettings*.json`.
- Use the Antire NuGet pack: `Asset.Insights.Portal.AspNetCore.Logging` (observability), `Asset.Insights.Portal.Npgsql` (data primitives), `Asset.Insights.Portal.FusionCache.Dapr` (caching), `Asset.Insights.Portal.GreenDonut.Enumerable` (GraphQL helpers), `Asset.Insights.Portal.Common`, `Asset.Insights.Portal.TestUtilities`. Pin to the version already used across the repo.
- Tests use **xUnit + NSubstitute + AutoFixture.Xunit2**, parameterised with `[Theory] [AutoTestData]` and `[Frozen]` for the dependency under test. No Moq, no FluentAssertions, no FakeItEasy.

## MUST NOT DO

- Don't introduce **MediatR**, CQRS handlers, or a separate domain/application assembly. The codebase uses plain service interfaces with repositories.
- Don't write **minimal APIs**. Use Controllers (versioned via Asp.Versioning) for REST surfaces, GraphQL for everything else.
- Don't add **EF Core migrations** (`dotnet ef migrations add`). Database schema changes go through DbUp `.sql` files in the `Db` project.
- Don't commit `appsettings*.json` — the build will fail. Use `dotnet user-secrets` locally and Dapr config providers in deployed environments.
- Don't return EF **entity types** (`*Entity`) from services or GraphQL. Map to the domain model (`Application`, `Asset`, etc.) defined under `Models/`.
- Don't inject `DbContext` directly — always use `IDbContextFactory<ManagementDbContext>`.
- Don't use `DateTime` / `DateTimeOffset` for new fields. Use NodaTime `Instant`/`LocalDate`/`Duration`. Existing legacy fields can stay until refactored.
- Don't use `Guid` or `int` for entity identifiers in new code. Define a strongly-typed ID.
- Don't suppress analyzer warnings ad hoc. If a Sonar/SecurityCodeScan/IDisposableAnalyzers/Wintellect rule fires, fix the code. Project-wide suppressions belong in `Directory.Build.props` `NoWarn` and need a comment.
- Don't bypass the rate limiter or auth policies. New endpoints inherit the global limiter and must opt into `[Authorize]` or `[Authorize(Roles = [...])]`.
- Don't write tests against EF Core InMemory **and then claim integration coverage**. InMemory belongs in `*.Api.Tests`; real-database scenarios go in `*.Api.Integration.Tests`.

## Canonical patterns (read these first)

### GraphQL query

```csharp
[QueryType]
[Authorize]
public static partial class ApplicationQueries
{
    /// <summary>Get Application by id.</summary>
    public static Task<Application?> GetApplicationAsync(
        [Service] IApplicationService applicationService,
        ApplicationId id,
        CancellationToken token) =>
        applicationService.GetApplicationAsync(id, token);

    /// <summary>Get a paged list of Applications.</summary>
    [UseFiltering]
    [UseSorting]
    [Authorize(Roles = [Constants.Features.MARKETPLACE_WRITE])]
    public static async Task<PageConnection<Application>> GetApplicationsAsync(
        [Service] IApplicationService applicationService,
        PagingArguments pagingArguments,
        QueryContext<Application>? queryContext,
        CancellationToken token)
    {
        var page = await applicationService.GetApplicationsAsync(pagingArguments, queryContext, token);
        return new PageConnection<Application>(page);
    }
}
```

### Service + repository

```csharp
public interface IApplicationService
{
    Task<Application?> GetApplicationAsync(ApplicationId id, CancellationToken token);
    Task<Page<Application>> GetApplicationsAsync(PagingArguments pagingArguments,
                                                 QueryContext<Application>? queryContext,
                                                 CancellationToken token);
}

public class ApplicationService(IApplicationRepository repository, IClock clock) : IApplicationService
{
    public Task<Application?> GetApplicationAsync(ApplicationId id, CancellationToken token) =>
        repository.GetApplicationAsync(id, token);

    public Task<Page<Application>> GetApplicationsAsync(PagingArguments pagingArguments,
                                                       QueryContext<Application>? queryContext,
                                                       CancellationToken token) =>
        repository.GetApplicationsAsync(pagingArguments, queryContext, token);
}
```

### Repository against `IDbContextFactory`

```csharp
public class ApplicationRepository(IDbContextFactory<ManagementDbContext> contextFactory, IClock clock)
    : IApplicationRepository
{
    public async Task<Application?> GetApplicationAsync(ApplicationId id, CancellationToken token)
    {
        await using var db = await contextFactory.CreateDbContextAsync(token);
        return await db.Set<ApplicationEntity>()
                       .AsNoTracking()
                       .Where(a => a.Id == id)
                       .Select(a => a.ToDomain())
                       .FirstOrDefaultAsync(token);
    }
}
```

### Strongly-typed ID

```csharp
public readonly record struct ApplicationId(Guid Value)
{
    public static ApplicationId New() => new(Guid.NewGuid());
    public override string ToString() => Value.ToString();
}
```

### Test

```csharp
public class ApplicationServiceTests
{
    [Theory]
    [AutoTestData]
    public async Task GetApplicationAsync_ReturnsApplication_WhenRepositoryHasIt(
        [Frozen] IApplicationRepository repository,
        ApplicationService sut,
        ApplicationId id,
        Application expected,
        CancellationToken token)
    {
        repository.GetApplicationAsync(id, token).Returns(expected);

        var result = await sut.GetApplicationAsync(id, token);

        Assert.Same(expected, result);
    }
}
```

## Output template

When implementing a feature, deliver in this order:

1. **Domain model** — record under `Models/`, strongly-typed ID under `Models/Ids/`, EF entity under `Models/Entities/` if persisted, mapping between them.
2. **Repository** — interface + implementation under `Repository/`, against `IDbContextFactory<ManagementDbContext>`.
3. **Service** — interface + implementation under `Services/`, orchestrating repositories, `IClock`, Dapr, etc.
4. **API surface** — GraphQL `Queries`/`Mutations` (preferred) and/or `Controllers/V1/...` for REST.
5. **DI wiring** — register in the existing `AddServices` extension method.
6. **Database migration** — new `NNN - description.sql` file in `<Product>.Db` if schema changes.
7. **Tests** — unit tests in `*.Api.Tests` mirroring the service folder structure; integration tests in `*.Api.Integration.Tests` when needed.
8. **Short rationale** — note any deviations from the canonical patterns and why.
