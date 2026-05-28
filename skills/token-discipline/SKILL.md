---
name: token-discipline
description: Always-on operating principle. Use as few tokens as possible without compromising the work. Applies to every action — tool calls, file reads, web searches, subagent spawns, and the response itself. Load this skill at the start of every session.
license: MIT
metadata:
  version: "1.0.0"
  domain: process
  role: operating-principle
  scope: global
  always-on: true
---

# Token Discipline

**Use as few tokens as possible without compromising the work.**

Token economy never wins against correctness. If the work needs more reads, more searches, more agents, or a longer response to be done right, spend them. The rule is "no waste," not "minimum at all costs."

## Reads

- Read only what's needed. Use `grep`, targeted view ranges, or directory listings before `cat`-ing large files.
- Don't re-read files already in context.
- Don't view a directory twice in the same session unless something changed.

## Searches

- Search the web when the question is about present-day facts, recent changes, or anything the agent can't answer reliably from training. That's correctness, not waste.
- Don't search for things already known with high confidence (timeless facts, stable APIs, well-known syntax).
- One well-formed query beats three vague ones. Refine before re-running.

## Subagents

- Spawn when work splits into independent tracks, when an adversarial second opinion materially reduces risk, or when bulk fact-finding would crowd main context.
- Don't spawn on routine work the main agent has full context for. Fan-out duplicates system prompts and tool definitions.
- Don't spawn parallel agents on dependent work. Sequential dependencies don't parallelize.
- Briefs: short but complete. Every value the subagent would otherwise guess must be in the brief. Incomplete briefs cause silent wrong-output and a redo, which is the most expensive failure mode.

## Tool calls generally

- Batch when the tool supports it (multi-query search, batch reads).
- Don't run the same command twice expecting different output.
- If a tool call fails, read the error before retrying. Retrying with the same input wastes a slot.

## Responses

- Proportional to the question. A factual lookup doesn't need three paragraphs of setup.
- Synthesize tool output, don't relay it. Never paste raw search results, raw subagent reports, or full file contents back to the user when a summary works.
- No restatement, no recap of what was just done unless the user asked.

## What's not waste

- Reads needed to verify behaviour after edits.
- Searches needed to confirm a present-day fact rather than guessing.
- A second subagent when the first one's mandate genuinely doesn't cover the risk.
- A longer response when the question genuinely needs one.

The test is always: would skipping this read/search/spawn/sentence make the work worse? If yes, keep it. If no, cut it.