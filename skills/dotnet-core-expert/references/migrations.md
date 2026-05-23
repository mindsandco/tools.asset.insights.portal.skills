# Database migrations (DbUp)

Schema and data migrations live in the `MyService.Db` project as numbered `.sql` files. DbUp applies them in lexicographic order and tracks state in a `SchemaVersion` table.

## Required packages

```xml
<PackageReference Include="dbup-postgresql" Version="7.*" />
```

In the `Db` project, embed every `.sql` file as a resource:

```xml
<ItemGroup>
  <EmbeddedResource Include="**\*.sql" />
</ItemGroup>
```

## Adding a new migration

1. Open `src/MyService.Db/` and find the highest existing number, e.g. `037 - …sql`.
2. Create `038 - Add foo column.sql` (zero-padded to **three digits**, space-hyphen-space, sentence case, ends with `.sql`).
3. Write idempotent PostgreSQL: `IF NOT EXISTS`, `DO $$ … $$`, `ALTER TABLE … IF EXISTS`. Never assume a clean slate.
4. Confirm the file is included in the build (the wildcard `EmbeddedResource` glob handles this).
5. **Do not modify existing migrations.** Once a file has been merged to `main` it is sealed; correcting fields means writing a new follow-up migration.

## Naming examples

```
001 - Customers.sql
002 - Orders.sql
003 - Order items.sql
004 - Add address columns.sql
005 - Backfill legacy emails.sql
006 - Alter Order status enum.sql
```

Pick a description that reads as a changelog entry — "Add X", "Alter Y", "Backfill Z".

## SQL conventions

- Schema: `public` (configurable per service if needed).
- Table and column names: `PascalCase`. EF mappings will match.
- Use `uuid` for typed-ID columns, mapped back to the strongly-typed ID via `HasConversion` in the EF configuration.
- Use `timestamptz` for `Instant` columns and `date` for `LocalDate`. The NodaTime Npgsql provider handles the rest.
- DbUp opens a transaction per script by default; explicit `BEGIN`/`COMMIT` makes intent visible for non-trivial scripts.

Example skeleton:

```sql
-- 038 - Add Description column to Order.sql

ALTER TABLE "Order"
    ADD COLUMN IF NOT EXISTS "Description" varchar(1024) NULL;

UPDATE "Order"
   SET "Description" = ''
 WHERE "Description" IS NULL;

ALTER TABLE "Order"
    ALTER COLUMN "Description" SET NOT NULL;
```

## DbUp runner

`Persistence/DatabaseMigration/DbMigration.cs` implements `IStartupFilter` so migrations run before any traffic is served:

```csharp
public sealed class DbMigration(
    IOptionsMonitor<ConnectionStrings> options,
    ILogger<DbMigration> logger)
    : IStartupFilter
{
    private const string DB_SCHEMA = "public";
    private const string DB_TABLE  = "SchemaVersion";

    public Action<IApplicationBuilder> Configure(Action<IApplicationBuilder> next)
    {
        var upgrader = DeployChanges.To
            .PostgresqlDatabase(options.CurrentValue.AppDb)
            .WithScriptsEmbeddedInAssembly(typeof(MyService.Db.Marker).Assembly)
            .JournalToPostgresqlTable(DB_SCHEMA, DB_TABLE)
            .LogTo(new DbUpLoggerAdapter(logger))
            .WithTransactionPerScript()
            .Build();

        var result = upgrader.PerformUpgrade();
        if (!result.Successful)
        {
            logger.LogError(result.Error, "Database migration failed.");
            throw new InvalidOperationException("Database migration failed.", result.Error);
        }

        return next;
    }
}
```

`MyService.Db.Marker` is a tiny empty class in the `Db` project — its only purpose is to give `typeof(...).Assembly` a stable handle. Register the filter as a singleton:

```csharp
services.AddSingleton<IStartupFilter, DbMigration>();
```

You should not need to touch the runner when adding a new migration — just drop the SQL into the `Db` project.

## Backfills

Data-only migrations follow the same numbering. Keep them small and idempotent:

```sql
-- 042 - Backfill Order.PlacedBy for legacy rows.sql

UPDATE "Order"
   SET "PlacedBy" = '00000000-0000-0000-0000-000000000000'
 WHERE "PlacedBy" IS NULL;
```

If a backfill is expensive, gate it on `EXISTS (...)` so reruns are no-ops.

## Local development

DbUp runs on app startup against the connection string supplied via UserSecrets or Dapr config. There is no separate `dotnet ef database update` step. To reset locally: drop the database and start the API; all scripts replay from `001`.

## Do NOT

- Edit, rename, or delete an existing committed migration. Add a new one.
- Use EF migrations (`Migrations/` folder, `IMigrationsAssembly`, `dotnet ef migrations add`). They are not wired up.
- Embed environment-specific values (connection strings, secrets) in SQL — the deployment supplies them.
- Skip `IF NOT EXISTS` / `IF EXISTS` guards — migrations must be safe to re-run if the journal table is wiped.
