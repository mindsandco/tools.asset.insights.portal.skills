---
name: testcontainers-dotnet
description: Use when writing .NET integration tests that need real backing services (PostgreSQL, RabbitMQ, Elasticsearch, MinIO, …) via Testcontainers, with xUnit v3 + Microsoft Testing Platform. Covers container fixture patterns (IAsyncLifetime, IClassFixture, AssemblyFixture), sealed-client wrapper pattern, BackgroundService handler extraction, NSubstitute mocking, and coverlet code coverage.
license: MIT
metadata:
  author: https://github.com/mindsandco
  version: "1.0.0"
  domain: testing
  triggers: Testcontainers, integration tests, xUnit v3, Microsoft Testing Platform, MTP, PostgreSQL container, RabbitMQ container, Elasticsearch container, MinIO container, Docker tests, NSubstitute
  role: specialist
  scope: implementation
  output-format: code
  related-skills: dotnet-core-expert, dotnet-code-analyzer, dotnet-http-client, dotnet-csharp-dependency-injection
---

# .NET Testcontainers + xUnit v3 Testing

Expert guidance for .NET integration testing with Testcontainers, xUnit v3, Microsoft Testing Platform (MTP), and NSubstitute. Covers:

- **xUnit v3 + Microsoft Testing Platform** — filter syntax and coverage flags differ from VSTest.
- **Container fixture coordination** — `IAsyncLifetime`, `IClassFixture`, `AssemblyFixture` patterns.
- **Sealed client wrappers** — patterns for `ElasticsearchClient`, `MinioClient`, `HttpClient`.
- **Handler extraction** — making `BackgroundService` business logic testable.
- **NSubstitute mocking** — substitutes, argument matchers, received-call verification.
- **Coverage collection** — coverlet.collector wired into `dotnet test`.

---

## When to use

- Integration tests requiring Docker containers (databases, queues, search, blob).
- Configuring xUnit v3 with Microsoft Testing Platform.
- Mocking sealed external clients (Elasticsearch, MinIO, etc.).
- Extracting handlers from `BackgroundService` for testability.
- Collecting code coverage with coverlet.

## Prerequisites

- **Docker or Podman** installed and running.
- **.NET 8, 9, or 10** SDK.
- **Docker socket** accessible (`/var/run/docker.sock` on Linux/macOS; Docker Desktop on Windows).

---

## 📦 Packages

### .NET 10

```xml
<PropertyGroup>
  <TargetFramework>net10.0</TargetFramework>
  <Nullable>enable</Nullable>
  <IsPackable>false</IsPackable>
  <IsTestProject>true</IsTestProject>
  <!-- Enable Microsoft Testing Platform -->
  <TestingPlatformDotnetTestSupport>true</TestingPlatformDotnetTestSupport>
  <GenerateTestingPlatformEntryPoint>true</GenerateTestingPlatformEntryPoint>
</PropertyGroup>

<ItemGroup>
  <!-- xUnit v3 -->
  <PackageReference Include="xunit.v3" Version="3.2.1" />
  <PackageReference Include="xunit.runner.visualstudio" Version="3.1.5">
    <PrivateAssets>all</PrivateAssets>
    <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
  </PackageReference>
  <PackageReference Include="Microsoft.NET.Test.Sdk" Version="18.1.0" />

  <!-- Coverage (coverlet.collector — works under both VSTest and MTP) -->
  <PackageReference Include="coverlet.collector" Version="10.0.1">
    <PrivateAssets>all</PrivateAssets>
    <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
  </PackageReference>

  <!-- Testcontainers — add only the modules you need -->
  <PackageReference Include="Testcontainers.PostgreSql"   Version="4.9.0" />
  <PackageReference Include="Testcontainers.RabbitMq"     Version="4.9.0" />
  <PackageReference Include="Testcontainers.Elasticsearch" Version="4.9.0" />
  <PackageReference Include="Testcontainers.Minio"        Version="4.9.0" />

  <!-- Mocking -->
  <PackageReference Include="NSubstitute" Version="5.3.0" />
  <PackageReference Include="NSubstitute.Analyzers.CSharp" Version="1.0.17">
    <PrivateAssets>all</PrivateAssets>
    <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
  </PackageReference>

  <!-- Test data (optional but recommended) -->
  <PackageReference Include="AutoFixture" Version="4.18.1" />
  <PackageReference Include="AutoFixture.Xunit2" Version="4.18.1" />
  <PackageReference Include="AutoFixture.AutoNSubstitute" Version="4.18.1" />

  <!-- Logger fakes from the BCL — no third-party logging adapter needed -->
  <PackageReference Include="Microsoft.Extensions.Diagnostics.Testing" Version="10.0.0" />

  <!-- WebApplicationFactory for integration tests -->
  <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="10.0.0" />

  <!-- OPTIONAL: AwesomeAssertions (Apache-2.0 fork of FluentAssertions).
       Plain Assert.* from xUnit is the default. Add only if your team already uses it. -->
  <!--
  <PackageReference Include="AwesomeAssertions" Version="9.3.0" />
  <PackageReference Include="AwesomeAssertions.Analyzers" Version="9.0.8">
    <PrivateAssets>all</PrivateAssets>
    <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
  </PackageReference>
  -->
</ItemGroup>
```

### .NET 8 / 9

Same set, but pin the BCL packages to the matching TFM:

```xml
<PackageReference Include="Microsoft.Extensions.Diagnostics.Testing" Version="9.0.0" />
<!-- or 8.0.0 for net8.0 -->
```

### Version gotchas

| Package | Gotcha | Fix |
|---|---|---|
| `Microsoft.Extensions.Diagnostics.Testing` | Must match target framework | `10.0.0` for net10, `9.0.0` for net9, `8.0.0` for net8 |
| `xunit.runner.visualstudio` v3 | Uses MTP under the hood when MTP is enabled, VSTest otherwise | Use the MTP flags below when `TestingPlatformDotnetTestSupport=true` |
| `Testcontainers.XunitV3` | Not always needed | Only add if you want the built-in xUnit v3 container traits |
| `FluentAssertions` 8.x | Commercial license required | If you want fluent assertions, use the Apache-2.0 `AwesomeAssertions` fork — listed above as optional |

---

## 🔧 xUnit v3 + Microsoft Testing Platform

### Command reference

```bash
# WRONG — VSTest syntax (won't work when MTP is enabled)
dotnet test --collect "XPlat Code Coverage"
dotnet test --filter "Category=Unit"

# CORRECT — MTP syntax
dotnet test -- --coverage --coverage-output-format cobertura
dotnet test --filter "FullyQualifiedName~Unit"

# Filter by namespace
dotnet test --filter "FullyQualifiedName~MyProject.Tests.Unit"

# Filter by test name pattern
dotnet test --filter "FullyQualifiedName~DocumentService"

# Run with coverage output to a specific file
dotnet test -- --coverage \
  --coverage-output-format cobertura \
  --coverage-output ./TestResults/coverage.xml
```

### Project configuration

```xml
<PropertyGroup>
  <TestingPlatformDotnetTestSupport>true</TestingPlatformDotnetTestSupport>
  <GenerateTestingPlatformEntryPoint>true</GenerateTestingPlatformEntryPoint>
</PropertyGroup>
```

### Assembly attributes

```csharp
// GlobalUsings.cs or AssemblyInfo.cs
[assembly: AssemblyFixture(typeof(SharedContainerFixture))]
[assembly: CaptureConsole]
[assembly: CaptureTrace]
```

---

## 🐳 Container fixture patterns

### Pattern 1: Per-test isolation (`IAsyncLifetime`)

Use when tests need an isolated container per test class:

```csharp
public sealed class CustomerRepositoryTests : IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .Build();

    public ValueTask InitializeAsync() => new(_postgres.StartAsync());

    public ValueTask DisposeAsync() => _postgres.DisposeAsync();

    [Fact]
    public async Task GetById_ExistingCustomer_ReturnsCustomer()
    {
        await using var connection = new NpgsqlConnection(_postgres.GetConnectionString());
        await connection.OpenAsync();

        // Test uses a fresh container.
    }
}
```

### Pattern 2: Class fixture (`IClassFixture`)

Use when every test in a single class shares the same container:

```csharp
public sealed class PostgresFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _container = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .Build();

    public string ConnectionString => _container.GetConnectionString();

    public async ValueTask InitializeAsync() => await _container.StartAsync();
    public async ValueTask DisposeAsync()    => await _container.DisposeAsync();
}

public sealed class OrderRepositoryTests(PostgresFixture fixture) : IClassFixture<PostgresFixture>
{
    [Fact]
    public async Task CreateOrder_ValidOrder_Persists()
    {
        await using var connection = new NpgsqlConnection(fixture.ConnectionString);
        // All tests in this class share one container.
    }
}
```

### Pattern 3: Assembly fixture (xUnit v3)

Use when **every** test class in the assembly shares the same containers — the best choice for an integration suite:

```csharp
public sealed class SharedContainerFixture : IAsyncLifetime
{
    // CONTAINERS
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .WithDatabase("testdb")
        .WithUsername("testuser")
        .WithPassword("testpass")
        .Build();

    private readonly RabbitMqContainer _rabbitmq = new RabbitMqBuilder()
        .WithImage("rabbitmq:4-management-alpine")
        .Build();

    private readonly ElasticsearchContainer _elasticsearch = new ElasticsearchBuilder()
        .WithImage("elasticsearch:8.17.0")
        .Build();

    private readonly MinioContainer _minio = new MinioBuilder()
        .WithImage("minio/minio:latest")
        .Build();

    // CONNECTION DETAILS
    public string PostgresConnectionString => _postgres.GetConnectionString();
    public string RabbitMqConnectionString => _rabbitmq.GetConnectionString();
    public Uri    ElasticsearchUri         => new(_elasticsearch.GetConnectionString());
    public string MinioEndpoint            => _minio.GetConnectionString();
    public string MinioAccessKey           => "minioadmin";
    public string MinioSecretKey           => "minioadmin";

    // EF CORE FACTORY (optional)
    public IDbContextFactory<AppDbContext>? DbFactory { get; private set; }

    // LIFECYCLE
    public async ValueTask InitializeAsync()
    {
        await Task.WhenAll(
            _postgres.StartAsync(),
            _rabbitmq.StartAsync(),
            _elasticsearch.StartAsync(),
            _minio.StartAsync());

        var dataSource = new NpgsqlDataSourceBuilder(PostgresConnectionString).Build();
        var services = new ServiceCollection();
        services.AddPooledDbContextFactory<AppDbContext>(opts =>
            opts.UseNpgsql(dataSource)
                .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));

        var provider = services.BuildServiceProvider();
        DbFactory = provider.GetRequiredService<IDbContextFactory<AppDbContext>>();

        await using var db = await DbFactory.CreateDbContextAsync();
        await db.Database.MigrateAsync();
    }

    public async ValueTask DisposeAsync()
    {
        await Task.WhenAll(
            _postgres.DisposeAsync().AsTask(),
            _rabbitmq.DisposeAsync().AsTask(),
            _elasticsearch.DisposeAsync().AsTask(),
            _minio.DisposeAsync().AsTask());
    }
}

// Register assembly-wide
[assembly: AssemblyFixture(typeof(SharedContainerFixture))]
```

Usage:

```csharp
public sealed class DocumentRepositoryIntegrationTests(SharedContainerFixture fixture)
{
    [Fact]
    public async Task AddAsync_ValidDocument_Persists()
    {
        await using var db = await fixture.DbFactory!.CreateDbContextAsync();
        // ...
    }
}
```

---

## 🧪 NSubstitute essentials

NSubstitute uses the **substitute** pattern: you get back an instance of the interface, configure return values directly on it, and verify by asking what calls it received.

### Substitute construction

```csharp
// Single substitute
var documentRepository = Substitute.For<IDocumentRepository>();

// Multiple substitutes for the class under test
public sealed class DocumentServiceTests
{
    private const string ValidFileName       = "invoice.pdf";
    private const string ValidStoragePath    = "documents/2025-01/abc123.pdf";
    private const string ExtractedOcrContent = "Invoice #12345";

    private readonly IDocumentRepository     _documentRepository = Substitute.For<IDocumentRepository>();
    private readonly IDocumentStorageService _storageService     = Substitute.For<IDocumentStorageService>();
    private readonly IRabbitMqPublisher      _publisher          = Substitute.For<IRabbitMqPublisher>();
    private readonly FakeLogger<DocumentService> _logger         = new();

    private DocumentService CreateSut() => new(
        _documentRepository,
        _storageService,
        _publisher,
        _logger);

    [Fact]
    public async Task UploadAsync_ValidPdf_PublishesOcrCommand()
    {
        // Arrange
        _documentRepository
            .AddAsync(Arg.Any<Document>(), Arg.Any<CancellationToken>())
            .Returns(call => call.Arg<Document>());          // passthrough

        var sut = CreateSut();

        // Act
        var result = await sut.UploadAsync(ValidFileName, Stream.Null, 1024, default);

        // Assert
        Assert.Equal(ValidFileName, result.FileName);

        await _storageService.Received(1).UploadAsync(
            Arg.Any<Stream>(),
            Arg.Is<string>(p => p.EndsWith(".pdf")),
            Arg.Any<long>(),
            Arg.Any<CancellationToken>());

        await _publisher.Received(1).PublishAsync(Arg.Any<string>(), Arg.Any<OcrCommand>());
    }
}
```

NSubstitute has **no `MockBehavior.Strict` equivalent**. Verify the calls you care about with `.Received(n)` / `.DidNotReceive()`. If you need to catch unexpected calls, follow the test with explicit `DidNotReceive` assertions on the methods you don't expect to be invoked.

### `FakeLogger` + `FakeLogCollector`

Use `Microsoft.Extensions.Diagnostics.Testing` for asserting on log output:

```csharp
public sealed class OcrProcessorTests
{
    private readonly FakeLogCollector       _logCollector = new();
    private readonly FakeLogger<OcrProcessor> _logger;
    private readonly IDocumentService         _documentService = Substitute.For<IDocumentService>();

    public OcrProcessorTests()
    {
        _logger = new FakeLogger<OcrProcessor>(_logCollector);
    }

    [Fact]
    public async Task ProcessAsync_DocumentNotFound_LogsWarning()
    {
        // Arrange
        _documentService
            .ProcessOcrResultAsync(Arg.Any<Guid>(), Arg.Any<string>(), Arg.Any<string?>(), Arg.Any<CancellationToken>())
            .Returns(false);

        var sut = new OcrProcessor(_documentService, _logger);

        // Act
        await sut.ProcessAsync(Guid.NewGuid(), default);

        // Assert
        var snapshot = _logCollector.GetSnapshot();
        Assert.Contains(snapshot, log =>
            log.Level == LogLevel.Warning &&
            (log.Message?.Contains("not found") ?? false));
    }
}
```

### Setup patterns reference (NSubstitute)

```csharp
// Basic return value
repo.GetByIdAsync(Arg.Any<Guid>(), Arg.Any<CancellationToken>())
    .Returns(document);

// Match specific argument
repo.GetByIdAsync(expectedId, Arg.Any<CancellationToken>())
    .Returns(document);

// Conditional match
repo.GetByIdAsync(
    Arg.Is<Guid>(id => id != Guid.Empty),
    Arg.Any<CancellationToken>())
    .Returns(document);

// Return based on input (passthrough)
repo.AddAsync(Arg.Any<Document>(), Arg.Any<CancellationToken>())
    .Returns(call => call.Arg<Document>());

// Throw exception
repo.GetByIdAsync(badId, Arg.Any<CancellationToken>())
    .Returns<Document>(_ => throw new InvalidOperationException("Not found"));

// Sequential returns
queue.GetNextAsync()
    .Returns("first", "second")
    .AndDoes(_ => throw new InvalidOperationException("No more"));

// Capture argument
Document? captured = null;
repo.AddAsync(Arg.Do<Document>(d => captured = d), Arg.Any<CancellationToken>())
    .Returns(call => call.Arg<Document>());

// Verify call count
await repo.Received(1).SaveAsync(Arg.Any<CancellationToken>());
await repo.DidNotReceive().DeleteAsync(Arg.Any<Guid>(), Arg.Any<CancellationToken>());

// Clear received calls between phases of a test
repo.ClearReceivedCalls();
```

### AutoFixture + AutoNSubstitute (optional)

Cut boilerplate with `[AutoData]`-style attributes:

```csharp
public sealed class AutoNSubstituteDataAttribute : AutoDataAttribute
{
    public AutoNSubstituteDataAttribute()
        : base(() => new Fixture().Customize(new AutoNSubstituteCustomization
        {
            ConfigureMembers = true,
            GenerateDelegates = true
        })) { }
}

public class DocumentServiceTests
{
    [Theory, AutoNSubstituteData]
    public async Task UploadAsync_PersistsAndPublishes(
        [Frozen] IDocumentRepository repository,
        [Frozen] IRabbitMqPublisher publisher,
        DocumentService sut,
        string fileName,
        CancellationToken token)
    {
        repository.AddAsync(Arg.Any<Document>(), token).Returns(call => call.Arg<Document>());

        await sut.UploadAsync(fileName, Stream.Null, 1024, token);

        await publisher.Received(1).PublishAsync(Arg.Any<string>(), Arg.Any<OcrCommand>());
    }
}
```

`[Frozen]` reuses the same substitute everywhere it appears, so the substitute injected into the `sut` parameter is the one you configure and verify.

---

## 🎯 Sealed-client wrapper pattern

External clients are often `sealed` (`ElasticsearchClient`, `MinioClient`, `HttpClient`). Wrap them behind an interface so NSubstitute can substitute the surface:

```csharp
internal interface IElasticClientWrapper
{
    Task<bool> IndexExistsAsync(string indexName, CancellationToken ct);
    Task CreateIndexAsync(string indexName, CancellationToken ct);
    Task<IndexResponse> IndexDocumentAsync<T>(T document, string id, CancellationToken ct) where T : class;
    Task<DeleteResponse> DeleteDocumentAsync(string id, CancellationToken ct);
    IAsyncEnumerable<T> SearchAsync<T>(string query, int limit, CancellationToken ct) where T : class;
}

internal sealed class ElasticClientWrapper(
    ElasticsearchClient client,
    IOptions<ElasticsearchOptions> options)
    : IElasticClientWrapper
{
    private readonly string _indexName = options.Value.IndexName;

    public async Task<bool> IndexExistsAsync(string indexName, CancellationToken ct)
    {
        var response = await client.Indices.ExistsAsync(indexName, ct);
        return response.Exists;
    }

    public Task CreateIndexAsync(string indexName, CancellationToken ct) =>
        client.Indices.CreateAsync(indexName, ct);

    public Task<IndexResponse> IndexDocumentAsync<T>(T document, string id, CancellationToken ct) where T : class =>
        client.IndexAsync(document, i => i.Index(_indexName).Id(id), ct);

    // ...
}

// DI
services.AddSingleton<IElasticClientWrapper, ElasticClientWrapper>();
```

Test against the substitute:

```csharp
public sealed class SearchIndexServiceTests
{
    private readonly IElasticClientWrapper _elastic = Substitute.For<IElasticClientWrapper>();

    [Fact]
    public async Task EnsureIndexAsync_IndexMissing_CreatesIndex()
    {
        // Arrange
        _elastic.IndexExistsAsync("documents", Arg.Any<CancellationToken>())
                .Returns(false);

        var sut = new SearchIndexService(_elastic, NullLogger<SearchIndexService>.Instance);

        // Act
        await sut.EnsureIndexAsync(default);

        // Assert
        await _elastic.Received(1).CreateIndexAsync("documents", Arg.Any<CancellationToken>());
    }
}
```

---

## 🔨 Handler extraction pattern

When `BackgroundService` uses `IServiceScopeFactory`, extract the business logic into a handler that takes explicit dependencies — the listener becomes thin orchestration.

### Before (hard to test)

```csharp
public class OcrResultListener : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly IRabbitMqConsumerFactory _consumerFactory;

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        await using var consumer = await _consumerFactory.CreateConsumerAsync<OcrEvent>(ct);
        await foreach (var msg in consumer.ConsumeAsync(ct))
        {
            using var scope = _scopeFactory.CreateScope();
            var service = scope.ServiceProvider.GetRequiredService<IDocumentService>();

            try
            {
                bool success = await service.ProcessOcrResultAsync(msg.JobId, msg.Status, msg.Content, ct);
                if (success) await consumer.AckAsync();
                else         await consumer.NackAsync(false);
            }
            catch
            {
                await consumer.NackAsync(false);
            }
        }
    }
}
```

### After (testable)

```csharp
internal sealed class OcrEventHandler(
    IDocumentService documentService,
    ISseStream<OcrEvent> sseStream,
    ILogger<OcrEventHandler> logger)
{
    public async Task<HandlerResult> HandleAsync(OcrEvent evt, CancellationToken ct)
    {
        try
        {
            bool success = await documentService.ProcessOcrResultAsync(
                evt.JobId, evt.Status, evt.Content, ct);

            if (!success)
            {
                logger.LogWarning("Document {JobId} not found", evt.JobId);
                return HandlerResult.NotFound;
            }

            sseStream.Publish(evt);
            return HandlerResult.Success;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed processing OCR event {JobId}", evt.JobId);
            return HandlerResult.Failed;
        }
    }
}

internal enum HandlerResult { Success, NotFound, Failed }

public class OcrResultListener(
    IRabbitMqConsumerFactory consumerFactory,
    OcrEventHandler handler)
    : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        await using var consumer = await consumerFactory.CreateConsumerAsync<OcrEvent>(ct);
        await foreach (var msg in consumer.ConsumeAsync(ct))
        {
            var result = await handler.HandleAsync(msg, ct);
            if (result == HandlerResult.Success)
                await consumer.AckAsync();
            else
                await consumer.NackAsync(requeue: result == HandlerResult.Failed);
        }
    }
}

services.AddScoped<OcrEventHandler>();
services.AddHostedService<OcrResultListener>();
```

### Handler test

```csharp
public sealed class OcrEventHandlerTests
{
    private const string CompletedStatus  = "Completed";
    private const string ExtractedContent = "Extracted text";

    private readonly IDocumentService   _documentService = Substitute.For<IDocumentService>();
    private readonly ISseStream<OcrEvent> _sseStream     = Substitute.For<ISseStream<OcrEvent>>();
    private readonly FakeLogger<OcrEventHandler> _logger = new();

    private OcrEventHandler CreateSut() => new(_documentService, _sseStream, _logger);

    private static OcrEvent CreateEvent(Guid? jobId = null) =>
        new(jobId ?? Guid.CreateVersion7(), CompletedStatus, ExtractedContent, DateTimeOffset.UtcNow);

    [Fact]
    public async Task HandleAsync_ProcessingSucceeds_PublishesAndReturnsSuccess()
    {
        // Arrange
        var evt = CreateEvent();

        _documentService
            .ProcessOcrResultAsync(evt.JobId, CompletedStatus, ExtractedContent, Arg.Any<CancellationToken>())
            .Returns(true);

        var sut = CreateSut();

        // Act
        var result = await sut.HandleAsync(evt, CancellationToken.None);

        // Assert
        Assert.Equal(HandlerResult.Success, result);
        _sseStream.Received(1).Publish(evt);
    }

    [Fact]
    public async Task HandleAsync_DocumentNotFound_ReturnsNotFound()
    {
        // Arrange
        var evt = CreateEvent();

        _documentService
            .ProcessOcrResultAsync(Arg.Any<Guid>(), Arg.Any<string>(), Arg.Any<string?>(), Arg.Any<CancellationToken>())
            .Returns(false);

        var sut = CreateSut();

        // Act
        var result = await sut.HandleAsync(evt, CancellationToken.None);

        // Assert
        Assert.Equal(HandlerResult.NotFound, result);
        _sseStream.DidNotReceive().Publish(Arg.Any<OcrEvent>());
    }
}
```

---

## 📁 Assembly visibility

Enable internal testing without exposing types publicly. NSubstitute uses Castle DynamicProxy, so it needs the same `DynamicProxyGenAssembly2` entry that Moq did:

```xml
<!-- Production .csproj -->
<ItemGroup>
  <InternalsVisibleTo Include="MyProject.Tests" />
  <InternalsVisibleTo Include="DynamicProxyGenAssembly2" /> <!-- Castle DynamicProxy (NSubstitute) -->
</ItemGroup>
```

---

## Common gotchas

### 1. Anonymous-type assertions

Production code uses anonymous types in `ProblemDetails.Extensions`, etc.:

```csharp
pd.Extensions["debug"] = new
{
    exception_type  = ex.GetType().FullName,
    inner_exception = ex.InnerException?.Message,
    stack_trace     = ex.StackTrace
};
```

**Solution A: reflection**

```csharp
var debug    = pd.Extensions["debug"]!;
var innerMsg = debug.GetType().GetProperty("inner_exception")?.GetValue(debug);
Assert.Equal("Expected message", innerMsg);
```

**Solution B: refactor to a named type (preferred)**

```csharp
internal sealed record DebugInfo(string? ExceptionType, string? InnerException, string? StackTrace);
pd.Extensions["debug"] = new DebugInfo(ex.GetType().FullName, ex.InnerException?.Message, ex.StackTrace);

// Test
var debug = Assert.IsType<DebugInfo>(pd.Extensions["debug"]);
Assert.Equal("Expected message", debug.InnerException);
```

### 2. Static initialisation that touches the filesystem

```csharp
private static readonly XmlSchemaSet Schemas = LoadSchemas();

private static XmlSchemaSet LoadSchemas()
{
    string schemaPath = Path.Combine(AppContext.BaseDirectory, "Schemas", "report.xsd");
    // Runs before test setup; you cannot intercept it from tests.
}
```

**Fixes:**

1. Make schema loading lazy (defer to first use).
2. Inject the schema path via constructor.
3. Use the real file system for that specific test and copy the schema to the test output directory.

### 3. Integration test fixture failures at 0ms

```
failed MyIntegrationTest (0ms)
```

**Causes:** fixture `InitializeAsync` threw, container startup failed, database migration failed, multiple fixtures contending for the same port/name.

**Fixes:**

- Check Docker is running.
- Inspect container logs: `docker logs <container_id>`.
- Use unique database names per fixture.
- Ensure a single `AssemblyFixture` coordinates all containers — don't mix per-test and assembly-wide.

### 4. `ErrorOr<T>` (or similar result types)

```csharp
// Success
Assert.False(result.IsError);
Assert.Equal(2, result.Value.ProcessedCount);

// Single error
Assert.True(result.IsError);
Assert.Equal("Report.InvalidGuid", result.FirstError.Code);
Assert.Contains("invalid GUID", result.FirstError.Description);

// Multiple errors
Assert.Equal(2, result.Errors.Count);
Assert.Contains("Error.One",  result.Errors.Select(e => e.Code));
Assert.Contains("Error.Two",  result.Errors.Select(e => e.Code));
```

---

## 📊 Coverage with coverlet.collector

`coverlet.collector` works under both VSTest and Microsoft Testing Platform because `xunit.runner.visualstudio` bridges them.

### MTP-mode (`TestingPlatformDotnetTestSupport=true`)

```bash
dotnet test -- --coverage \
  --coverage-output-format cobertura \
  --coverage-output ./TestResults/coverage.cobertura.xml
```

The MTP `--coverage` flag uses the platform's built-in collector. To force coverlet specifically, pass it through the collector argument:

```bash
dotnet test -- --collect "XPlat Code Coverage" \
              --results-directory ./TestResults
```

### VSTest-mode (`TestingPlatformDotnetTestSupport` unset)

```bash
dotnet test --collect "XPlat Code Coverage" \
            --results-directory ./TestResults
```

`coverlet.collector` writes `coverage.cobertura.xml` into a `TestResults/<guid>/` folder.

### `runsettings` for coverlet

Optional but useful for tuning exclusions:

```xml
<!-- coverlet.runsettings -->
<?xml version="1.0" encoding="utf-8"?>
<RunSettings>
  <DataCollectionRunSettings>
    <DataCollectors>
      <DataCollector friendlyName="XPlat code coverage">
        <Configuration>
          <Format>cobertura</Format>
          <Exclude>[*.Tests]*,[*.IntegrationTests]*</Exclude>
          <ExcludeByAttribute>Obsolete,GeneratedCodeAttribute,CompilerGeneratedAttribute</ExcludeByAttribute>
          <SkipAutoProps>true</SkipAutoProps>
        </Configuration>
      </DataCollector>
    </DataCollectors>
  </DataCollectionRunSettings>
</RunSettings>
```

```bash
dotnet test --settings coverlet.runsettings --collect "XPlat Code Coverage"
```

### GitHub Actions

```yaml
- name: Test with coverage
  run: |
    dotnet test \
      --configuration Release \
      --no-build \
      --collect "XPlat Code Coverage" \
      --results-directory ./TestResults

- name: Upload coverage
  uses: codecov/codecov-action@v4
  with:
    files: ./TestResults/**/coverage.cobertura.xml
```

### NUKE build target

```csharp
Target CodeCoverage => _ => _
    .DependsOn(Compile)
    .Executes(() =>
    {
        DotNetTest(s => s
            .SetProjectFile(Solution.GetProject("MyProject.Tests"))
            .SetConfiguration(Configuration.Debug)
            .SetDataCollector("XPlat Code Coverage")
            .SetResultsDirectory(RootDirectory / "TestResults")
            .EnableNoBuild());
    });
```

---

## 🏗️ Test project structure

```
MyProject.Tests/
├── Unit/
│   ├── Services/
│   │   ├── DocumentServiceTests.cs
│   │   └── OcrProcessorTests.cs
│   ├── Handlers/
│   │   ├── OcrEventHandlerTests.cs
│   │   └── GenAiEventHandlerTests.cs
│   └── Validators/
│       └── UploadRequestValidatorTests.cs
├── Integration/
│   ├── SharedContainerFixture.cs
│   ├── Repositories/
│   │   └── DocumentRepositoryIntegrationTests.cs
│   └── Endpoints/
│       └── DocumentEndpointTests.cs
├── Builders/
│   ├── DocumentBuilder.cs
│   └── UploadRequestBuilder.cs
├── GlobalUsings.cs
└── MyProject.Tests.csproj
```

### `GlobalUsings.cs`

```csharp
global using Xunit;
global using NSubstitute;
global using Microsoft.Extensions.Logging;
global using Microsoft.Extensions.Logging.Testing;

// Optional: only if you adopted AwesomeAssertions
// global using AwesomeAssertions;

[assembly: AssemblyFixture(typeof(SharedContainerFixture))]
[assembly: CaptureConsole]
[assembly: CaptureTrace]
```

---

## 📋 Refactoring checklist

### Before writing tests

- [ ] Add `[assembly: InternalsVisibleTo("...Tests")]` to the production `.csproj`.
- [ ] Add `[assembly: InternalsVisibleTo("DynamicProxyGenAssembly2")]` for NSubstitute (Castle DynamicProxy).
- [ ] Identify sealed external clients needing wrappers.
- [ ] Identify `BackgroundService`s needing handler extraction.

### Handler extraction

- [ ] Extract business logic from `ExecuteAsync` into an internal handler class.
- [ ] Handler takes explicit constructor dependencies (no `IServiceScopeFactory`).
- [ ] Handler returns a result enum (`Success`, `NotFound`, `Failed`).
- [ ] Listener/worker becomes thin orchestration (< 15 lines).
- [ ] Register the handler in DI.

### Sealed client wrapping

- [ ] Create `I{Client}Wrapper` interface.
- [ ] Implementation delegates to the sealed client.
- [ ] Service depends on the interface, not the sealed client.
- [ ] Register the wrapper in DI.

### Test structure

- [ ] Constants section at the top.
- [ ] Field-initialised `Substitute.For<T>()` per dependency.
- [ ] Private `CreateSut()` factory method.
- [ ] Use `Received` / `DidNotReceive` for verification.
- [ ] Use builders for non-trivial test data.

---

## Examples

### Example 1: PostgreSQL integration test

```csharp
public sealed class UserRepositoryTests : IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .WithDatabase("testdb")
        .WithUsername("testuser")
        .WithPassword("testpass")
        .Build();

    public ValueTask InitializeAsync() => new(_postgres.StartAsync());
    public ValueTask DisposeAsync()    => _postgres.DisposeAsync();

    [Fact]
    public async Task CreateUser_ValidUser_Persists()
    {
        await using var connection = new NpgsqlConnection(_postgres.GetConnectionString());
        await connection.OpenAsync();

        await using var cmd = new NpgsqlCommand(
            "CREATE TABLE users (id SERIAL PRIMARY KEY, name TEXT NOT NULL)", connection);
        await cmd.ExecuteNonQueryAsync();

        var repo = new UserRepository(connection);

        var user = await repo.CreateAsync("Alice");

        Assert.True(user.Id > 0);
        Assert.Equal("Alice", user.Name);
    }
}
```

### Example 2: RabbitMQ publisher test

```csharp
public sealed class EventPublisherTests : IAsyncLifetime
{
    private readonly RabbitMqContainer _rabbitmq = new RabbitMqBuilder()
        .WithImage("rabbitmq:4-management-alpine")
        .Build();

    public ValueTask InitializeAsync() => new(_rabbitmq.StartAsync());
    public ValueTask DisposeAsync()    => _rabbitmq.DisposeAsync();

    [Fact]
    public async Task PublishAsync_ValidEvent_DeliversToQueue()
    {
        var factory = new ConnectionFactory { Uri = new Uri(_rabbitmq.GetConnectionString()) };

        await using var connection = await factory.CreateConnectionAsync();
        await using var channel    = await connection.CreateChannelAsync();

        await channel.QueueDeclareAsync("test-queue", durable: false, exclusive: false, autoDelete: true);

        var publisher = new EventPublisher(channel);

        await publisher.PublishAsync("test-queue", new TestEvent { Message = "Hello" });

        var result = await channel.BasicGetAsync("test-queue", autoAck: true);
        Assert.NotNull(result);

        var message = JsonSerializer.Deserialize<TestEvent>(result.Body.Span);
        Assert.Equal("Hello", message!.Message);
    }
}
```

### Example 3: Elasticsearch search test

```csharp
public sealed class SearchServiceTests : IAsyncLifetime
{
    private readonly ElasticsearchContainer _elasticsearch = new ElasticsearchBuilder()
        .WithImage("elasticsearch:8.17.0")
        .Build();

    public ValueTask InitializeAsync() => new(_elasticsearch.StartAsync());
    public ValueTask DisposeAsync()    => _elasticsearch.DisposeAsync();

    [Fact]
    public async Task SearchAsync_MatchingDocument_ReturnsResult()
    {
        var settings = new ElasticsearchClientSettings(new Uri(_elasticsearch.GetConnectionString()));
        var client   = new ElasticsearchClient(settings);

        await client.Indices.CreateAsync("documents");
        await client.IndexAsync(new DocumentIndex { Id = "1", Content = "Hello World" }, i => i.Index("documents"));
        await client.Indices.RefreshAsync("documents");

        var searchService = new SearchService(client);

        var results = await searchService.SearchAsync("Hello").ToListAsync();

        Assert.Single(results, d => d.Content.Contains("Hello"));
    }
}
```

### Example 4: MinIO storage test

```csharp
public sealed class StorageServiceTests : IAsyncLifetime
{
    private readonly MinioContainer _minio = new MinioBuilder()
        .WithImage("minio/minio:latest")
        .Build();

    public ValueTask InitializeAsync() => new(_minio.StartAsync());
    public ValueTask DisposeAsync()    => _minio.DisposeAsync();

    [Fact]
    public async Task UploadAsync_ValidFile_StoresInBucket()
    {
        var client = new MinioClient()
            .WithEndpoint(_minio.GetConnectionString())
            .WithCredentials("minioadmin", "minioadmin")
            .Build();

        await client.MakeBucketAsync(new MakeBucketArgs().WithBucket("test-bucket"));

        var storageService = new StorageService(client);
        var content        = "Hello, MinIO!"u8.ToArray();

        await storageService.UploadAsync("test-bucket", "test.txt", new MemoryStream(content));

        var statArgs = new StatObjectArgs().WithBucket("test-bucket").WithObject("test.txt");
        var stat     = await client.StatObjectAsync(statArgs);
        Assert.Equal(content.Length, stat.Size);
    }
}
```

---

## Best-practice summary

1. **Use Testcontainers' pre-configured modules** — sensible defaults out of the box.
2. **Use `AssemblyFixture` for integration suites** — share containers across every test class.
3. **Extract handlers from `BackgroundService`s** — makes the business logic directly testable.
4. **Wrap sealed clients** — create mockable interfaces for `ElasticsearchClient`, `MinioClient`, etc.
5. **NSubstitute, not Moq** — substitutes + `Received` / `DidNotReceive` verification.
6. **Constants at the top of a test class** — keep test data consistent and obvious.
7. **Private `CreateSut()` factory** — one place that builds the system under test.
8. **AwesomeAssertions is optional** — `Assert.*` from xUnit is the default; add the Apache-2.0 fork only if your team really wants fluent syntax.
9. **MTP for xUnit v3** — `dotnet test -- --coverage`, not `--collect "XPlat Code Coverage"` (which is the VSTest path).
10. **coverlet.collector for cross-mode coverage** — works under both VSTest and MTP, emits cobertura.

---

## Additional resources

- **Testcontainers .NET**: https://dotnet.testcontainers.org/
- **xUnit v3**: https://xunit.net/docs/getting-started/v3
- **Microsoft Testing Platform**: https://learn.microsoft.com/en-us/dotnet/core/testing/microsoft-testing-platform-overview
- **NSubstitute**: https://nsubstitute.github.io/
- **coverlet**: https://github.com/coverlet-coverage/coverlet
- **AwesomeAssertions** (optional): https://github.com/AwesomeAssertions/awesomeassertions
