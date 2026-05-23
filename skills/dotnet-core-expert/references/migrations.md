# Database migrations (DbUp)

Schema and data migrations live in the `<Product>.Db` project as numbered `.sql` files. DbUp applies them in lexicographic order and tracks state in a `Management_SchemaVersion` table.

## Adding a new migration

1. Open `src/<Product>.Db/` and find the highest existing number, e.g. `037 - …sql`.
2. Create `038 - Add foo column.sql` (zero-padded to **three digits**, space-hyphen-space, sentence case, ends with `.sql`).
3. Write idempotent PostgreSQL: `IF NOT EXISTS`, `DO $$ … $$`, `ALTER TABLE … IF EXISTS`. Never assume a clean slate.
4. Set the file's build action to `Embedded Resource` (the existing csproj already does this with a wildcard — confirm new file matches).
5. **Do not modify existing migrations.** Once a file has been merged to `main` it is sealed; correcting fields means writing a new follow-up migration.

## Naming examples (from the repo)

```
001 - Clients.sql
002 - Roles.sql
003 - Applications.sql
004 - Marketplace and User features.sql
005 - Add path and component.sql
006 - Add type and author columns.sql
007 - Alter Application.sql
008 - Add Field,Gateway,Asset.sql
009 - Add custom properties.sql
010 - Fields - Features.sql
```

Pick a description that reads as a changelog entry — "Add X", "Alter Y", "Backfill Z".

## SQL conventions

- Schema: `public` (the constant lives in `DbMigration.cs` as `DB_SCHEMA`).
- Table and column names: `PascalCase`. EF mappings will match.
- Use `uuid` for typed-ID columns, mapped back to the strongly-typed ID via `HasConversion` in the EF configuration.
- Use `timestamptz` for `Instant` columns and `date` for `LocalDate`. The NodaTime Npgsql provider handles the rest.
- Always wrap DDL that could fail mid-batch in a transaction at the top of the file (`BEGIN; … COMMIT;`) — DbUp opens a transaction per script by default, but explicit `BEGIN`/`COMMIT` makes it visible.

Example skeleton:

```sql
-- 038 - Add description column to Gateway.sql

ALTER TABLE "Gateway"
    ADD COLUMN IF NOT EXISTS "Description" varchar(1024) NULL;

UPDATE "Gateway"
   SET "Description" = ''
 WHERE "Description" IS NULL;

ALTER TABLE "Gateway"
    ALTER COLUMN "Description" SET NOT NULL;
```

## DbUp runner

`Persistence/DatabaseMigration/DbMigration.cs` implements `IStartupFilter`. It:

- Reads the connection string from `IOptionsMonitor<ConnectionStrings>`.
- Logs through `IDbUpLogger` (wraps `ILogger<DbMigration>`).
- Applies all embedded `.sql` resources from the `<Product>.Db` assembly in name order.
- Records each applied script in `public.Management_SchemaVersion`.

The filter is registered as a singleton in the `Api` project's `AddServices`. You should not need to touch this file when adding a new migration — just drop the SQL into the `Db` project.

## Backfills

Data-only migrations follow the same numbering. Keep them small and idempotent:

```sql
-- 042 - Backfill Application.Author for legacy rows.sql

UPDATE "Application"
   SET "Author" = 'unknown'
 WHERE "Author" IS NULL;
```

If a backfill is expensive, gate it on `EXISTS (...)` so reruns are no-ops.

## Local development

DbUp runs on app startup against the connection string supplied via UserSecrets / Dapr config. There is no separate `dotnet ef database update` step. To reset locally: drop the database and start the API; all scripts replay from `001`.

## Do NOT

- Edit, rename, or delete an existing committed migration. Add a new one.
- Use EF migrations (`Migrations/` folder, `IMigrationsAssembly`, `dotnet ef migrations add`). They are not wired up.
- Embed environment-specific values (connection strings, secrets) in SQL — the deployment supplies them.
- Skip `IF NOT EXISTS` / `IF EXISTS` guards — migrations must be safe to re-run if DbUp's history table is wiped.
