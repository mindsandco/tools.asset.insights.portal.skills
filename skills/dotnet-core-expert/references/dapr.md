# Dapr & Configuration

Every portal service runs alongside a Dapr sidecar. Dapr supplies configuration, secrets, pub/sub, state, jobs, and encryption. Locally, `Man.Dapr.Sidekick` bootstraps the sidecar from the same process.

## Configuration sources

```csharp
var dapr = builder.Services.AddDapr(builder.Configuration);
builder.ConfigureConfiguration(args, dapr);
```

The provider chain (highest precedence last):

1. JSON defaults baked into the assembly (`appsettings.json` is **forbidden** — see the `FailOnAppSettings` MSBuild target in `Directory.Build.props`).
2. UserSecrets (`<UserSecretsId>` in `*.Api.csproj`).
3. Environment variables.
4. Dapr Configuration component (`Dapr.Extensions.Configuration`) — pulls keys from the configured backing store (e.g. Azure App Configuration).
5. Command-line args.

To add a new local setting:

```sh
dotnet user-secrets --project src/<Product>.Api set "ManagementOptions:Foo:Bar" "value"
```

## Options pattern

Every options class has:

- A POCO with `[Required]` / `[Range]` data annotations.
- An `IValidateOptions<T>` for cross-field rules.
- A startup registration that validates eagerly.

```csharp
public sealed class ManagementOptions
{
    [Required] public AuthenticationOptions Authentication { get; init; } = new();
    [Range(0, int.MaxValue)] public int RequestTimeOutMs { get; init; } = 30_000;
    public string[] CorsOrigins { get; init; } = [];
    // ...
}

public sealed class ManagementOptionsValidation : IValidateOptions<ManagementOptions>
{
    public ValidateOptionsResult Validate(string? name, ManagementOptions options)
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
builder.Services.AddSingleton<IValidateOptions<ManagementOptions>, ManagementOptionsValidation>();
builder.Services.AddOptions<ManagementOptions>()
       .Bind(builder.Configuration.GetSection(nameof(ManagementOptions)))
       .ValidateDataAnnotations()
       .ValidateOnStart();
```

`ValidateOnStart()` is non-negotiable — misconfiguration must crash at boot, never at first request.

## Pub/sub

Use `DaprClient.PublishEventAsync` for emitting events; consume with `[Topic("<pubsub>", "<topic>")]` on a controller action under `Controllers/Dapr/`:

```csharp
[Route("dapr")]
[ApiController]
public sealed class GatewayEventsController(IGatewayService gatewayService) : ControllerBase
{
    [Topic("pubsub", "gateway.registered")]
    [HttpPost("gateway-registered")]
    public async Task<IActionResult> OnGatewayRegisteredAsync(
        [FromBody] GatewayRegisteredEvent @event,
        CancellationToken token)
    {
        await gatewayService.HandleRegisteredAsync(@event, token);
        return Ok();
    }
}
```

Dapr controllers are excluded from rate limiting and authenticated via the `AddDapr()` auth scheme registered in `Program.cs`.

## State store

Direct `DaprClient.GetStateAsync` / `SaveStateAsync` is acceptable for transient cross-service coordination, but prefer **FusionCache** (`Asset.Insights.Portal.FusionCache.Dapr`) for caching — it gives you L1/L2 + the Dapr backplane in one API.

## Secrets

```csharp
var secret = await daprClient.GetSecretAsync("kv-store", "FooSecret", cancellationToken: token);
```

Don't roll your own KeyVault client — the Dapr secret store binding is the standard surface.

## Jobs

The `Dapr.Jobs` package schedules cron-driven invocations. Pair it with a Worker (see `workers.md`) or a Dapr controller endpoint. For pure in-process scheduling use `Cronos` directly.

## Encryption

`DaprEncryptionService` wraps `Dapr.Cryptography` for envelope encryption of stored secrets/certificates. Inject `IEncryptionService` rather than calling the Dapr APIs directly — it centralises key naming and error handling.

## Sidekick (local dev only)

`Man.Dapr.Sidekick.AspNetCore` boots a sidecar inside the API process when `builder.Environment.IsLocal()`. Configuration lives under `ManagementOptions:SideKick`. CI and deployed environments use the real sidecar.

## Health checks

Every Dapr building block contributes to the health endpoint. `AddHealthCheck(dapr, connectionStrings)` registers:

- `AspNetCore.HealthChecks.Dapr` — sidecar liveness.
- `AspNetCore.HealthChecks.NpgSql` — database reachability.

If you add a new external dependency (HTTP, blob, queue), add the matching health check probe.

## Do NOT

- Commit `appsettings*.json`. The build will fail.
- Read secrets via `IConfiguration["..."]` once and cache them in a `private static` field — bind into an options object so the validator runs and reloads work.
- Talk to KeyVault, Service Bus, Redis, etc. directly. Go through the Dapr component contract so the binding can be swapped per environment.
- Call `DaprClient` from controllers/services without injection — let DI provide it.
