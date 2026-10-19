# Fixed read-only MCP evaluation fixture

This fixture describes synthetic evaluation data, never the user's account state. It is not seeded into the normal application. To run an LLM evaluation, use a separate temporary DATA_DIR and a seeded SQLite Store containing these immutable tasks, then expose that server through the MCP bridge. Do not run these against live evolving plans.

All tasks have explicit configured acceptance criteria. `—` means no deadline or latest verdict. Counts and totals below are fixed and can be independently checked. These questions test list pagination, dates, statuses, sources, completion provenance and rule distinctions. The automated integration test separately exercises real MCP creation, listing, errors and actual scheduler completion.

| Title | Day | Source | Minutes | Status | Rule | Latest verdict | Deadline | Priority | Completion source |
|---|---|---|---:|---|---|---|---|---|---|
| Confirm subscription | 2026-10-19 | Claude Code | 30 | todo | JSON subscription.active = true | pending | 2026-10-19T10:00:00+08:00 | high | — |
| Review design memo | 2026-10-19 | Codex | 45 | todo | llm, autoComplete false | review | 2026-10-19T03:00:00Z | high | — |
| Load report | 2026-10-19 | Codex | 60 | todo | json status = "active" | error | — | normal | — |
| CI evidence | 2026-10-19 | Claude Code | 15 | done | file_contains "passed" | pass | — | normal | 自动验收 |
| Call supplier | 2026-10-19 | Claude Code | 30 | done | manual | — | — | normal | 手动确认 |
| Draft README | 2026-10-19 | Codex | 30 | todo | file_exists | pending | — | normal | — |
| Plan next release | 2026-10-19 | 手动 | 20 | todo | manual | — | — | low | — |
| Prepare demo | 2026-10-20 | Codex | 45 | todo | manual | — | — | high | — |
| Team review | 2026-10-20 | 手动 | 30 | todo | manual | — | — | normal | — |

Expected totals: 2026-10-19 = 230 minutes; 2026-10-20 = 75 minutes. Unfinished Codex = 180 minutes. Unfinished automatic 2026-10-19 = 4. Dates are intentionally fixed for repeatability.
