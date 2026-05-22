# fullstack-dev-skills

A Claude Code plugin marketplace bundling skills for full-stack development.

## Skills included

- **dotnet-core-expert** — .NET 10 / C# 14 with minimal APIs, clean architecture, EF Core, CQRS/MediatR, JWT auth.

## Install

### 1. Install the Claude Code CLI

Requires Node.js 18+.

```sh
npm install -g @anthropic-ai/claude-code
```

Verify the install and authenticate:

```sh
claude --version
claude            # first run walks you through sign-in
```

Other install methods (Homebrew, native installer, etc.) and full docs: <https://docs.claude.com/en/docs/claude-code/overview>.

### 2. Add this marketplace and install the plugin

Start Claude Code in any directory:

```sh
claude
```

Then run these slash commands inside the Claude Code session:

```
/plugin marketplace add mindsandco/tools.asset.insights.portal.skills
/plugin install fullstack-dev-skills@fullstack-dev-skills
```

The argument to `marketplace add` is `<owner>/<repo>` on GitHub. After install, the skills auto-load and trigger from their `SKILL.md` descriptions.

> **Note:** `/plugin` is only available inside the interactive Claude Code TUI. If you see `/plugin isn't available in this environment`, you're running in a non-interactive context (e.g. piped input, an SDK harness, or a web client) — open a regular terminal and run `claude` first.

### 3. Update later

From inside Claude Code:

```
/plugin marketplace update fullstack-dev-skills
```

## Repository layout

```
.claude-plugin/
  marketplace.json   # marketplace manifest (this repo)
  plugin.json        # plugin manifest
skills/
  dotnet-core-expert/
    SKILL.md
    references/
```

## Adding a new skill

1. Create `skills/<skill-name>/SKILL.md` with YAML frontmatter (`name`, `description`).
2. Bump `version` in both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.
3. Commit and push — users run `/plugin marketplace update fullstack-dev-skills` to pull it.
