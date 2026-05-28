#!/usr/bin/env bash
# SessionStart hook. Emits JSON with hookSpecificOutput.additionalContext
# so the rule is silently injected into the session per Claude Code 2.1.0+.
# Phrased as factual statements, not imperative system commands, to avoid
# tripping prompt-injection defenses.

cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Operating principle for this session: use as few tokens as possible without compromising the work. Token economy never wins against correctness. Reads, searches, subagent spawns, and response length should be proportional to the task. Read only what is needed, do not re-read files already in context, batch tool calls when supported, synthesize tool output rather than relaying it, and do not spawn subagents for routine work the main agent has full context for. Spend the tokens when the work genuinely needs them: behaviour verification after edits, present-day fact lookups, second opinions on real risk, longer responses when the question warrants. The test is whether skipping the read, search, spawn, or sentence would make the work worse. If yes, keep it. If no, cut it."
  }
}
EOF