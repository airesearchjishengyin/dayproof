import Database from "better-sqlite3";
import { mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { randomUUID } from "node:crypto";
import {
  canAutoCheck,
  type Task,
  type TaskDraft,
  type Verdict,
} from "../shared/schema.ts";
export class Store {
  db: Database.Database;
  constructor(path: string) {
    mkdirSync(dirname(resolve(path)), { recursive: true });
    this.db = new Database(path);
    this.db.pragma("journal_mode = WAL");
    this.db.exec(
      "CREATE TABLE IF NOT EXISTS tasks(id TEXT PRIMARY KEY, body TEXT NOT NULL); CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL); CREATE TABLE IF NOT EXISTS events(id INTEGER PRIMARY KEY AUTOINCREMENT, body TEXT NOT NULL)",
    );
  }
  all(): Task[] {
    return (
      this.db.prepare("SELECT body FROM tasks").all() as { body: string }[]
    ).map((r) => JSON.parse(r.body));
  }
  get(id: string): Task {
    const r = this.db.prepare("SELECT body FROM tasks WHERE id=?").get(id) as
      { body: string } | undefined;
    if (!r) throw new Error("任务不存在");
    return JSON.parse(r.body);
  }
  save(t: Task): Task {
    this.db
      .prepare("INSERT OR REPLACE INTO tasks VALUES(?,?)")
      .run(t.id, JSON.stringify(t));
    return t;
  }
  add(d: TaskDraft): Task {
    return this.save({
      ...d,
      id: randomUUID(),
      status: "todo",
      createdAt: new Date().toISOString(),
      completedAt: null,
      completionSource: null,
      lastCheck: null,
      nextCheckAt: canAutoCheck(d.rule) ? new Date().toISOString() : null,
      revision: 0,
    });
  }
  import(ds: TaskDraft[]): Task[] {
    return this.db.transaction(() => ds.map((d) => this.add(d)))();
  }
  edit(id: string, d: TaskDraft): Task {
    const t = this.get(id);
    return this.save({
      ...t,
      ...d,
      status: "todo",
      completedAt: null,
      completionSource: null,
      lastCheck: null,
      nextCheckAt: canAutoCheck(d.rule) ? new Date().toISOString() : null,
      revision: t.revision + 1,
    });
  }
  complete(id: string, done: boolean, source = "手动确认"): Task {
    const t = this.get(id);
    this.event({
      taskId: id,
      title: t.title,
      reason: done ? "已确认完成" : "重新打开任务",
      source,
    });
    return this.save({
      ...t,
      status: done ? "done" : "todo",
      completedAt: done ? new Date().toISOString() : null,
      completionSource: done ? source : null,
      revision: t.revision + 1,
      nextCheckAt:
        done || !canAutoCheck(t.rule)
          ? null
          : new Date(Date.now() + t.intervalMinutes * 60000).toISOString(),
    });
  }
  applyCheck(id: string, revision: number, v: Verdict): Task {
    const t = this.get(id);
    if (t.revision !== revision || t.status === "done") return t;
    this.event({ taskId: id, title: t.title, ...v });
    return this.save({
      ...t,
      lastCheck: v,
      status: v.outcome === "pass" ? "done" : "todo",
      completedAt: v.outcome === "pass" ? v.checkedAt : null,
      completionSource: v.outcome === "pass" ? "自动验收" : null,
      nextCheckAt:
        v.outcome === "pass" || !canAutoCheck(t.rule)
          ? null
          : new Date(Date.now() + t.intervalMinutes * 60000).toISOString(),
    });
  }
  remove(id: string): void {
    this.get(id);
    this.db.prepare("DELETE FROM tasks WHERE id=?").run(id);
  }
  event(v: object): void {
    this.db
      .prepare("INSERT INTO events(body) VALUES(?)")
      .run(JSON.stringify({ at: new Date().toISOString(), ...v }));
    this.db.exec(
      "DELETE FROM events WHERE id NOT IN (SELECT id FROM events ORDER BY id DESC LIMIT 500)",
    );
  }
  events(): unknown[] {
    return (
      this.db
        .prepare("SELECT body FROM events ORDER BY id DESC LIMIT 50")
        .all() as { body: string }[]
    ).map((x) => JSON.parse(x.body));
  }
  settings(): { model: string } {
    const r = this.db
      .prepare("SELECT value FROM settings WHERE key='model'")
      .get() as { value: string } | undefined;
    return { model: r?.value || process.env.OLLAMA_MODEL || "qwen3:4b" };
  }
  setModel(model: string): void {
    this.db
      .prepare("INSERT OR REPLACE INTO settings VALUES('model',?)")
      .run(model);
  }
}
