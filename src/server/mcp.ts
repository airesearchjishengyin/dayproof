import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { z } from "zod";
import { Day, TaskInput, type Task } from "../shared/schema.ts";
const url = process.env.DAYPROOF_URL || "http://127.0.0.1:4317";
async function api(
  path: string,
  method = "GET",
  body?: unknown,
): Promise<unknown> {
  let token = process.env.DAYPROOF_TOKEN;
  if (!token) {
    try {
      token = readFileSync(
        resolve(process.env.DATA_DIR || "data", "token"),
        "utf8",
      ).trim();
    } catch {
      throw new Error(
        "Start Dayproof first, then set DATA_DIR to its absolute data directory or provide DAYPROOF_TOKEN.",
      );
    }
  }
  const r = await fetch(url + path, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(120000),
  });
  const data = (await r.json()) as { error?: string };
  if (!r.ok) throw new Error(data.error || `HTTP ${r.status}`);
  return data;
}
const server = new McpServer(
  { name: "dayproof", version: "0.1.0" },
  {
    instructions:
      "Use dayproof to persist user-approved daily plans. First list tasks to avoid duplicates. Create tasks with explicit timezone deadlines and acceptance criteria. Evidence files must be within the configured EVIDENCE_ROOT. Verification uses code only, never LLMs. README/checklist declarations are acceptable only when the user chooses declaration-based acceptance; never label them as runtime proof. Reading-note and email-draft structure checks default to human confirmation; autoComplete requires the user to accept those artifact criteria. Use check_task for verification; manual completion requires user confirmation.",
  },
);
const write = {
  readOnlyHint: false,
  destructiveHint: false,
  idempotentHint: false,
  openWorldHint: false,
};
function summary(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(summary);
  const t = value as Task;
  return {
    id: t.id,
    title: t.title,
    day: t.day,
    status: t.status,
    lastCheck: t.lastCheck,
    nextCheckAt: t.nextCheckAt,
  };
}
function toolResult(value: unknown) {
  return {
    content: [{ type: "text" as const, text: JSON.stringify(value, null, 2) }],
  };
}
async function safe(fn: () => Promise<unknown>) {
  try {
    return toolResult(await fn());
  } catch (e) {
    return {
      isError: true,
      content: [
        {
          type: "text" as const,
          text: e instanceof Error ? e.message : String(e),
        },
      ],
    };
  }
}
server.registerTool(
  "dayproof_list_tasks",
  {
    description:
      "List persisted daily tasks and verification outcomes. Filter by YYYY-MM-DD; omit to list all. Return paginated items and total. Use before creating a plan to avoid duplicates.",
    inputSchema: {
      day: Day.optional(),
      offset: z.number().int().min(0).default(0),
      limit: z.number().int().min(1).max(50).default(20),
    },
    annotations: { readOnlyHint: true, openWorldHint: false },
  },
  async ({ day, offset, limit }) =>
    safe(async () => {
      const state = (await api("/api/state")) as { tasks: Task[] };
      const list = state.tasks.filter((t) => !day || t.day === day);
      const items = list.slice(offset, offset + limit);
      while (items.length > 1 && JSON.stringify(items).length > 24000)
        items.pop();
      return {
        items,
        total: list.length,
        hasMore: offset + items.length < list.length,
        nextOffset: offset + items.length,
      };
    }),
);
server.registerTool(
  "dayproof_create_plan",
  {
    description:
      "Atomically create 1–50 tasks from a plan. Include day, explicit timezone deadline, acceptance criteria, and optional file/JSON/markdown_checklist/reading_notes/email_draft verification rule. Local-model verification is disabled; use manual for semantic checks. source should identify the caller, e.g. Codex or Claude Code. Returns created task IDs.",
    inputSchema: { tasks: z.array(TaskInput).min(1).max(50) },
    annotations: write,
  },
  async ({ tasks }) =>
    safe(async () => summary(await api("/api/plan/import", "POST", { tasks }))),
);
server.registerTool(
  "dayproof_check_task",
  {
    description:
      "Run the configured evidence checker for a task ID. May mark complete only when its configured rule passes. Missing evidence stays pending; semantic questions and legacy model rules need human review. Does not execute commands or operate subscriptions.",
    inputSchema: { id: z.string().uuid() },
    annotations: { ...write, idempotentHint: false },
  },
  async ({ id }) =>
    safe(async () => summary(await api(`/api/tasks/${id}/check`, "POST", {}))),
);
server.registerTool(
  "dayproof_update_task",
  {
    description:
      "Replace a task plan after listing it. Editing resets completion and previous verdict so the revised acceptance criteria must be checked again. Does not accept completion claims.",
    inputSchema: { id: z.string().uuid(), task: TaskInput },
    annotations: { ...write, idempotentHint: false },
  },
  async ({ id, task }) =>
    safe(async () => summary(await api(`/api/tasks/${id}`, "PUT", task))),
);
await server.connect(new StdioServerTransport());
