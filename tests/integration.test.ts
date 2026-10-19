import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn, type ChildProcess } from "node:child_process";
import { mkdtemp, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { once } from "node:events";
import { createServer } from "node:net";
import { request as httpRequest } from "node:http";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import type { Task } from "../src/shared/schema.ts";
test(
  "real HTTP, SQLite, scheduler and MCP workflow",
  { timeout: 45000 },
  async () => {
    const dir = await mkdtemp(join(tmpdir(), "dayproof-integration-"));
    const socket = createServer();
    socket.listen(0, "127.0.0.1");
    await once(socket, "listening");
    const port = (socket.address() as { port: number }).port;
    await new Promise<void>((r) => socket.close(() => r()));
    const url = `http://127.0.0.1:${port}`,
      env = {
        ...process.env,
        PORT: String(port),
        DATA_DIR: dir,
        EVIDENCE_ROOT: dir,
      };
    let child: ChildProcess | undefined;
    let client: Client | undefined;
    try {
      child = spawn(resolve("node_modules/.bin/tsx"), ["src/server/index.ts"], {
        env,
        stdio: ["ignore", "pipe", "pipe"],
      });
      let logs = "";
      child.stdout!.on("data", (d) => {
        logs += String(d);
      });
      child.stderr!.on("data", (d) => {
        logs += String(d);
      });
      for (let i = 0; i < 100; i++) {
        if (logs.includes("Dayproof →")) break;
        if (child.exitCode !== null) throw new Error(logs);
        await new Promise((r) => setTimeout(r, 100));
      }
      assert.match(logs, /Dayproof →/);
      assert.equal((await fetch(url + "/api/state")).status, 401);
      assert.equal(
        (
          await fetch(url + "/api/session", {
            headers: { Origin: "https://evil.example" },
          })
        ).status,
        403,
      );
      const badHost = await new Promise<number | undefined>(
        (resolve, reject) => {
          const req = httpRequest(
            url + "/api/session",
            { headers: { Host: "evil.example" } },
            (res) => {
              res.resume();
              resolve(res.statusCode);
            },
          );
          req.on("error", reject);
          req.end();
        },
      );
      assert.equal(badHost, 403);
      const session = await fetch(url + "/api/session");
      assert.match(session.headers.get("set-cookie") || "", /HttpOnly/);
      const token = (await readFile(join(dir, "token"), "utf8")).trim();
      const request = async (path: string, method = "GET", body?: unknown) => {
        const r = await fetch(url + "/api" + path, {
          method,
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          body: body === undefined ? undefined : JSON.stringify(body),
        });
        return { r, data: await r.json() };
      };
      const day = new Date().toLocaleDateString("en-CA", {
        timeZone: "Asia/Shanghai",
      });
      const input = {
        title: "验收订阅",
        day,
        criteria: "状态 active",
        source: "Test",
        rule: {
          type: "json_equals",
          path: "subscription.json",
          key: "subscription.active",
          value: true,
        },
      };
      const created = await request("/tasks", "POST", input);
      assert.equal(created.r.status, 201);
      const task = created.data as Task;
      assert.equal(
        (await request(`/tasks/${task.id}/check`, "POST", {})).data.lastCheck
          .outcome,
        "pending",
      );
      const invalid = await request("/plan/import", "POST", {
        tasks: [
          { title: "should rollback", day },
          { title: "", day },
        ],
      });
      assert.equal(invalid.r.status, 400);
      assert.equal((await request("/state")).data.tasks.length, 1);
      // Force due time without changing production clock, then let the real 10s scheduler perform the check.
      await writeFile(
        join(dir, "subscription.json"),
        JSON.stringify({ subscription: { active: true } }),
      );
      await request(`/tasks/${task.id}`, "PUT", input);
      for (let i = 0; i < 125; i++) {
        const current = (await request("/state")).data.tasks[0];
        if (current.status === "done") break;
        await new Promise((r) => setTimeout(r, 100));
      }
      const completed = (await request("/state")).data.tasks[0];
      assert.equal(completed.status, "done");
      assert.equal(completed.completionSource, "自动验收");
      client = new Client({ name: "dayproof-test", version: "1.0" });
      await client.connect(
        new StdioClientTransport({
          command: resolve("node_modules/.bin/tsx"),
          args: [resolve("src/server/mcp.ts")],
          env: {
            ...Object.fromEntries(
              Object.entries(process.env).filter(
                (e): e is [string, string] => e[1] !== undefined,
              ),
            ),
            DATA_DIR: dir,
            DAYPROOF_URL: url,
          },
        }),
      );
      const list = await client.listTools();
      assert.equal(list.tools.length, 4);
      const planned = await client.callTool({
        name: "dayproof_create_plan",
        arguments: {
          tasks: [
            {
              title: "MCP 写入的计划",
              day,
              source: "Codex",
              criteria: "产出评审文档",
            },
          ],
        },
      });
      assert.notEqual(planned.isError, true);
      const rows = await client.callTool({
        name: "dayproof_list_tasks",
        arguments: { day, limit: 1, offset: 1 },
      });
      const result = JSON.parse((rows.content as { text: string }[])[0].text);
      assert.equal(result.total, 2);
      assert.equal(result.items.length, 1);
      await writeFile(join(dir, "progress.md"), "- [x] 保存游戏进度\n");
      const codePlan = await client.callTool({
        name: "dayproof_create_plan",
        arguments: {
          tasks: [
            {
              title: "游戏阶段进展",
              day,
              rule: {
                type: "markdown_checklist",
                path: "progress.md",
                items: ["保存游戏进度"],
              },
            },
          ],
        },
      });
      assert.notEqual(codePlan.isError, true);
      const [codeTask] = JSON.parse(
        (codePlan.content as { text: string }[])[0].text,
      );
      const codeCheck = await client.callTool({
        name: "dayproof_check_task",
        arguments: { id: codeTask.id },
      });
      assert.notEqual(codeCheck.isError, true);
      assert.equal(
        JSON.parse((codeCheck.content as { text: string }[])[0].text).status,
        "done",
      );
      const legacy = await request("/tasks", "POST", {
        title: "旧模型任务",
        day,
        criteria: "用户确认",
        rule: { type: "llm", path: "missing", autoComplete: true },
      });
      assert.equal(legacy.data.nextCheckAt, null);
      const legacyCheck = await request(
        `/tasks/${legacy.data.id}/check`,
        "POST",
        {},
      );
      assert.equal(legacyCheck.data.lastCheck.outcome, "review");
      assert.equal(legacyCheck.data.nextCheckAt, null);
      const missing = await client.callTool({
        name: "dayproof_check_task",
        arguments: { id: "00000000-0000-4000-8000-000000000000" },
      });
      assert.equal(missing.isError, true);
      const exportData = await request("/export");
      assert.equal(exportData.data.tasks.length, 4);
      assert.ok(exportData.data.events.length >= 2);
    } finally {
      await client?.close();
      if (child && child.exitCode === null) {
        child.kill("SIGTERM");
        await once(child, "exit");
      }
      await rm(dir, { recursive: true, force: true });
    }
  },
);
