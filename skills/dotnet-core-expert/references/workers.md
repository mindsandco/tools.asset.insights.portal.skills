# Workers

Background work lives under `Api/Workers/` as `BackgroundService` subclasses. Typical jobs: warmup, cleanup, notification fan-out, role reconciliation. Examples in the repo: `WarmupWorker`, `CleanupCertificatesAndSecretsWorker`, `GatewayNotificationWorker`, `RoleWorker`.

## Anatomy of a worker

```csharp
public sealed class CleanupCertificatesAndSecretsWorker(
    IServiceScopeFactory scopeFactory,
    IOptions<ManagementOptions> options,
    ILogger<CleanupCertificatesAndSecretsWorker> logger,
    IClock clock)
    : BackgroundService
{
    private readonly CronExpression _schedule = CronExpression.Parse(
        options.Value.Workers.CleanupCertificatesAndSecretsCron,
        CronFormat.IncludeSeconds);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            var now = clock.GetCurrentInstant().ToDateTimeUtc();
            var next = _schedule.GetNextOccurrence(now, TimeZoneInfo.Utc);
            if (next is null)
            {
                return;
            }

            var delay = next.Value - now;
            try
            {
                await Task.Delay(delay, stoppingToken);
            }
            catch (TaskCanceledException)
            {
                return;
            }

            try
            {
                await using var scope = scopeFactory.CreateAsyncScope();
                var service = scope.ServiceProvider.GetRequiredService<ICertificateService>();
                await service.CleanupExpiredAsync(stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogError(ex, "Cleanup job failed; will retry on next tick.");
            }
        }
    }
}
```

Key rules:

- **Always inject `IServiceScopeFactory`**, not the scoped service directly. Workers are singletons; per-tick work goes inside a fresh `CreateAsyncScope()`.
- **Always catch and log** at the loop boundary. An unhandled exception kills the worker for the lifetime of the process.
- Use `Cronos` (already referenced) to parse cron expressions and compute the next instant. Schedules belong in `ManagementOptions.Workers.*Cron`, never hardcoded.
- Honour `stoppingToken` everywhere — pass it into `Task.Delay`, DbContext calls, HTTP calls, etc.
- Use `IClock` for "now" so tests can fast-forward.

## Registering a worker

In the `AddServices` extension:

```csharp
services.AddHostedService<CleanupCertificatesAndSecretsWorker>();
```

If the worker depends on options, ensure those options are registered with `ValidateOnStart()` so misconfiguration fails the boot before the worker starts.

## Warmup workers

Run-once-at-startup work that should block readiness goes in a worker like `WarmupWorker` plus an `IStartupFilter` if the work must complete before any traffic is served. Typical uses: pre-populating FusionCache, validating Dapr component reachability, applying DbUp scripts (see `migrations.md`).

## Dapr Jobs

For schedule-as-code that survives process restarts and works across replicas, prefer **Dapr Jobs** over a local cron loop:

```csharp
await daprClient.ScheduleJobAsync(
    name: "cleanup-secrets",
    schedule: "0 */15 * * * *",
    data: JsonSerializer.SerializeToUtf8Bytes(new CleanupSecretsRequest()),
    cancellationToken: token);
```

The job fires via a Dapr controller endpoint (similar to a pub/sub topic — see `dapr.md`). Use this whenever a single replica must own the schedule.

## Logging

Use the structured logger injected via the primary constructor. Standard event identifiers live in `LogConstants`. Worker logs should include:

- The worker name (handled by `ILogger<TWorker>`).
- The current scheduled instant.
- Outcome counts (`{ItemsCleaned}`, `{NotificationsSent}`).

## Testing

Workers themselves rarely have unit tests — the value is in the service they invoke. Test `ICertificateService.CleanupExpiredAsync` directly. For the worker's scheduling logic, factor out the "next occurrence" helper into a pure function and unit-test that.

## Do NOT

- Inject a scoped dependency (repository, DbContext factory user, service) into a `BackgroundService`. Use `IServiceScopeFactory`.
- Swallow `OperationCanceledException` from `stoppingToken` — let the loop exit cleanly.
- Use `Thread.Sleep`. Use `await Task.Delay(..., stoppingToken)`.
- Hardcode cron expressions. Bind them through `ManagementOptions.Workers` so they're configurable per environment.
- Run inline migrations or one-time data fixes inside a worker — that's what `<Product>.Db` + DbUp is for.
