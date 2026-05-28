---
name: subagent-enforcer
description: Evaluate whether one or more subagents (Explore, Plan, general-purpose, or any fullstack-dev-skills specialist — api-designer, backend-developer, code-reviewer, database-optimizer, performance-engineer, readme-generator, security-auditor, test-engineer) should be used before starting non-trivial work. Trigger when a task splits into independent tracks that can run in parallel, when an adversarial second opinion materially reduces risk (security, correctness on a sizeable diff, perf against a baseline), or when bulk fact-finding would otherwise consume main-context tokens. Spawn using the Agent tool with a self-contained brief. Do NOT trigger on routine multi-file edits, small refactors, or tasks the main agent already has full context for.
license: MIT
metadata:
  author: https://github.com/mindsandco
  version: "2.0.0"
  domain: process
  triggers: subagent, delegate, parallel agents, fan out, spawn agent, second opinion, multi-agent
  role: orchestrator
  scope: orchestration
  output-format: process
  related-skills: planning-and-task-breakdown, incremental-implementation, code-reviewer, shipping-and-launch
---

# Subagent Enforcer

## Overview

The main agent's context is reserved for orchestration, judgment, and synthesis. Subagents pay off when work splits into genuinely independent tracks, when a second pair of eyes materially reduces risk, or when bulk fact-finding would crowd the main context. They do not pay off on routine work the main agent can finish in a few tool calls — fan-out costs tokens, latency, and brief-writing overhead that often exceeds the savings.

## Token discipline (general operating principle)

**Use as few tokens as possible without compromising the work.** This is not a rule scoped to this skill — it applies to every action the agent takes: tool calls, file reads, web searches, subagent spawns, and the response itself. Token economy never wins against correctness. If the work needs three agents, three file reads, or a long response to be done right, spend them.

General application:

- Read only what you need. Don't `cat` a 2000-line file when a `grep` or a targeted view range will do.
- Don't re-read files already in context.
- Don't search the web for things already known with high confidence (see the search-first rules — they're about correctness on present-day facts, not blanket searching).
- Keep responses proportional to the question. A one-line answer doesn't need three paragraphs of setup.
- Synthesize tool output, don't relay it.

Specific to this skill:

- Don't spawn a subagent when the main agent already has the context to finish in a few calls. Fan-out duplicates system prompts and tool definitions per subagent.
- Don't spawn parallel agents on dependent work. Plan → implement → test → review is sequential; parallel framing here just adds round-trip overhead.
- Keep briefs short but complete. Every value the subagent would otherwise guess must be in the brief (paths, line numbers, exact identifiers). Brevity without completeness causes silent wrong-output and forces a redo, which costs more than a longer brief would have.
- If a cheap agent (`Explore`) can do the fact-finding leg, route that leg there instead of bundling it into a heavyweight specialist's brief.

## When to use

Trigger when the task matches ANY of these:

- Work splits into **independent** tracks (e.g. backend endpoint + frontend component + DB migration where the contracts are settled). Independence is the test, not file count.
- An **adversarial second opinion** materially reduces risk: security audit on auth-touching code, correctness review on a sizeable diff, perf analysis against a baseline.
- **Bulk fact-finding** would otherwise eat main context: locating symbols across a large repo, mapping call sites, surveying naming conventions.
- The user explicitly asks for review, audit, or a second opinion.

## When NOT to use

- Routine multi-file edits the main agent has full context for.
- Small refactors, single-feature changes, or bug fixes scoped to a known area.
- Sequential work with no independent legs.
- "I think this is simple" cases where you actually do have the context — trust that judgment instead of overriding it. The previous version of this skill forced delegation here; that was wrong.

## Routing — pick the cheapest fit

| Subagent | Use for |
|---|---|
| `Explore` | broad codebase structure, locating symbols, naming-convention searches, "where is X defined" |
| `Plan` | architecture trade-offs and implementation strategy before writing code |
| `general-purpose` | open-ended research spanning multiple files when the right keyword isn't obvious |
| `fullstack-dev-skills:api-designer` | REST/GraphQL endpoint design, OpenAPI specs, versioning strategy |
| `fullstack-dev-skills:backend-developer` | server-side APIs and microservices with production-ready scaffolding |
| `fullstack-dev-skills:code-reviewer` | five-axis review (correctness, readability, architecture, security, performance) on a diff |
| `fullstack-dev-skills:database-optimizer` | slow queries, indexing strategy, EXPLAIN analysis |
| `fullstack-dev-skills:performance-engineer` | application/database/infra bottleneck hunting against a baseline |
| `fullstack-dev-skills:readme-generator` | maintainer-ready README built from scanned repo reality |
| `fullstack-dev-skills:security-auditor` | vulnerability detection, threat modelling, secure-coding review |
| `fullstack-dev-skills:test-engineer` | test strategy, test writing, coverage analysis |

Default to `Explore` / `general-purpose` for fact-finding before involving a specialist. Reserve `fullstack-dev-skills:*` specialists for tasks that genuinely match their description. Over-routing dilutes their value and wastes tokens.

If part of the work is locating code, route that leg to `Explore` in parallel with the substantive work going to a specialist. Sending everything to one heavyweight agent wastes cycles.

## Scope discipline — carve cleanly, don't overlap

When fanning out 2+ review/audit agents, give each a non-overlapping mandate. Overlap produces duplicate findings, harder synthesis, and wasted tokens.

Good carve-up for a "review this PR" task:

- `Explore` → locate touched files, list call sites, surface related tests ONLY
- `fullstack-dev-skills:code-reviewer` → correctness / readability / architecture / performance ONLY
- `fullstack-dev-skills:security-auditor` → security only (no style or perf findings)
- `fullstack-dev-skills:test-engineer` → coverage gaps and test quality ONLY

Write the exclusion into each brief explicitly ("do not cover X — that is delegated elsewhere").

## Brief hygiene

Each `Agent` call gets a self-contained brief. Include:

- Goal in one line
- Exact files / paths to consult (with line numbers when possible)
- Output format + word limit
- What NOT to cover (delegated to sibling agents)
- Any values the subagent would otherwise guess — look these up first

Never put a guessed value in a brief. Subagents can't ask clarifying questions. If you don't know the connection string template, the build command, the branch name, grep or read first, or tell the subagent "use the value from `appsettings.Development.json` or omit the field." Brief leakage causes silent wrong-output and a re-run, which is the most expensive failure mode in this whole workflow.

Never write "based on your findings, fix it." That delegates understanding to the subagent and prevents synthesis across multiple returns.

## Spawning (exact format)

```
Agent({
  description: "Short 3-5 word description",
  prompt: "Self-contained brief: goal + files + output format + word limit + exclusions",
  subagent_type: "Explore" | "Plan" | "general-purpose" |
                 "fullstack-dev-skills:code-reviewer" | "fullstack-dev-skills:security-auditor" |
                 "fullstack-dev-skills:test-engineer"  | "fullstack-dev-skills:api-designer" |
                 "fullstack-dev-skills:backend-developer" | "fullstack-dev-skills:database-optimizer" |
                 "fullstack-dev-skills:performance-engineer" | "fullstack-dev-skills:readme-generator"
})
```

Spawn parallel calls in a single message with multiple `Agent` tool uses. Sequential calls in separate messages are fake parallelism.

## After subagents return — verify, don't trust

1. **Inspect the diff.** If a subagent edited files, run `git diff` (or read changed files) before claiming done. Subagents misformat, pick wrong constants, or silently drop a requested change.
2. **Verify behaviour, not just compilation.** `dotnet build` / `pnpm build` proves it compiles. It does not prove the endpoint returns the expected shape, the EF query actually tracks, or the React route renders. After the build, spot-check the actual output: hit the route, run the integration test, inspect the rendered DOM.
3. **Account for every parallel slot.** If you spawned 4 and only 3 returned, something failed (timeout, error, rate limit). Surface the gap; don't pretend the wave was complete.
4. **State what was deferred.** If reviewer agents surfaced 7 items and the implementer did 4, list the 3 deferred items with one-line reasons. The user can't redirect what they can't see.

## Synthesis & handoff

- Synthesize concisely. Do not dump raw subagent reports back to the user.
- Present: what changed, what was verified, what was deferred, what's open.
- If files are modified and uncommitted, ask the user whether to commit before ending the turn. Don't leave dangling state silently.

## Common patterns

### "Review this PR / branch"

Fan out in one message:

- `Explore` → list changed files and their call sites
- `fullstack-dev-skills:code-reviewer` → correctness, readability, architecture, perf (NOT security)
- `fullstack-dev-skills:security-auditor` → security only
- `fullstack-dev-skills:test-engineer` → coverage gaps

### "Build feature X end-to-end"

1. `Plan` first — get the slice breakdown.
2. Then per slice, either `fullstack-dev-skills:backend-developer` or implement directly. Direct is usually cheaper if you have the context.
3. `fullstack-dev-skills:test-engineer` for the test plan if the surface area justifies it.
4. `fullstack-dev-skills:code-reviewer` before merge if the diff is sizeable or touches sensitive areas.

### "Why is this slow?"

- `Explore` → locate hot path
- `fullstack-dev-skills:database-optimizer` (if DB-bound) AND/OR `fullstack-dev-skills:performance-engineer` (if app/infra-bound) — in parallel if both plausible

## Enforcement

When a task matches the "when to use" criteria, spawn. When it matches "when NOT to use," do the work directly. The decision is the orchestrator's, and the cost of a wrong call in either direction is real: under-spawning misses risk; over-spawning burns tokens and time. Bias toward the cheaper choice that still gets the work done correctly.