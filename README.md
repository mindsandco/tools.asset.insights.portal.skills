# fullstack-dev-skills

A Claude Code plugin marketplace bundling skills for full-stack development.

## Skills included

- **dotnet-core-expert** — .NET 10 / C# 14 with minimal APIs, clean architecture, EF Core, CQRS/MediatR, JWT auth.

## Install

In Claude Code, add this repo as a marketplace and install the plugin:

```
/plugin marketplace add mindsandco/tools.asset.insights.portal.skills
/plugin install fullstack-dev-skills@fullstack-dev-skills
```

The first argument to `marketplace add` is `<owner>/<repo>` on GitHub. After install, the skills auto-load and trigger from their `SKILL.md` descriptions.

To update later:

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
