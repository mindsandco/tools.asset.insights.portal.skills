---
name: pr-description
description: Generates structured pull request descriptions (Why / What / Risks) from a branch's diff. Use whenever a PR is about to be opened or its body written — phrasings like "open a PR", "create a pull request", "draft a PR", "gh pr create", "write the PR body/description/summary/intro", "ready to ship this branch", or any request to document a branch's changes for review. Honors `.github/pull_request_template.md` when present.
license: MIT
metadata:
  author: https://github.com/mindsandco
  version: "1.1.0"
  domain: process
  triggers: PR, pull request, PR description, PR body, PR summary, PR intro, open PR, create PR, draft PR, gh pr create, write PR, document changes, review-ready
  role: specialist
  scope: review
  output-format: markdown
  related-skills: git-workflow-and-versioning, code-reviewer, incremental-implementation, shipping-and-launch, planning-and-task-breakdown
---

# PR Description Generator

Generate clear, comprehensive pull request descriptions that help reviewers quickly understand your changes.

## Overview

This skill analyzes code changes and generates structured PR descriptions with two key sections:
- **Why I'm Doing This**: Business context, technical motivation, and background
- **What I'm Doing**: Implementation details, technical decisions, risks, and review focus areas

## Scope and Boundaries

This skill **produces the description text**. It does not push branches or open the PR itself — those are the user's call, and the actual `gh pr create` invocation is handled by the surrounding workflow (see [git-workflow-and-versioning](../git-workflow-and-versioning/SKILL.md) for branch hygiene and the canonical `gh pr create --body "$(cat <<'EOF' … EOF)"` HEREDOC pattern that preserves Markdown formatting).

For the assumptions this skill leans on — small, atomic, single-purpose PRs (~100 lines, one logical change) — see [git-workflow-and-versioning](../git-workflow-and-versioning/SKILL.md). If the diff is sprawling or mixes concerns, surface that to the user rather than papering over it with a long description; splitting beats explaining. Connect risk callouts to the rollout/rollback thinking in [shipping-and-launch](../shipping-and-launch/SKILL.md) when the change is deployment-sensitive.

## Workflow

### Step 1: Gather Code Changes

Choose the appropriate method based on user input:

**Method A: Analyze Current Branch (Default)**
- Run `git status` to check the current branch and any uncommitted work
- Run `git diff main...HEAD` to see all changes since the branch diverged (triple-dot resolves to the merge-base automatically — no need to call `git merge-base` separately)
- Run `git log main..HEAD --oneline` to see commit history on this branch
- If the repo's default branch isn't `main` (e.g., `master`, `develop`), substitute accordingly — confirm with `git symbolic-ref refs/remotes/origin/HEAD` if unsure

**Method B: User-Specified Files**
- If the user mentions specific files, read those files
- Compare with git diff for those specific paths if needed

**Check for a repo PR template:**
Look for `.github/pull_request_template.md` (or `docs/pull_request_template.md`, `.github/PULL_REQUEST_TEMPLATE/*.md`). If one exists, treat its headings and checklist as the authoritative structure for the output and map the Why/What/Risks content into it instead of imposing this skill's default sections.

### Step 2: Understand the Changes

Analyze the code changes to understand:
1. **Purpose**: What problem is being solved? What feature is being added?
2. **Scope**: Which files/modules are affected? How significant are the changes?
3. **Type**: Is this a feature, bug fix, refactoring, optimization, or something else?
4. **Impact**: What are the functional changes? Any performance implications?
5. **Risks**: Breaking changes, edge cases, deployment considerations?

**Analysis Tips:**
- Look at file names and paths to understand affected modules
- Read commit messages for context
- Identify patterns: new files (feature), modified logic (bug fix), restructured code (refactoring)
- Check for configuration changes, database migrations, API changes
- Note any TODO comments or follow-up work mentioned

### Step 3: Generate the PR Description

Create a structured Markdown description with these sections:

#### Why I'm Doing This
Provide context that helps reviewers understand the motivation:
- Business problem or user need being addressed
- Technical motivation (performance, security, maintainability, tech debt)
- Reference to related issues, tickets, or discussions
- Background information for those unfamiliar with the context

**Keep it concise but informative** - 2-4 sentences or bullet points typically suffice.

#### What I'm Doing
Describe the implementation in a way that aids review:

**High-level summary** (required):
- Brief overview of the changes (1-2 sentences)
- Key components or files modified

**Technical details** (include when relevant):
- Important technical decisions and trade-offs
- New features or capabilities added
- Performance optimizations or improvements
- Architecture or design pattern changes
- Dependencies added or updated

**Testing and validation** (include when relevant):
- Test coverage added
- How changes were validated
- Edge cases handled

**Risks and considerations** (include when present):
- Breaking changes or deprecations
- Known limitations or edge cases
- Follow-up work needed
- Deployment considerations
- Areas requiring special review attention

**Format Guidelines:**
- Use bullet points for readability
- Group related changes together
- Highlight important information with **bold**
- Use code formatting for technical terms: `function_name`, `file.ts`
- Keep it scannable - reviewers should grasp key points quickly

### Step 4: Review and Refine

Before presenting the PR description:
- Ensure "Why" section provides sufficient context
- Verify "What" section accurately reflects the code changes
- Check that risks and important considerations are called out
- Confirm the description helps reviewers know what to focus on (this is the same lens as [code-reviewer](../code-reviewer/SKILL.md) — write the description for the reviewer's path through the diff, not the author's path through the work)

## Output Format

Present the generated PR description in a fenced Markdown block so the user can copy it directly into the PR body or pipe it to `gh pr create --body "$(cat <<'EOF' … EOF)"`:

```markdown
## Why I'm Doing This

[Context and motivation]

## What I'm Doing

[Implementation details]

**Technical Details:**
- [Key technical points]

**Risks:**
- [Any risks or considerations]
```

If a repo PR template was found in Step 1, mirror its headings and checklist instead of the template above — the team's existing structure takes precedence.

## Best Practices

1. **Be thorough but concise**: Include all relevant information without overwhelming reviewers
2. **Think like a reviewer**: What would help someone understand and review these changes?
3. **Call out the important stuff**: Highlight breaking changes, risks, and areas needing careful review
4. **Provide context**: Don't assume reviewers have full background knowledge
5. **Be honest about limitations**: Note known issues, follow-up work, or trade-offs made

## Examples and Reference

For detailed examples of well-written PR descriptions across different scenarios (features, bug fixes, optimizations, refactoring), see [pr_examples.md](references/pr_examples.md).

Load this reference when you need inspiration or want to understand best practices for specific types of changes.

## Related Skills

- [git-workflow-and-versioning](../git-workflow-and-versioning/SKILL.md) — branch hygiene, atomic commits, PR sizing, and the `gh pr create` HEREDOC pattern that consumes this skill's output
- [code-reviewer](../code-reviewer/SKILL.md) — the reviewer's-eye lens this skill writes for
- [incremental-implementation](../incremental-implementation/SKILL.md) — why small PRs read better than long descriptions
- [shipping-and-launch](../shipping-and-launch/SKILL.md) — rollout, rollback, and monitoring context for the Risks section when the change touches production
- [planning-and-task-breakdown](../planning-and-task-breakdown/SKILL.md) — source of the "Why" context when the work was planned upfront