import express from "express";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { randomBytes, timingSafeEqual } from "node:crypto";
import { z } from "zod";
import { Store } from "./store.ts";
import { decide, ollama } from "./decision.ts";
import {
  Day,
  SettingsInput,
  TaskInput,
  today,
  canAutoCheck,
} from "../shared/schema.ts";
process.env.TZ ||= "Asia/Shanghai";
const port = Number(process.env.PORT || 4317),
  dataDir = resolve(process.env.DATA_DIR || "data");
const root = resolve(process.env.EVIDENCE_ROOT || process.cwd());
mkdirSync(dataDir, { recursive: true, mode: 0o700 });
const tokenPath = resolve(dataDir, "token");
if (!existsSync(tokenPath))
  writeFileSync(tokenPath, randomBytes(32).toString("hex"), { mode: 0o600 });
const token = readFileSync(tokenPath, "utf8").trim();
const store = new Store(resolve(dataDir, "dayproof.sqlite"));
const app = express();
app.disable("x-powered-by");
app.use((req, res, next) => {
  const host = req.headers.host?.split(":")[0];
  if (!["localhost", "127.0.0.1"].includes(host || "")) {
    res.status(403).json({ error: "仅接受本地访问" });
    return;
  }
  const origin = req.headers.origin;
  if (
    origin &&
    !["http://localhost:" + port, "http://127.0.0.1:" + port].includes(origin)
  ) {
    res.status(403).json({ error: "跨来源请求被拒绝" });
    return;
  }
  if (req.headers["sec-fetch-site"] === "cross-site") {
    res.status(403).json({ error: "跨站请求被拒绝" });
    return;
  }
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Referrer-Policy", "no-referrer");
  res.setHeader("X-Frame-Options", "DENY");
  next();
});
app.get("/api/session", (req, res) => {
  res.setHeader("Cache-Control", "no-store");
  res.cookie("dayproof", token, {
    httpOnly: true,
    sameSite: "strict",
    path: "/",
  });
  res.json({ ok: true });
});
app.use("/api", (req, res, next) => {
  const supplied =
    req.headers.authorization?.replace(/^Bearer /, "") ||
    req.headers.cookie
      ?.split(";")
      .map((x) => x.trim())
      .find((x) => x.startsWith("dayproof="))
      ?.slice(9) ||
    "";
  const a = Buffer.from(supplied),
    b = Buffer.from(token);
  if (a.length !== b.length || !timingSafeEqual(a, b)) {
    res
      .status(401)
      .json({ error: "请刷新页面建立本地会话；CLI/MCP 需要本地访问令牌" });
    return;
  }
  if (
    ["POST", "PUT", "PATCH"].includes(req.method) &&
    !req.is("application/json")
  ) {
    res.status(415).json({ error: "请使用 application/json" });
    return;
  }
  res.setHeader("Cache-Control", "no-store");
  next();
});
app.use(express.json({ limit: "256kb" }));
const running = new Map<string, Promise<unknown>>();
function check(id: string): Promise<unknown> {
  const active = running.get(id);
  if (active) return active;
  const task = store.get(id);
  if (task.status === "done") return Promise.resolve(task);
  const work = decide(task, root, store.settings().model)
    .then((v) => store.applyCheck(id, task.revision, v))
    .finally(() => running.delete(id));
  running.set(id, work);
  return work;
}
app.get("/api/state", (_req, res) => {
  res.json({
    tasks: store.all(),
    events: store.events(),
    settings: store.settings(),
    today: today(),
    timezone: process.env.TZ,
    evidenceRoot: root,
    projectRoot: process.cwd(),
    dataDir,
    mcp:
      process.env.DAYPROOF_NODE && process.env.DAYPROOF_MCP_ENTRY
        ? {
            command: process.env.DAYPROOF_NODE,
            args: [process.env.DAYPROOF_MCP_ENTRY],
          }
        : {
            command: resolve("node_modules/.bin/tsx"),
            args: [resolve("src/server/mcp.ts")],
          },
    checking: [...running.keys()],
  });
});
app.get("/api/export", (_req, res) => {
  res.attachment(`dayproof-${today()}.json`).json({
    version: 1,
    exportedAt: new Date().toISOString(),
    timezone: process.env.TZ,
    tasks: store.all(),
    events: store.events(),
  });
});
app.post("/api/tasks", (req, res, next) => {
  try {
    res.status(201).json(store.add(TaskInput.parse(req.body)));
  } catch (e) {
    next(e);
  }
});
app.put("/api/tasks/:id", (req, res, next) => {
  try {
    res.json(store.edit(req.params.id, TaskInput.parse(req.body)));
  } catch (e) {
    next(e);
  }
});
app.patch("/api/tasks/:id/status", (req, res, next) => {
  try {
    const { done } = z.object({ done: z.boolean() }).strict().parse(req.body);
    res.json(store.complete(req.params.id, done));
  } catch (e) {
    next(e);
  }
});
app.delete("/api/tasks/:id", (req, res, next) => {
  try {
    store.remove(req.params.id);
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});
app.post("/api/tasks/:id/check", async (req, res, next) => {
  try {
    res.json(await check(req.params.id));
  } catch (e) {
    next(e);
  }
});
app.post("/api/check", async (req, res, next) => {
  try {
    const { day } = z.object({ day: Day }).strict().parse(req.body);
    const tasks = store
      .all()
      .filter(
        (t) => t.day === day && t.status === "todo" && canAutoCheck(t.rule),
      );
    for (const t of tasks) await check(t.id);
    res.json({ checked: tasks.length });
  } catch (e) {
    next(e);
  }
});
app.post("/api/plan/import", (req, res, next) => {
  try {
    const ds = z
      .object({ tasks: z.array(TaskInput).min(1).max(50) })
      .strict()
      .parse(req.body);
    res.status(201).json(store.import(ds.tasks));
  } catch (e) {
    next(e);
  }
});
app.post("/api/settings", (req, res, next) => {
  try {
    const s = SettingsInput.parse(req.body);
    store.setModel(s.model);
    res.json(store.settings());
  } catch (e) {
    next(e);
  }
});
app.get("/api/ollama", async (_req, res) => {
  try {
    const r = await fetch(
      `${process.env.OLLAMA_URL || "http://127.0.0.1:11434"}/api/tags`,
      { signal: AbortSignal.timeout(2500) },
    );
    if (!r.ok) throw new Error();
    const data = (await r.json()) as { models?: { name: string }[] };
    res.json({
      available: true,
      models: data.models?.map((x) => x.name) || [],
    });
  } catch {
    res.json({ available: false, models: [] });
  }
});
const PlanResult = z
  .object({
    tasks: z
      .array(
        z.object({
          title: z.string().min(1).max(200),
          criteria: z.string().min(1).max(2000),
          estimate: z.number().int().min(5).max(480),
          priority: z.enum(["high", "normal", "low"]),
          deadline: z.string().nullable(),
        }),
      )
      .min(1)
      .max(20),
  })
  .strict();
app.post("/api/plan/generate", async (req, res, next) => {
  try {
    const { goal, day } = z
      .object({ goal: z.string().trim().min(1).max(4000), day: Day })
      .strict()
      .parse(req.body);
    const raw = await ollama(
      [
        {
          role: "system",
          content: `Create a realistic daily plan in Chinese. Date: ${day}, timezone ${process.env.TZ}. Split goals into up to 8 concrete tasks with verifiable acceptance criteria. deadline must be ISO8601 with explicit offset or null. Never claim tasks are already complete. All tasks will be manually reviewed before import.`,
        },
        { role: "user", content: goal },
      ],
      store.settings().model,
      {
        type: "object",
        properties: {
          tasks: {
            type: "array",
            items: {
              type: "object",
              properties: {
                title: { type: "string" },
                criteria: { type: "string" },
                estimate: { type: "integer" },
                priority: { type: "string", enum: ["high", "normal", "low"] },
                deadline: { type: ["string", "null"] },
              },
              required: [
                "title",
                "criteria",
                "estimate",
                "priority",
                "deadline",
              ],
              additionalProperties: false,
            },
          },
        },
        required: ["tasks"],
        additionalProperties: false,
      },
    );
    const result = PlanResult.parse(raw);
    res.json({
      tasks: result.tasks.map((t) =>
        TaskInput.parse({
          ...t,
          day,
          source: "Ollama",
          rule: { type: "manual" },
        }),
      ),
    });
  } catch (e) {
    next(e);
  }
});
app.use("/api", (_req, res) => {
  res.status(404).json({ error: "API 不存在" });
});
const dist = resolve("dist");
if (existsSync(resolve(dist, "index.html"))) {
  app.use(express.static(dist));
  app.get("*", (_req, res) => res.sendFile(resolve(dist, "index.html")));
} else {
  const { createServer } = await import("vite");
  const vite = await createServer({
    server: { middlewareMode: true },
    appType: "spa",
  });
  app.use(vite.middlewares);
}
app.use(
  (
    err: unknown,
    _req: express.Request,
    res: express.Response,
    _next: express.NextFunction,
  ) => {
    const message =
      err instanceof z.ZodError
        ? err.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ")
        : err instanceof Error
          ? err.message
          : "请求失败";
    res.status(message === "任务不存在" ? 404 : 400).json({ error: message });
  },
);
let ticking = false;
const timer = setInterval(async () => {
  if (ticking) return;
  ticking = true;
  try {
    const due = store
      .all()
      .filter(
        (t) =>
          t.status === "todo" &&
          canAutoCheck(t.rule) &&
          t.day <= today() &&
          t.nextCheckAt &&
          Date.parse(t.nextCheckAt) <= Date.now(),
      );
    for (const t of due) {
      try {
        await check(t.id);
      } catch {
        /* a task may be removed during a check */
      }
    }
  } finally {
    ticking = false;
  }
}, 10000);
const server = app.listen(port, "127.0.0.1", () =>
  console.log(
    `Dayproof → http://127.0.0.1:${port}\nEvidence root: ${root}\nScheduler: 10s tick; runs while this server is alive.`,
  ),
);
for (const signal of ["SIGTERM", "SIGINT"] as const)
  process.on(signal, () => {
    clearInterval(timer);
    server.close(() => process.exit(0));
  });
