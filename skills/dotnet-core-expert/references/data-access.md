# Data Access

EF Core 10 on Npgsql against PostgreSQL, NodaTime for all time types, FusionCache-backed second-level cache, and strongly-typed IDs throughout.

## Required packages

```xml
<PackageReference Include="Microsoft.EntityFrameworkCore" Version="10.*" />
<PackageReference Include="Npgsql.EntityFrameworkCore.PostgreSQL" Version="10.*" />
<PackageReference Include="Npgsql.EntityFrameworkCore.PostgreSQL.NodaTime" Version="10.*" />
<PackageReference Include="NodaTime" Version="3.*" />
<PackageReference Include="NodaTime.Serialization.SystemTextJson" Version="1.*" />
<PackageReference Include="EFCoreSecondLevelCacheInterceptor.FusionCache" Version="5.*" />
<PackageReference Include="ZiggyCreatures.FusionCache" Version="2.*" />
```

## DbContext

Single `AppDbContext` under `Persistence/`. Configurations are discovered from the assembly that owns your entity base type:

```csharp
public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(Assembly.GetAssembly(typeof(EntityBase<>))!);
        base.OnModelCreating(modelBuilder);
    }
}
```

Register the **factory**, not a scoped context:

```csharp
services.AddPooledDbContextFactory<AppDbContext>((sp, opt) =>
{
    var connectionStrings = sp.GetRequiredService<IOptions<ConnectionStrings>>().Value;
    opt.UseNpgsql(connectionStrings.AppDb, npg => npg.UseNodaTime())
       .AddInterceptors(sp.GetRequiredService<SecondLevelCacheInterceptor>(),
                        sp.GetRequiredService<AuditSaveChangesInterceptor>());
});
```

Always inject `IDbContextFactory<AppDbContext>`, never the context directly.

## Repository pattern

```csharp
public class OrderRepository(
    IDbContextFactory<AppDbContext> contextFactory,
    IClock clock)
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

    public async Task<OrderId> UpsertOrderAsync(Order order, CancellationToken token)
    {
        await using var db = await contextFactory.CreateDbContextAsync(token);

        var strategy = db.Database.CreateExecutionStrategy();

        return await strategy.ExecuteAsync(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(token);

            var entity = await db.Set<OrderEntity>()
                                 .FirstOrDefaultAsync(o => o.Id == order.Id, token)
                                 ?? new OrderEntity { Id = order.Id };

            entity.Apply(order, clock.GetCurrentInstant());
            db.Set<OrderEntity>().Update(entity);

            await db.SaveChangesAsync(token);
            await tx.CommitAsync(token);

            return entity.Id;
        });
    }
}
```

Key points:

- One `DbContext` per logical operation, created from the factory, disposed via `await using`.
- `AsNoTracking()` for every read path. Project to the domain (`Select(e => e.ToDomain())`) **inside the query**, not after materialisation.
- For multi-statement writes, **always** wrap in `CreateExecutionStrategy().ExecuteAsync(...)` plus an explicit transaction — Npgsql's retry policy can replay the entire delegate.

## Strongly-typed IDs

Defined under `Models/Ids/` as `readonly record struct`. EF binding lives in an `IEntityTypeConfiguration<T>`:

```csharp
public readonly record struct OrderId(Guid Value)
{
    public static OrderId New() => new(Guid.NewGuid());
    public override string ToString() => Value.ToString();
}

internal sealed class OrderEntityConfiguration : IEntityTypeConfiguration<OrderEntity>
{
    public void Configure(EntityTypeBuilder<OrderEntity> builder)
    {
        builder.HasKey(o => o.Id);

        builder.Property(o => o.Id)
               .HasConversion(id => id.Value, value => new OrderId(value));

        builder.Property(o => o.Number).IsRequired().HasMaxLength(64);
        builder.Property(o => o.CreatedAt).IsRequired();
    }
}
```

GraphQL surfaces the typed ID via HotChocolate's reflection over the `record struct`.

## NodaTime

- Use `Instant` for UTC timestamps, `LocalDate` for calendar dates, `Duration` for elapsed times. Avoid `DateTime` / `DateTimeOffset` in new code.
- Inject `IClock` — never `SystemClock.Instance` — so tests can pin time with `FakeClock`.
  - Register once: `services.AddSingleton<IClock>(SystemClock.Instance);`
- The `.UseNodaTime()` Npgsql configuration enables EF support; columns map automatically (`timestamptz` → `Instant`, `date` → `LocalDate`, …).
- Configure System.Text.Json for NodaTime in `Program.cs`:

  ```csharp
  builder.Services.AddControllers()
         .AddJsonOptions(opt =>
             opt.JsonSerializerOptions.ConfigureForNodaTime(DateTimeZoneProviders.Tzdb));
  ```

## Domain vs entity

- **Domain records** under `Models/` — exposed to GraphQL, controllers, services.
- **EF entities** under `Models/Entities/` — only touched inside repositories. Convention: every entity has a `ToDomain()` extension and an `Apply(domain, instant)` mutator.
- Never return an entity from a service or expose it through GraphQL.

## Audit fields via interceptor

```csharp
public sealed class AuditSaveChangesInterceptor(IClock clock) : SaveChangesInterceptor
{
    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData,
        InterceptionResult<int> result,
        CancellationToken cancellationToken = default)
    {
        if (eventData.Context is null) return new(result);

        var now = clock.GetCurrentInstant();

        foreach (var entry in eventData.Context.ChangeTracker.Entries<IAuditable>())
        {
            if (entry.State == EntityState.Added)   entry.Entity.CreatedAt = now;
            if (entry.State == EntityState.Modified) entry.Entity.ModifiedAt = now;
        }

        return new(result);
    }
}
```

Register the interceptor as a scoped service and add it via `opt.AddInterceptors(...)` in the `DbContextOptionsBuilder` callback. Don't set `CreatedAt`/`ModifiedAt` by hand inside repositories.

## Second-level cache

`EFCoreSecondLevelCacheInterceptor.FusionCache` provides an EF-level cache on top of FusionCache:

```csharp
services.AddEFSecondLevelCache(opt => opt
    .UseFusionCacheProvider()
    .ConfigureLogging(true)
    .UseCacheKeyPrefix("ef:"));

services.AddFusionCache()
        .WithDefaultEntryOptions(new FusionCacheEntryOptions(TimeSpan.FromMinutes(5)));
```

Opt a query in:

```csharp
return await db.Set<TaxRateEntity>()
               .AsNoTracking()
               .Cacheable(CacheExpirationMode.Sliding, TimeSpan.FromMinutes(5))
               .Select(r => r.ToDomain())
               .ToListAsync(token);
```

Cache invalidation is automatic on writes through the same `DbContext`. For cross-process invalidation, configure a FusionCache backplane (Redis, Dapr, …) — see `dapr.md` for the Dapr-based setup.

## Bulk and streaming reads

For large result sets (export endpoints, workers), prefer `AsAsyncEnumerable()` + `await foreach`. For very large blobs, use Npgsql's `NpgsqlLargeObjectManager` directly.

## Do NOT

- Inject `AppDbContext` directly. Always go through `IDbContextFactory<>`.
- Track entities in read paths — `AsNoTracking()` is the default expectation.
- Skip `CreateExecutionStrategy()` on writes; transient Npgsql faults will surface as test flakiness.
- Hand-roll EF migrations — schema changes are SQL files in the `Db` project (see `migrations.md`).
- Use `DateTime.UtcNow` or `Instant.FromDateTimeUtc(DateTime.UtcNow)` — inject `IClock`.
