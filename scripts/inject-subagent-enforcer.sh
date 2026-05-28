#!/usr/bin/env bash
# SessionStart hook. Emits JSON with hookSpecificOutput.additionalContext
# so the rule is silently injected into the session per Claude Code 2.1.0+.
# Phrased as factual statements, not imperative system commands, to avoid
# tripping prompt-injection defenses.

cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Operating principle for this session: subagent fan-out via the Agent tool pays off when work splits into genuinely independent tracks, when an adversarial second opinion materially reduces risk (security audit on sensitive code, correctness review on a sizeable diff, performance analysis against a baseline), or when bulk fact-finding would otherwise consume main-context tokens. It does not pay off for routine multi-file edits, small refactors, or work the main agent already has full context for — fan-out costs system-prompt duplication, latency, and brief-writing overhead that often exceeds the savings. Routing favours the cheapest fit: Explore for locating symbols and codebase navigation, Plan for architecture trade-offs before implementation, general-purpose for open-ended research. The fullstack-dev-skills specialists (api-designer, backend-developer, code-reviewer, database-optimizer, performance-engineer, readme-generator, security-auditor, test-engineer) are reserved for tasks that genuinely match their description. Briefs are self-contained — every value the subagent would otherwise guess goes in the brief, since subagents cannot ask clarifying questions; brief leakage causes silent wrong-output and a redo, which is the most expensive failure mode. Parallel calls go in a single message with multiple Agent tool uses; sequential calls in separate messages are not parallelism. When fanning out review agents, each gets a non-overlapping mandate written explicitly into its brief. After subagents return, the diff is inspected before claiming done."
  }
}
EOF
