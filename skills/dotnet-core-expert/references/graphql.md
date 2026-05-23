# GraphQL (HotChocolate 16)

The portal's primary read/write surface for domain entities. Built on HotChocolate 16, integrated with EF Core via `HotChocolate.Data.EntityFramework`, and uses GreenDonut for batching.

## Conventions

- **Queries/Mutations are `static partial class` types** annotated with `[QueryType]` or `[MutationType]`. The `HotChocolate.Types.Analyzers` source generator discovers and registers them — never add manual `.AddType<>()` calls.
- File-per-aggregate naming: `ApplicationQueries.cs`, `ApplicationMutations.cs`, `GatewayQueries.cs`, etc. One static class per file.
- Methods are `public static async Task<…>` with dependencies injected via `[Service]`, and **always** terminated by a `CancellationToken token`.
- Authorization is declared with `[Authorize]` at the class or method level. Role checks: `[Authorize(Roles = [Constants.Features.MARKETPLACE_WRITE])]`. Use the existing constants — don't hardcode role strings.
- Filtering and sorting: `[UseFiltering]` and `[UseSorting]` on collection queries. The IQueryable returned is rewritten by HotChocolate against the request.
- Pagination is **cursor-based** via `PageConnection<T>` returned from `PagingArguments` + `QueryContext<T>`. Never use `[UseOffsetPaging]`.

## Query template

```csharp
[QueryType]
[Authorize]
public static partial class FieldQueries
{
    /// <summary>Get a single Field by id.</summary>
    public static Task<Field?> GetFieldAsync(
        [Service] IFieldService fieldService,
        FieldId id,
        CancellationToken token) =>
        fieldService.GetFieldAsync(id, token);

    /// <summary>Get a page of Fields.</summary>
    [UseFiltering]
    [UseSorting]
    public static async Task<PageConnection<Field>> GetFieldsAsync(
        [Service] IFieldService fieldService,
        PagingArguments pagingArguments,
        QueryContext<Field>? queryContext,
        CancellationToken token)
    {
        var page = await fieldService.GetFieldsAsync(pagingArguments, queryContext, token);
        return new PageConnection<Field>(page);
    }
}
```

## Mutation template

```csharp
[MutationType]
[Authorize(Roles = [Constants.Features.MARKETPLACE_WRITE])]
public static partial class ApplicationMutations
{
    /// <summary>Install a previously uploaded application.</summary>
    public static Task<Application?> InstallApplicationAsync(
        [Service] IApplicationService applicationService,
        ApplicationId id,
        CancellationToken token) =>
        applicationService.InstallApplicationAsync(id, token);
}
```

Mutations should accept either strongly-typed IDs or a single **Input record** (`record InstallApplicationInput(ApplicationId Id, …)`) — never a long list of scalars.

## Cursor pagination — the right primitives

```csharp
// Service layer signature
Task<Page<Application>> GetApplicationsAsync(
    PagingArguments pagingArguments,
    QueryContext<Application>? queryContext,
    CancellationToken token);

// Repository layer — let GreenDonut + HotChocolate.Data translate the IQueryable
public async Task<Page<Application>> GetApplicationsAsync(
    PagingArguments pagingArguments,
    QueryContext<Application>? queryContext,
    CancellationToken token)
{
    await using var db = await contextFactory.CreateDbContextAsync(token);

    return await db.Set<ApplicationEntity>()
                   .AsNoTracking()
                   .Select(a => a.ToDomain())
                   .With(queryContext)              // applies filtering/sorting from HotChocolate
                   .ToPageAsync(pagingArguments, token);
}
```

For non-Guid cursor keys (e.g. `Instant`, `string`), register the matching serializer at startup — see the existing `InstantCursorKeySerializer`, `GuidTypedValueCursorKeySerializer`, `StringTypedValueCursorKeySerializer` files.

## DataLoaders

For N+1 patterns (loading children per parent in a paged query), add a DataLoader under `GraphQL/DataLoaders/`. Generate them with HotChocolate's `[DataLoader]` attribute on a static method — the source generator emits the class.

```csharp
internal static class RoleDataLoaders
{
    [DataLoader]
    public static async Task<IReadOnlyDictionary<RoleId, Role>> GetRolesByIdAsync(
        IReadOnlyList<RoleId> ids,
        IDbContextFactory<ManagementDbContext> contextFactory,
        CancellationToken token)
    {
        await using var db = await contextFactory.CreateDbContextAsync(token);
        return await db.Set<RoleEntity>()
                       .Where(r => ids.Contains(r.Id))
                       .Select(r => r.ToDomain())
                       .ToDictionaryAsync(r => r.Id, token);
    }
}
```

## Types

Custom GraphQL types live under `GraphQL/Types/`. Use `ObjectType<T>` only when you need to override field visibility, add resolvers, or customise descriptions. Otherwise rely on HotChocolate's reflection over the domain record.

Register NodaTime scalars via `HotChocolate.Types.NodaTime` (already wired by `AddGraphQl`).

## Error handling

Throw domain exceptions from services; the global `GraphQlErrorFilter` (under `GraphQL/`) translates them. Don't write try/catch inside query/mutation methods.

## Do NOT

- Add HotChocolate offset paging.
- Return EF entity types — return domain records.
- Use `IResolverContext` directly unless extending the schema (rare). Inject services via `[Service]`.
- Manually call `services.AddType<…>()` — let the source generator handle it.
- Hardcode role strings — use `Constants.Features.*`.
