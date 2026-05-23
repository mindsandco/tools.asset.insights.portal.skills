# GraphQL (HotChocolate 16)

The primary read/write surface for domain entities. Built on HotChocolate 16, integrated with EF Core via `HotChocolate.Data.EntityFramework`, and uses GreenDonut for batching.

## Required packages

```xml
<PackageReference Include="HotChocolate.AspNetCore" Version="16.*" />
<PackageReference Include="HotChocolate.AspNetCore.Authorization" Version="16.*" />
<PackageReference Include="HotChocolate.Data" Version="16.*" />
<PackageReference Include="HotChocolate.Data.EntityFramework" Version="16.*" />
<PackageReference Include="HotChocolate.Diagnostics" Version="16.*" />
<PackageReference Include="HotChocolate.Types.NodaTime" Version="16.*" />
<PackageReference Include="HotChocolate.Types.Analyzers" Version="16.*">
  <PrivateAssets>all</PrivateAssets>
  <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
</PackageReference>
```

`HotChocolate.Types.Analyzers` is the source generator that discovers `[QueryType]` / `[MutationType]` / `[DataLoader]` and emits the registration code.

## Conventions

- **Queries/Mutations are `static partial class` types** annotated with `[QueryType]` or `[MutationType]`. The source generator registers them — never add manual `.AddType<>()` calls.
- File-per-aggregate naming: `OrderQueries.cs`, `OrderMutations.cs`, `CustomerQueries.cs`. One static class per file.
- Methods are `public static async Task<…>` with dependencies injected via `[Service]`, and **always** terminated by a `CancellationToken token`.
- Authorization is declared with `[Authorize]` at the class or method level. Role checks: `[Authorize(Roles = [Roles.OrdersWrite])]`. Define a `Roles` static class — don't hardcode role strings.
- Filtering and sorting: `[UseFiltering]` and `[UseSorting]` on collection queries. The `IQueryable` returned is rewritten by HotChocolate against the request.
- Pagination is **cursor-based** via `PageConnection<T>` returned from `PagingArguments` + `QueryContext<T>`. Never use `[UseOffsetPaging]`.

## Query template

```csharp
[QueryType]
[Authorize]
public static partial class OrderQueries
{
    /// <summary>Get a single Order by id.</summary>
    public static Task<Order?> GetOrderAsync(
        [Service] IOrderService orderService,
        OrderId id,
        CancellationToken token) =>
        orderService.GetOrderAsync(id, token);

    /// <summary>Get a page of Orders.</summary>
    [UseFiltering]
    [UseSorting]
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

## Mutation template

```csharp
[MutationType]
[Authorize(Roles = [Roles.OrdersWrite])]
public static partial class OrderMutations
{
    /// <summary>Submit a draft order.</summary>
    public static Task<Order?> SubmitOrderAsync(
        [Service] IOrderService orderService,
        SubmitOrderInput input,
        CancellationToken token) =>
        orderService.SubmitOrderAsync(input, token);
}

public sealed record SubmitOrderInput(OrderId Id, string Notes);
```

Mutations should accept either strongly-typed IDs or a single **Input record** — never a long flat parameter list.

## Cursor pagination — the right primitives

```csharp
// Service layer signature
Task<Page<Order>> GetOrdersAsync(
    PagingArguments pagingArguments,
    QueryContext<Order>? queryContext,
    CancellationToken token);

// Repository layer — let GreenDonut + HotChocolate.Data translate the IQueryable
public async Task<Page<Order>> GetOrdersAsync(
    PagingArguments pagingArguments,
    QueryContext<Order>? queryContext,
    CancellationToken token)
{
    await using var db = await contextFactory.CreateDbContextAsync(token);

    return await db.Set<OrderEntity>()
                   .AsNoTracking()
                   .Select(o => o.ToDomain())
                   .With(queryContext)              // applies filtering/sorting from HotChocolate
                   .ToPageAsync(pagingArguments, token);
}
```

For non-Guid cursor keys (e.g. `Instant`, `string`), register a matching `ICursorKeySerializer` at startup. HotChocolate ships the common ones; provide your own only for custom value types.

## DataLoaders

For N+1 patterns (loading children per parent in a paged query), add a DataLoader under `GraphQL/DataLoaders/`. Use HotChocolate's `[DataLoader]` attribute on a static method — the source generator emits the class.

```csharp
internal static class CustomerDataLoaders
{
    [DataLoader]
    public static async Task<IReadOnlyDictionary<CustomerId, Customer>> GetCustomersByIdAsync(
        IReadOnlyList<CustomerId> ids,
        IDbContextFactory<AppDbContext> contextFactory,
        CancellationToken token)
    {
        await using var db = await contextFactory.CreateDbContextAsync(token);
        return await db.Set<CustomerEntity>()
                       .Where(c => ids.Contains(c.Id))
                       .Select(c => c.ToDomain())
                       .ToDictionaryAsync(c => c.Id, token);
    }
}
```

Resolvers consume the loader by parameter:

```csharp
public static Task<Customer?> GetCustomerAsync(
    [Parent] Order order,
    ICustomerByIdDataLoader customerLoader,
    CancellationToken token) =>
    customerLoader.LoadAsync(order.CustomerId, token);
```

## Types

Custom GraphQL types live under `GraphQL/Types/`. Use `ObjectType<T>` only when you need to override field visibility, add resolvers, or customise descriptions. Otherwise rely on HotChocolate's reflection over the domain record.

Register NodaTime scalars via `HotChocolate.Types.NodaTime`:

```csharp
services.AddGraphQLServer()
        .AddNodaTime();
```

## Error handling

Throw domain exceptions from services; register a global error filter to translate them. Don't write `try`/`catch` inside query/mutation methods.

```csharp
public sealed class DomainErrorFilter : IErrorFilter
{
    public IError OnError(IError error) => error.Exception switch
    {
        NotFoundException nf       => error.WithMessage(nf.Message).WithCode("NOT_FOUND"),
        ValidationException ve     => error.WithMessage(ve.Message).WithCode("VALIDATION"),
        _                          => error
    };
}

// Registration
services.AddGraphQLServer()
        .AddErrorFilter<DomainErrorFilter>();
```

## Server registration

```csharp
services.AddGraphQLServer()
        .AddAuthorization()
        .AddFiltering()
        .AddSorting()
        .AddProjections()
        .AddNodaTime()
        .AddErrorFilter<DomainErrorFilter>()
        .AddInstrumentation();          // HotChocolate.Diagnostics
```

The source generator picks up `[QueryType]` / `[MutationType]` automatically; you only register cross-cutting concerns here.

## Do NOT

- Add HotChocolate offset paging.
- Return EF entity types — return domain records.
- Use `IResolverContext` directly unless extending the schema (rare). Inject services via `[Service]`.
- Manually call `services.AddType<…>()` — let the source generator handle it.
- Hardcode role strings — use a `Roles` static class.
