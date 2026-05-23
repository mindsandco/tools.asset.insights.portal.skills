# Authentication, Authorization & Rate Limiting

JWT Bearer is the primary scheme, with a parallel Dapr scheme for sidecar-originated calls. Authorization combines ASP.NET policies (for controllers) and HotChocolate `[Authorize(Roles = [...])]` (for GraphQL). Rate limiting is per-user and global.

## JWT Bearer

```csharp
var authenticationBuilder = builder.Services.AddAuthentication("Bearer");
authenticationBuilder.AddJwtBearer(e =>
{
    e.Authority = managementOptions.Authentication.Authority;
    e.RequireHttpsMetadata = !builder.Environment.IsLocal();
    e.TokenValidationParameters = new TokenValidationParameters
    {
        ValidAudiences = managementOptions.Authentication.Audiences,
        ValidIssuers = managementOptions.Authentication.Issuers,
        ValidateIssuer = true,
        ValidateAudience = managementOptions.Authentication.Audiences.Length > 0
    };
    e.Events = new JwtBearerEvents
    {
        OnTokenValidated = OnTokenValidated,
        OnAuthenticationFailed = OnAuthenticationFailed
    };
})
.AddDapr();
```

- **Authority / audiences / issuers** are bound from `ManagementOptions:Authentication` and validated by `ManagementOptionsValidation` at boot.
- `RequireHttpsMetadata` is disabled only when `builder.Environment.IsLocal()` — never weaken it elsewhere.
- The Dapr scheme is registered alongside Bearer to authenticate sidecar-initiated calls (pub/sub topics, jobs).

### OnTokenValidated

Use this hook to enrich the principal with portal-specific claims (object id, tenant, feature flags). It must:

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
public sealed class GatewayController(IGatewayService service) : ControllerBase { ... }
```

For feature-specific authorization use `[Authorize(Roles = Constants.Features.MARKETPLACE_WRITE)]` — strings live in `Constants.Features.*`, never inlined.

### GraphQL

```csharp
[QueryType]
[Authorize]
public static partial class ApplicationQueries
{
    [Authorize(Roles = [Constants.Features.MARKETPLACE_WRITE])]
    public static Task<PageConnection<Application>> GetApplicationsAsync(...) { ... }
}
```

The HotChocolate `[Authorize]` attribute reads from the same ASP.NET principal — there is no separate identity store.

### Anonymous endpoints

Allowed surfaces:

- Health checks (`/health/live`, `/health/ready`) — wired by `MapHealthChecks` with `AllowAnonymous`.
- OpenAPI / Nitro UI (local + non-production only).
- Dapr internal endpoints (already secured via the Dapr API token).

Add new anonymous routes only with explicit security review.

## Rate limiting

Global limiter partitions on the most specific identifier available:

```csharp
builder.Services.AddRateLimiter(opt =>
{
    opt.RejectionStatusCode = 429;
    opt.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.User.FindFirst(Constants.ClaimTypes.ObjectId)?.Value
                       ?? context.User.Identity?.Name
                       ?? context.Connection.RemoteIpAddress?.ToString()
                       ?? context.Request.Headers.Host.ToString(),
            factory: _ => new FixedWindowRateLimiterOptions
            {
                AutoReplenishment = true,
                PermitLimit = managementOptions.RateLimit.PermitLimit,
                QueueLimit = managementOptions.RateLimit.QueueLimit,
                Window = managementOptions.RateLimit.Window
            }));
});
```

- The partition key falls back gracefully: ObjectId → name → IP → host.
- Window / permit / queue limits come from `ManagementOptions.RateLimit`.
- Dapr-internal endpoints bypass the limiter (the sidecar is trusted).
- New endpoints inherit the global limiter automatically. To disable for a specific (high-frequency, low-risk) endpoint, attach `[DisableRateLimiting]`.

## Security middleware

In addition to auth:

- `NWebsec.AspNetCore.Middleware` — HSTS (365d, includeSubdomains, preload), XFO same-origin, XSS protection.
- `HtmlSanitizer` (`Ganss.Xss`) — injected as `IHtmlSanitizer` singleton; use for any user-provided HTML before persisting or rendering.
- `AntiXssOptions` — bound from configuration to keep the sanitizer's allowlist environment-specific.

## Claims used

- `Constants.ClaimTypes.ObjectId` — stable user identifier from the IdP. Use this as the user key everywhere, including the rate limit partition.
- Standard `name`, `email`, `role` claims as projected by Keycloak (see `KeycloakAdminOptions`).

## Do NOT

- Hardcode role strings — they live in `Constants.Features.*`.
- Set `RequireHttpsMetadata = false` in any non-local environment.
- Bypass the global rate limiter for new endpoints without a documented rationale.
- Validate JWTs manually — use the standard `JwtBearer` events.
- Mix policy names across projects — keep the canonical `default` policy and add new ones only when their requirements truly differ.
