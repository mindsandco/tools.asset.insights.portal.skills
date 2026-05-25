# NUKE Build

[NUKE](https://nuke.build/) is a C# build automation system for .NET projects. The build script *is* a typed C# project (`build/_build.csproj`) that lives in the repo, gets compiled, and runs targets locally and in CI. Use it whenever you want the build to be:

- Authored in the same language as the product (refactoring, debugging, IntelliSense).
- Identical locally and in CI (no copy-pasted YAML).
- Composed from typed targets with `.DependsOn(...)` instead of stringly-typed task graphs.

## Project layout

```
<repo-root>/
├── .nuke/
│   ├── build.schema.json           # JSON schema for parameters
│   └── parameters.json             # Default / committed parameters
├── build/
│   ├── _build.csproj               # Build project (sdk=Nuke.Common)
│   ├── Build.cs                    # Main partial class (targets)
│   └── Build.<area>.cs             # Optional partial files (e.g. Build.Coverage.cs)
├── build.cmd                       # Windows bootstrap
├── build.sh                        # *nix bootstrap
├── build.ps1                       # PowerShell bootstrap
├── GitVersion.yml                  # Optional — version derivation
└── src/                            # Product code
```

`.nuke/` is committed. `build/bin` and `build/obj` are gitignored.

## Bootstrap

In a repo without NUKE:

```sh
dotnet tool install --global Nuke.GlobalTool
cd <repo-root>
nuke :setup
```

`nuke :setup` is interactive and generates `build/_build.csproj`, `build/Build.cs`, the bootstrap scripts, and `.nuke/`. After setup, commit everything under `build/`, `.nuke/`, `build.cmd`, `build.sh`, and `build.ps1`.

## Build project (`build/_build.csproj`)

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <RootNamespace>_build</RootNamespace>
    <NoWarn>$(NoWarn);CS0649;CS0169;NU1701</NoWarn>
    <NukeRootDirectory>..</NukeRootDirectory>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Nuke.Common" Version="9.*" />
  </ItemGroup>
</Project>
```

Pin `Nuke.Common` deliberately — a major-version bump may rename APIs.

## Target definition pattern

```csharp
using Nuke.Common;
using Nuke.Common.IO;
using Nuke.Common.ProjectModel;
using Nuke.Common.Tooling;
using Nuke.Common.Tools.DotNet;
using static Nuke.Common.Tools.DotNet.DotNetTasks;

class Build : NukeBuild
{
    public static int Main() => Execute<Build>(x => x.Compile);

    [Parameter("Configuration: Debug or Release.")]
    readonly Configuration Configuration = IsLocalBuild ? Configuration.Debug : Configuration.Release;

    [Solution(GenerateProjects = true)]
    readonly Solution Solution;

    AbsolutePath ArtifactsDirectory => RootDirectory / "artifacts";
    AbsolutePath TestResultsDirectory => ArtifactsDirectory / "test-results";
    AbsolutePath CoverageDirectory => ArtifactsDirectory / "coverage";

    Target Clean => _ => _
        .Before(Restore)
        .Executes(() =>
        {
            ArtifactsDirectory.CreateOrCleanDirectory();
        });

    Target Restore => _ => _
        .Executes(() =>
        {
            DotNetRestore(s => s
                .SetProjectFile(Solution)
                .SetLockedMode(true));
        });

    Target Compile => _ => _
        .DependsOn(Restore)
        .Executes(() =>
        {
            DotNetBuild(s => s
                .SetProjectFile(Solution)
                .SetConfiguration(Configuration)
                .EnableNoRestore());
        });

    Target Test => _ => _
        .DependsOn(Compile)
        .Executes(() =>
        {
            DotNetTest(s => s
                .SetProjectFile(Solution)
                .SetConfiguration(Configuration)
                .EnableNoBuild()
                .SetResultsDirectory(TestResultsDirectory)
                .SetLoggers("trx;LogFileName=results.trx"));
        });
}
```

Key idioms:

- **`Configuration`** is a tiny custom enum (`Configuration.cs`):
  ```csharp
  [TypeConverter(typeof(TypeConverter<Configuration>))]
  public class Configuration : Enumeration
  {
      public static Configuration Debug = new() { Value = nameof(Debug) };
      public static Configuration Release = new() { Value = nameof(Release) };
      public static implicit operator string(Configuration c) => c.Value;
  }
  ```
- **`[Solution(GenerateProjects = true)]`** discovers the `.sln` / `.slnx` and emits strongly-typed project handles (`Solution.MyService_Api`).
- **`AbsolutePath`** instead of `string` for any path; supports `/` operator, `.CreateOrCleanDirectory()`, `.GlobFiles(...)`.
- **`Before` / `DependsOn` / `Triggers` / `OnlyWhenStatic`** compose the dependency graph. Don't call other targets — declare dependencies.

## Running targets

| Command | Effect |
|---|---|
| `./build.sh` (no args) | Runs the default target declared in `Main()` (`Compile` above). |
| `./build.sh Test` | Run a specific target. Dependencies execute automatically. |
| `./build.sh Test Pack` | Multiple targets. |
| `./build.sh Test --configuration Release` | Override a `[Parameter]`. |
| `./build.sh Test --skip Compile` | Skip a dependency (assumes it's already done). |
| `./build.sh --plan` | Print the dependency graph and exit. |
| `./build.sh --help` | List all targets and parameters. |

## Common targets to add

### `Pack`

```csharp
Target Pack => _ => _
    .DependsOn(Test)
    .Produces(ArtifactsDirectory / "*.nupkg")
    .Executes(() =>
    {
        DotNetPack(s => s
            .SetProject(Solution)
            .SetConfiguration(Configuration)
            .SetOutputDirectory(ArtifactsDirectory)
            .EnableNoBuild()
            .EnableNoRestore()
            .SetVersion(GitVersion.NuGetVersionV2));
    });
```

### `Push` (NuGet feed)

```csharp
[Parameter] [Secret] readonly string NuGetApiKey;
[Parameter] readonly string NuGetSource = "https://api.nuget.org/v3/index.json";

Target Push => _ => _
    .DependsOn(Pack)
    .Requires(() => NuGetApiKey)
    .OnlyWhenStatic(() => GitRepository.IsOnMainBranch())
    .Executes(() =>
    {
        ArtifactsDirectory.GlobFiles("*.nupkg")
            .ForEach(pkg => DotNetNuGetPush(s => s
                .SetTargetPath(pkg)
                .SetSource(NuGetSource)
                .SetApiKey(NuGetApiKey)));
    });
```

`[Secret]` ensures the value is redacted from logs and refused on insecure parameter sources.

### `Coverage` (coverlet + ReportGenerator)

```csharp
Target Coverage => _ => _
    .DependsOn(Compile)
    .Produces(CoverageDirectory / "*.cobertura.xml")
    .Executes(() =>
    {
        DotNetTest(s => s
            .SetProjectFile(Solution)
            .SetConfiguration(Configuration)
            .EnableNoBuild()
            .SetResultsDirectory(TestResultsDirectory)
            .SetDataCollector("XPlat Code Coverage")
            .SetSettingsFile(RootDirectory / "coverlet.runsettings"));

        TestResultsDirectory.GlobFiles("**/coverage.cobertura.xml")
            .ForEach(f => CopyFile(f, CoverageDirectory / "coverage.cobertura.xml", FileExistsPolicy.Overwrite));
    });
```

This matches the coverlet recipe in `testcontainers-dotnet`.

### `Container` (SDK container support)

```csharp
[Parameter] readonly string ContainerRegistry = "myregistry.azurecr.io";

Target PublishContainer => _ => _
    .DependsOn(Compile)
    .OnlyWhenStatic(() => GitRepository.IsOnMainBranch())
    .Executes(() =>
    {
        DotNetPublish(s => s
            .SetProject(Solution.MyService_Api)
            .SetConfiguration(Configuration)
            .EnableNoBuild()
            .SetProperty("PublishProfile", "DefaultContainer")
            .SetProperty("ContainerRegistry", ContainerRegistry)
            .SetProperty("ContainerImageTag", GitVersion.SemVer));
    });
```

This uses .NET's built-in SDK container support — no Dockerfile required.

## Parameters

`[Parameter]` makes a field bindable from `.nuke/parameters.json`, environment variables, and command-line flags. Precedence (highest wins): CLI flag → env var (`NUKE_*` or matching var) → `parameters.json` → field initialiser default.

```csharp
[Parameter("Configuration: Debug or Release.")]
readonly Configuration Configuration = IsLocalBuild ? Configuration.Debug : Configuration.Release;

[Parameter("Skip tests when set.")]
readonly bool SkipTests;
```

CI sets parameters via env vars. The bootstrap scripts read them and pass through to the build executable.

## GitVersion integration

```csharp
using Nuke.Common.Tools.GitVersion;

[GitVersion] readonly GitVersion GitVersion;

// later
.SetVersion(GitVersion.NuGetVersionV2)
.SetAssemblyVersion(GitVersion.AssemblySemVer)
.SetFileVersion(GitVersion.AssemblySemFileVer)
.SetInformationalVersion(GitVersion.InformationalVersion)
```

Requires `GitVersion.yml` at repo root (the management repo ships one). Falls back to commit SHA if no tags.

## Multiple files via `partial class`

Split a long `Build.cs` by area:

```
build/
  Build.cs                  // partial class Build (core targets)
  Build.Coverage.cs         // partial class Build (Coverage, ReportGenerator)
  Build.Container.cs        // partial class Build (PublishContainer, scan)
  Build.Release.cs          // partial class Build (Pack, Push, GitHub release)
  Configuration.cs          // Configuration enum
```

Each file declares `partial class Build : NukeBuild`. Targets defined anywhere are discovered.

## CI integration

### GitHub Actions

Two patterns. The NUKE-generated YAML (via `[GitHubActions]` attribute on the Build class) auto-regenerates `.github/workflows/*.yml` whenever you change targets — preferred for keeping CI and build in sync. The hand-written form is simpler when you only have one target:

```yaml
name: ci
on:
  push: { branches: [main] }
  pull_request:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }              # GitVersion needs history
      - uses: actions/setup-dotnet@v4
        with: { dotnet-version: '10.0.x' }
      - run: ./build.sh Test Pack Coverage
        env:
          NUKE_TELEMETRY_OPTOUT: "1"
```

For the auto-generated workflow path:

```csharp
[GitHubActions(
    "ci",
    GitHubActionsImage.UbuntuLatest,
    AutoGenerate = true,
    FetchDepth = 0,
    OnPushBranches = ["main"],
    OnPullRequestBranches = ["main"],
    InvokedTargets = [nameof(Test), nameof(Pack), nameof(Coverage)],
    ImportSecrets = [nameof(NuGetApiKey)])]
class Build : NukeBuild { /* ... */ }
```

After editing, `./build.sh --plan` regenerates `.github/workflows/ci.yml`. Commit the regenerated YAML.

### Azure DevOps / GitLab / Jenkins

Same story — invoke `./build.sh <Target>` from a single step. Equivalent attributes exist (`[AzurePipelines]`, `[GitLab]`, `[Jenkins]`, `[TeamCity]`).

## Local-build conveniences

```csharp
public static int Main() => Execute<Build>(x => x.Compile);

Target Default => _ => _
    .DependsOn(Compile)
    .DependsOn(Test);
```

Plus the **JetBrains Rider / VS run configurations** that `nuke :setup` writes — F5 on the build project runs your selected target with the debugger attached. Set a breakpoint inside an `.Executes` lambda; it hits.

## Common pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| GitVersion returns `0.1.0` always | Shallow clone | `fetch-depth: 0` on `actions/checkout`. |
| `Solution.MyService_Api` doesn't compile | `[Solution(GenerateProjects = true)]` missing, or solution not yet built | Run `./build.sh --plan` once; NUKE generates the typed project surface. |
| `[Parameter]` reads `null` in CI | Env var name mismatch | Either rename to `NUKE_<PARAM>` or use the explicit name attribute `[Parameter(Name = "MyVar")]`. |
| Targets re-run on every CI step | Each step shells `./build.sh` separately | Combine into one step: `./build.sh Test Pack Coverage`. |
| Slow first run in CI | `dotnet restore` warms NuGet cache from scratch | Cache `~/.nuget/packages` keyed on `**/*.csproj` + `packages.lock.json`. |
| Bootstrap script can't find SDK | Self-installed SDK location | Either rely on `setup-dotnet` (CI) or set `DOTNET_INSTALL_DIR` (local). |
| `Push` accidentally publishes from PR branch | Missing `OnlyWhenStatic(() => GitRepository.IsOnMainBranch())` | Add the guard. NUKE will skip the target on non-main branches. |
| Secret prints in logs | Field marked `[Parameter]` but not `[Secret]` | Add `[Secret]`. NUKE redacts and prevents loading from insecure sources. |

## When NOT to use NUKE

- Single-file projects where `dotnet build` + 10 lines of GitHub Actions YAML is enough — NUKE overhead is unjustified.
- Languages where the entire stack is not .NET (Node, Python, Go). Use the native idiom; reach for NUKE only if the project is .NET-primary and you want one source of truth across local + CI.

## Pair with

- **`fullstack-dev-skills:dotnet-core-expert`** — the build targets compile the canonical .NET 10 stack described there.
- **`fullstack-dev-skills:testcontainers-dotnet`** — the `Test` target should run against the integration-test recipe (xUnit v3 + MTP + coverlet).
- **`fullstack-dev-skills:dotnet-code-analyzer`** — the `Compile` target enforces analyzer warnings as errors; expect the failure surface described there.
- **`fullstack-dev-skills:jetbrains-lint-pro`** — add a `ReSharperCleanup` / `ReSharperInspect` target that wraps `jb cleanupcode` / `jb inspectcode` on changed files only.
- **`fullstack-dev-skills:shipping-and-launch`** — the `Pack` / `PublishContainer` / `Push` chain is the build half of the launch checklist; pair with the post-launch monitoring section there.
