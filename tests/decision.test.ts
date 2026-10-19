import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, writeFile, symlink, mkdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { decide } from "../src/server/decision.ts";
import { Store } from "../src/server/store.ts";
import { TaskInput, type Verdict } from "../src/shared/schema.ts";
async function fixture(fn: (dir: string, store: Store) => Promise<void>) {
  const dir = await mkdtemp(join(tmpdir(), "dayproof-test-"));
  const store = new Store(join(dir, "db.sqlite"));
  try {
    await fn(dir, store);
  } finally {
    store.db.close();
    await rm(dir, { recursive: true, force: true });
  }
}
const draft = (rule: unknown) =>
  TaskInput.parse({
    title: "完成订阅",
    day: "2026-10-19",
    criteria: "订阅状态必须为 active",
    rule,
  });
test("missing evidence stays pending; valid structured status completes; string does not equal boolean", () =>
  fixture(async (dir, store) => {
    const t = store.add(
      draft({
        type: "json_equals",
        path: "status.json",
        key: "subscription.active",
        value: true,
      }),
    );
    assert.equal((await decide(t, dir, "test")).outcome, "pending");
    await writeFile(
      join(dir, "status.json"),
      JSON.stringify({ subscription: { active: "true" } }),
    );
    assert.equal((await decide(t, dir, "test")).outcome, "pending");
    await writeFile(
      join(dir, "status.json"),
      JSON.stringify({ subscription: { active: true } }),
    );
    const v = await decide(t, dir, "test");
    assert.equal(v.outcome, "pass");
    assert.equal(store.applyCheck(t.id, t.revision, v).status, "done");
  }));
test("malformed JSON is an error and never completes", () =>
  fixture(async (dir, store) => {
    await writeFile(join(dir, "status.json"), "not json");
    const t = store.add(
      draft({
        type: "json_equals",
        path: "status.json",
        key: "active",
        value: true,
      }),
    );
    assert.equal((await decide(t, dir, "test")).outcome, "error");
  }));
test("path traversal and symlinks outside root cannot access evidence", () =>
  fixture(async (dir, store) => {
    const outside = await mkdtemp(join(tmpdir(), "dayproof-outside-"));
    try {
      await writeFile(join(outside, "secret"), "active");
      await symlink(join(outside, "secret"), join(dir, "link"));
      for (const path of [join(outside, "secret"), "link"]) {
        const t = store.add(draft({ type: "file_exists", path }));
        assert.equal((await decide(t, dir, "test")).outcome, "error");
      }
    } finally {
      await rm(outside, { recursive: true, force: true });
    }
  }));
test("directories and oversized documents cannot be used as text evidence", () =>
  fixture(async (dir, store) => {
    await mkdir(join(dir, "folder"));
    let t = store.add(draft({ type: "file_exists", path: "folder" }));
    assert.equal((await decide(t, dir, "test")).outcome, "error");
    await writeFile(join(dir, "huge.txt"), "a".repeat(33000));
    t = store.add(
      draft({ type: "file_contains", path: "huge.txt", text: "a" }),
    );
    assert.equal((await decide(t, dir, "test")).outcome, "error");
  }));
test("file existence and literal text rules require their actual condition", () =>
  fixture(async (dir, store) => {
    await writeFile(join(dir, "evidence.txt"), "subscription active");
    const t = store.add(draft({ type: "file_exists", path: "evidence.txt" }));
    assert.equal((await decide(t, dir, "test")).outcome, "pass");
    for (const [text, outcome] of [
      ["active", "pass"],
      ["payment confirmed", "pending"],
    ]) {
      const task = store.add(
        draft({ type: "file_contains", path: "evidence.txt", text }),
      );
      assert.equal((await decide(task, dir, "test")).outcome, outcome);
    }
  }));
test("stale check results cannot overwrite an edited or manually reopened task", () =>
  fixture(async (_dir, store) => {
    const t = store.add(draft({ type: "manual" }));
    const v: Verdict = {
      outcome: "pass",
      reason: "pass",
      evidence: "yes",
      confidence: 1,
      checkedAt: new Date().toISOString(),
    };
    store.edit(t.id, draft({ type: "manual" }));
    assert.equal(store.applyCheck(t.id, t.revision, v).status, "todo");
    const updated = store.get(t.id);
    store.complete(t.id, true);
    store.complete(t.id, false);
    assert.equal(store.applyCheck(t.id, updated.revision, v).status, "todo");
  }));
test("manual task does not auto-complete and edits clear previous completion", () =>
  fixture(async (dir, store) => {
    const t = store.add(draft({ type: "manual" }));
    assert.equal((await decide(t, dir, "test")).outcome, "review");
    store.complete(t.id, true);
    const edited = store.edit(t.id, draft({ type: "manual" }));
    assert.equal(edited.completedAt, null);
    assert.equal(edited.status, "todo");
    assert.equal(edited.lastCheck, null);
  }));
test("task validation rejects invalid calendar date, ambiguous deadline and model rule without criteria", () => {
  for (const extra of [
    { day: "2026-02-30" },
    { deadline: "2026-10-19T15:00" },
    { criteria: "", rule: { type: "llm", path: "a" } },
  ])
    assert.equal(
      TaskInput.safeParse({ title: "task", day: "2026-10-19", ...extra })
        .success,
      false,
    );
});
test("legacy model verification never calls fetch, never schedules, and requires manual confirmation", () =>
  fixture(async (dir, store) => {
    const original = globalThis.fetch;
    let calls = 0;
    globalThis.fetch = async () => {
      calls++;
      throw new Error("must not call model");
    };
    try {
      const t = store.add(
        draft({ type: "llm", path: "proof.txt", autoComplete: true }),
      );
      assert.equal(t.nextCheckAt, null);
      const result = await decide(t, dir, "any-model");
      assert.equal(result.outcome, "review");
      assert.equal(
        store.applyCheck(t.id, t.revision, result).nextCheckAt,
        null,
      );
      store.complete(t.id, true);
      assert.equal(store.complete(t.id, false).nextCheckAt, null);
      assert.equal(calls, 0);
    } finally {
      globalThis.fetch = original;
    }
  }));

test("data persists across database reopen", () =>
  fixture(async (dir, store) => {
    const t = store.add(draft({ type: "manual" }));
    store.complete(t.id, true);
    const other = new Store(join(dir, "db.sqlite"));
    try {
      assert.equal(other.get(t.id).status, "done");
      assert.equal(other.events().length, 1);
    } finally {
      other.db.close();
    }
  }));
