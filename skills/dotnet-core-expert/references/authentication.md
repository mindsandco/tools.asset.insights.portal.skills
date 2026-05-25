# Authentication, Authorization & Rate Limiting

JWT Bearer is the primary scheme, with a parallel Dapr scheme for sidecar-originated calls. Authorization combines ASP.NET policies (for controllers) and HotChocolate `[Authorize(Roles = [...])]` (for GraphQL). Rate limiting is per-user and global.

## Required packages

```xml
<PackageReference Include="Microsoft.AspNetCore.Authentication.JwtBearer" Version="10.*" />
<PackageReference Include="Dapr.AspNetCore" Version="1.17.*" />
<PackageReference Include="NWebsec.AspNetCore.Middleware" Version="3.*" />
<PackageReference Include="HtmlSanitizer" Version="9.*" />
```

## JWT Bearer

```csharp
var authenticationBuilder = builder.Services.AddAuthentication("Bearer");
authenticationBuilder.AddJwtBearer(e =>
{
    e.Authority = appOptions.Authentication.Authority;
    e.RequireHttpsMetadata = !builder.Environment.IsDevelopment();
    e.TokenValidationParameters = new TokenValidationParameters
    {
        ValidAudiences = appOptions.Authentication.Audiences,
        ValidIssuers   = appOptions.Authentication.Issuers,
        ValidateIssuer = true,
        ValidateAudience = appOptions.Authentication.Audiences.Length > 0
    };
    e.Events = new JwtBearerEvents
    {
        OnTokenValidated      = OnTokenValidated,
        OnAuthenticationFailed = OnAuthenticationFailed
    };
})
.AddDapr();
```

- **Authority / audiences / issuers** are bound from `AppOptions:Authentication` and validated by `AppOptionsValidation` at boot.
- `RequireHttpsMetadata` is disabled only when `builder.Environment.IsDevelopment()` — never weaken it elsewhere.
- The Dapr scheme is registered alongside Bearer to authenticate sidecar-initiated calls (pub/sub topics, jobs).

### OnTokenValidated

Use this hook to enrich the principal with app-specific claims (object id, tenant, feature flags). It must:

- Be async-safe (`OnTokenValidated` returns `Task`).
- Log failures via the request-scoped logger from `context.HttpContext.RequestServices`.
- Never block on synchronous database calls — go through a service.

### OnAuthenticationFailed

Map known failures (`SecurityTokenExpiredException`, `SecurityTokenInvalidSignatureException`) to deterministic responses; let unknown exceptions propagate to the global exception middleware.

## Authorization

### Policies (controllers)

```csharp
builder.Services.AddAuthorization(options =>
    options.AddPolicy("default", policy => policy.RequireAuthenticatedUser()));
```

Apply at controller level:

```csharp
[Authorize(Policy = "default")]
[ApiController]
[Route("api/v{version:apiVersion}/[controller]")]
public sealed class OrderController(IOrderService service) : ControllerBase { ... }
```

For role-specific authorization use `[Authorize(Roles = Roles.OrdersWrite)]` — strings live in a `Roles` static class, never inlined.

```csharp
public static class Roles
{
    public const string OrdersRead  = "orders:read";
    public const string OrdersWrite = "orders:write";
    public const string Admin       = "admin";
}
```

### GraphQL

```csharp
[QueryType]
[Authorize]
public static partial class OrderQueries
{
    [Authorize(Roles = [Roles.OrdersRead])]
    public static Task<PageConnection<Order>> GetOrdersAsync(...) { ... }
}
```

The HotChocolate `[Authorize]` attribute reads from the same ASP.NET principal — there is no separate identity store.

### Anonymous endpoints

Allowed surfaces:

- Health checks (`/healthz`, `/readyz`) — wired with `AllowAnonymous`.
- OpenAPI / Banana Cake Pop in development only.
- Dapr internal endpoints (secured via the Dapr API token, not JWT).

Add new anonymous routes only with explicit security review.

## Rate limiting

Global limiter partitions on the most specific identifier available:

```csharp
builder.Services.AddRateLimiter(opt =>
{
    opt.RejectionStatusCode = 429;
    opt.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.User.FindFirst("oid")?.Value
                       ?? context.User.Identity?.Name
                       ?? context.Connection.RemoteIpAddress?.ToString()
                       ?? context.Request.Headers.Host.ToString(),
            factory: _ => new FixedWindowRateLimiterOptions
            {
                AutoReplenishment = true,
                PermitLimit = appOptions.RateLimit.PermitLimit,
                QueueLimit  = appOptions.RateLimit.QueueLimit,
                Window      = appOptions.RateLimit.Window
            }));
});
```

- The partition key falls back gracefully: stable object-id claim (`"oid"` for Azure AD; pick your IdP's equivalent) → name → IP → host.
- Window / permit / queue limits come from `AppOptions.RateLimit`.
- Dapr-internal endpoints bypass the limiter (the sidecar is trusted).
- New endpoints inherit the global limiter automatically. To disable for a specific (high-frequency, low-risk) endpoint, attach `[DisableRateLimiting]`.

## Security middleware

In addition to auth:

- `NWebsec.AspNetCore.Middleware` — HSTS (365d, includeSubdomains, preload), XFO same-origin, XSS protection.

  ```csharp
  if (!app.Environment.IsDevelopment())
  {
      app.UseHsts(o => o.MaxAge(365).IncludeSubdomains().Preload());
      app.UseHttpsRedirection();
  }
  app.UseXfo(o => o.SameOrigin());
  app.UseXXssProtection(o => o.EnabledWithBlockMode());
  ```

- `HtmlSanitizer` (`Ganss.Xss`) — register as a singleton `IHtmlSanitizer`; use for any user-provided HTML before persisting or rendering.

## Claim conventions

Pick stable identifiers from the IdP and use them consistently:

- **Object id**: stable user identifier — `"oid"` (Azure AD/Entra), `"sub"` (generic OIDC), or your IdP's equivalent. Use this as the user key everywhere, including the rate limit partition.
- Standard `name`, `email`, `role` claims as projected by the identity provider.

## Do NOT

- Hardcode role strings — they live in a `Roles` static class.
- Set `RequireHttpsMetadata = false` in any non-development environment.
- Bypass the global rate limiter for new endpoints without a documented rationale.
- Validate JWTs manually — use the standard `JwtBearer` events.
- Mix policy names across projects — keep a canonical `default` policy and add new ones only when their requirements truly differ.
