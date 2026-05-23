# Dapr & Configuration

Every service runs alongside a Dapr sidecar. Dapr supplies configuration, secrets, pub/sub, state, jobs, and encryption. Locally, `Man.Dapr.Sidekick` (or the standalone `dapr run` CLI) bootstraps the sidecar.

## Required packages

```xml
<PackageReference Include="Dapr.AspNetCore" Version="1.17.*" />
<PackageReference Include="Dapr.Extensions.Configuration" Version="1.17.*" />
<PackageReference Include="Dapr.Jobs" Version="1.17.*" />
<PackageReference Include="Dapr.Cryptography" Version="1.17.*" />
<!-- optional, local dev only -->
<PackageReference Include="Man.Dapr.Sidekick.AspNetCore" Version="1.*" />
```

## Configuration sources

```csharp
var builder = WebApplication.CreateBuilder(args);

var daprClient = new DaprClientBuilder().Build();
builder.Configuration.AddDaprConfigurationStore(
    store: "appconfig",
    keys: ["myservice:"],
    daprClient: daprClient,
    timeout: TimeSpan.FromSeconds(20));
```

Provider precedence (highest wins):

1. JSON defaults baked into the assembly. **No `appsettings.json`** — see "FailOnAppSettings" below.
2. UserSecrets (`<UserSecretsId>` in `*.Api.csproj`).
3. Environment variables.
4. Dapr Configuration component (e.g. Azure App Configuration, Consul).
5. Command-line args.

### Forbid appsettings.json at build time

In `Directory.Build.props`:

```xml
<Target Name="FailOnAppSettings" BeforeTargets="BeforeBuild">
  <ItemGroup>
    <ForbiddenFiles Include="appsettings*.json" />
  </ItemGroup>
  <Error
    Condition="@(ForbiddenFiles->Count()) &gt; 0"
    Text="Forbidden configuration files detected: @(ForbiddenFiles). Use UserSecrets or Dapr config." />
</Target>
```

To add a new local setting:

```sh
dotnet user-secrets --project src/MyService.Api set "AppOptions:Foo:Bar" "value"
```

## Options pattern

Every options class has:

- A POCO with `[Required]` / `[Range]` data annotations.
- An `IValidateOptions<T>` for cross-field rules.
- A startup registration that validates eagerly.

```csharp
public sealed class AppOptions
{
    [Required] public AuthenticationOptions Authentication { get; init; } = new();
    [Range(0, int.MaxValue)] public int RequestTimeOutMs { get; init; } = 30_000;
    public string[] CorsOrigins { get; init; } = [];
    public RateLimitOptions RateLimit { get; init; } = new();
}

public sealed class AppOptionsValidation : IValidateOptions<AppOptions>
{
    public ValidateOptionsResult Validate(string? name, AppOptions options)
    {
        if (options.Authentication.Audiences.Length == 0 &&
            !string.IsNullOrEmpty(options.Authentication.Authority))
        {
            return ValidateOptionsResult.Fail("Audiences required when Authority is set.");
        }
        return ValidateOptionsResult.Success;
    }
}

// Program.cs
builder.Services.AddSingleton<IValidateOptions<AppOptions>, AppOptionsValidation>();
builder.Services.AddOptions<AppOptions>()
       .Bind(builder.Configuration.GetSection(nameof(AppOptions)))
       .ValidateDataAnnotations()
       .ValidateOnStart();
```

`ValidateOnStart()` is non-negotiable — misconfiguration must crash at boot, never at first request.

## Pub/sub

Emit events with `DaprClient.PublishEventAsync`. Consume them with `[Topic("<pubsub>", "<topic>")]` on a controller action under `Controllers/Dapr/`:

```csharp
[Route("dapr")]
[ApiController]
public sealed class OrderEventsController(IOrderService orderService) : ControllerBase
{
    [Topic("pubsub", "order.placed")]
    [HttpPost("order-placed")]
    public async Task<IActionResult> OnOrderPlacedAsync(
        [FromBody] OrderPlacedEvent @event,
        CancellationToken token)
    {
        await orderService.HandlePlacedAsync(@event, token);
        return Ok();
    }
}
```

Dapr controllers should be excluded from rate limiting and authenticated via the Dapr scheme registered alongside JWT Bearer (see `authentication.md`).

## State store

Direct `DaprClient.GetStateAsync` / `SaveStateAsync` is acceptable for transient cross-service coordination, but prefer **FusionCache** (with a Redis or Dapr backplane) for caching — it gives you L1/L2 + cross-process invalidation in one API.

## Secrets

```csharp
var secret = await daprClient.GetSecretAsync("secrets", "MyServiceJwtSigningKey", cancellationToken: token);
```

Don't roll your own KeyVault/Secret Manager client — the Dapr secret store binding is the standard surface and lets you swap backends per environment.

## Jobs

The `Dapr.Jobs` package schedules cron-driven invocations across replicas:

```csharp
await daprClient.ScheduleJobAsync(
    name: "cleanup-expired",
    schedule: "0 */15 * * * *",
    data: JsonSerializer.SerializeToUtf8Bytes(new CleanupRequest()),
    cancellationToken: token);
```

The job fires via a Dapr controller endpoint (similar to a pub/sub topic). Use this whenever a single replica must own the schedule. For in-process scheduling, see `workers.md`.

## Encryption

`Dapr.Cryptography` provides envelope encryption against a configured key store. Wrap it in your own `IEncryptionService` so callers don't depend on `DaprClient` directly — that centralises key naming and error handling.

## Sidekick (local dev only)

`Man.Dapr.Sidekick.AspNetCore` boots a sidecar inside the API process when `builder.Environment.IsDevelopment()`. Configure it under `AppOptions:Sidekick` so the same binary works locally and in deployed environments (which use the real `daprd` sidecar).

## Health checks

```xml
<PackageReference Include="AspNetCore.HealthChecks.Dapr" Version="9.*" />
<PackageReference Include="AspNetCore.HealthChecks.NpgSql" Version="9.*" />
```

```csharp
services.AddHealthChecks()
        .AddDapr()
        .AddNpgSql(connectionStrings.AppDb);
```

If you add a new external dependency (HTTP, blob, queue), add the matching health check probe.

## Do NOT

- Commit `appsettings*.json`. The build will fail.
- Read secrets via `IConfiguration["..."]` once and cache them in a `private static` field — bind into an options object so the validator runs and reloads work.
- Talk to KeyVault, Service Bus, Redis, etc. directly. Go through the Dapr component contract so the binding can be swapped per environment.
- Call `DaprClient` from controllers/services without injection — let DI provide it.
