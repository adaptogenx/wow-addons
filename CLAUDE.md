Claude Code — WoW Addons

Follow AGENTS.md and the relevant scoped instructions.

Subagents

Prefer specialized subagents for substantial addon-specific work:

* ph — pH architecture, accounting, sessions, metrics, and UI.
* pockets — inventory, item interactions, capacity estimation, and UI.

Subagent definitions live in .claude/agents/.

Each subagent must read its addon’s AGENTS.md and relevant specifications before making changes.

Delegation

* Addon-specific work: Delegate substantial investigations and implementations to the corresponding subagent.
* Small changes: Handle directly.
* Shared code: Main agent coordinates changes; both addon subagents validate compatibility.
* Cross-addon changes: Main agent owns integration and final validation.

Use parallel subagents for independent investigations or reviews. Avoid concurrent edits to the same files.

Completion

Before reporting completion:

1. Run applicable checks and tests.
2. Verify shared changes against both addons.
3. Summarize changes, validation results, and outstanding manual tests.

Never claim unexecuted tests passed.
