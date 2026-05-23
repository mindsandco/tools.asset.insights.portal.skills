# Data Access

EF Core 10 on Npgsql against PostgreSQL, NodaTime for all time types, FusionCache-backed second-level cache, and strongly-typed IDs throughout.

## DbContext

Single `ManagementDbContext` (or `<Product>DbContext`) under `Persistence/`. Configurations are discovered from the assembly that owns `EntityBase<>`:

```csharp
public class ManagementDbContext(DbContextOptions<ManagementDbContext> options) : DbContext(options)
{
    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(Assembly.GetAssembly(typeof(EntityBase<>))!);
        base.OnModelCreating(modelBuilder);
    }
}
```

Always inject `IDbContextFactory<ManagementDbContext>`, never the context directly. Pool size and connection string are configured via the `Asset.Insights.Portal.Npgsql` extension during startup.

## Repository pattern

```csharp
public class GatewayRepository(
    IDbContextFactory<ManagementDbContext> contextFactory,
    IClock clock)
    : IGatewayRepository
{
    public async Task<Gateway?> GetGatewayAsync(GatewayId id, CancellationToken token)
    {
        await using var db = await contextFactory.CreateDbContextAsync(token);

        return await db.Set<GatewayEntity>()
                       .AsNoTracking()
                       .Where(g => g.Id == id)
                       .Select(g => g.ToDomain())
                       .FirstOrDefaultAsync(token);
    }

    public async Task<GatewayId> UpsertGatewayAsync(Gateway gateway, CancellationToken token)
    {
        await using var db = await contextFactory.CreateDbContextAsync(token);

        var strategy = db.Database.CreateExecutionStrategy();

        return await strategy.ExecuteAsync(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(token);

            var entity = await db.Set<GatewayEntity>()
                                 .FirstOrDefaultAsync(g => g.Id == gateway.Id, token)
                                 ?? new GatewayEntity { Id = gateway.Id };

            entity.Apply(gateway, clock.GetCurrentInstant());
            db.Set<GatewayEntity>().Update(entity);

            await db.SaveChangesAsync(token);
            await tx.CommitAsync(token);

            return entity.Id;
        });
    }
}
```

Key points:

- One `DbContext` per logical operation, created from the factory, disposed via `await using`.
- `AsNoTracking()` for every read path. Domain projection (`Select(e => e.ToDomain())`) happens in the query, not after materialisation.
- For multi-statement writes, **always** wrap in `CreateExecutionStrategy().ExecuteAsync(...)` plus an explicit transaction — Npgsql's retry policy can replay the entire delegate.

## Strongly-typed IDs

Defined under `Models/Ids/` as `readonly record struct`. EF binding lives in an `IEntityTypeConfiguration<T>`:

```csharp
public readonly record struct GatewayId(Guid Value)
{
    public static GatewayId New() => new(Guid.NewGuid());
    public override string ToString() => Value.ToString();
}

internal sealed class GatewayEntityConfiguration : IEntityTypeConfiguration<GatewayEntity>
{
    public void Configure(EntityTypeBuilder<GatewayEntity> builder)
    {
        builder.HasKey(g => g.Id);

        builder.Property(g => g.Id)
               .HasConversion(id => id.Value, value => new GatewayId(value));

        builder.Property(g => g.Name).IsRequired().HasMaxLength(256);
        builder.Property(g => g.CreatedAt).IsRequired();
    }
}
```

GraphQL surfaces the typed ID via the registered scalar (HotChocolate sees the `record struct`).

## NodaTime

- Use `Instant` for UTC timestamps, `LocalDate` for calendar dates, `Duration` for elapsed times. Avoid `DateTime` / `DateTimeOffset` in new code.
- Inject `IClock` — never `SystemClock.Instance` — so tests can pin time with `FakeClock`.
- Connection strings configured via `Asset.Insights.Portal.Npgsql` enable NodaTime EF support and `Npgsql.EntityFrameworkCore.PostgreSQL.NodaTime`; columns map automatically (`timestamptz` → `Instant`, `date` → `LocalDate`, …).

## Domain vs entity

- **Domain records** under `Models/` — exposed to GraphQL, controllers, services.
- **EF entities** under `Models/Entities/` — only touched inside repositories. Convention: every entity has a `ToDomain()` extension and an `Apply(domain, instant)` mutator.
- Never return an entity from a service or expose it through GraphQL.

## Audit fields via interceptor

`CoreEntitySaveChangesInterceptor` (in `Persistence/`) stamps `CreatedAt`/`ModifiedAt`/`CreatedBy`/`ModifiedBy` automatically on entities that implement the audit interface. Don't set these manually in repositories — let the interceptor do it.

## Second-level cache

`EFCoreSecondLevelCacheInterceptor.FusionCache` is wired by `AddCaching(daprOptions)`. To opt a query in:

```csharp
return await db.Set<RoleEntity>()
               .AsNoTracking()
               .Cacheable(CacheExpirationMode.Sliding, TimeSpan.FromMinutes(5))
               .Select(r => r.ToDomain())
               .ToListAsync(token);
```

Cache invalidation is automatic on writes through the same `DbContext`. For cross-process invalidation, the FusionCache+Dapr backplane handles fan-out.

## Bulk and streaming reads

For large result sets (export endpoints, workers), prefer `AsAsyncEnumerable()` + `await foreach`. For very large blobs, use the `NpgsqlLargeObjectManager` (already imported from `Asset.Insights.Portal.Npgsql`) — see `ApplicationRepository` for the canonical pattern.

## Do NOT

- Inject `ManagementDbContext` directly. Always go through `IDbContextFactory<>`.
- Track entities in read paths — `AsNoTracking()` is the default expectation.
- Skip `CreateExecutionStrategy()` on writes; transient Npgsql faults will surface as test flakiness.
- Hand-roll EF migrations — schema changes are SQL files in the `Db` project (see `migrations.md`).
- Use `DateTime.UtcNow` or `Instant.FromDateTimeUtc(DateTime.UtcNow)` — inject `IClock`.
