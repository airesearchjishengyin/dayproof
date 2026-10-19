import { open, realpath, stat } from "node:fs/promises";
import { resolve, relative, isAbsolute, sep } from "node:path";
import { homedir } from "node:os";
import {
  checkChecklist,
  checkReadingNotes,
  checkEmailDraft,
} from "./artifacts.ts";
import type { Task, Verdict } from "../shared/schema.ts";
const MAX_BYTES = 32768;
export async function evidencePath(
  path: string,
  root: string,
  directory = false,
): Promise<string> {
  const base = await realpath(root),
    target = await realpath(
      resolve(
        base,
        path.startsWith("~/") ? resolve(homedir(), path.slice(2)) : path,
      ),
    );
  const rel = relative(base, target);
  if (rel === ".." || rel.startsWith(`..${sep}`) || isAbsolute(rel))
    throw new Error("证据路径必须位于 EVIDENCE_ROOT 内（含符号链接目标）");
  const meta = await stat(target);
  if (directory ? !meta.isDirectory() : !meta.isFile())
    throw new Error(directory ? "笔记路径必须是目录" : "证据必须是普通文件");
  return target;
}
async function readEvidence(path: string): Promise<string> {
  const f = await open(path, "r");
  try {
    const meta = await f.stat();
    if (meta.size > MAX_BYTES)
      throw new Error("证据文件超过 32 KB，请提供精简状态文件");
    return await f.readFile("utf8");
  } finally {
    await f.close();
  }
}
export async function ollama(
  messages: { role: string; content: string }[],
  model: string,
  format: object,
): Promise<unknown> {
  const response = await fetch(
    `${process.env.OLLAMA_URL || "http://127.0.0.1:11434"}/api/chat`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        messages,
        stream: false,
        format,
        options: { temperature: 0 },
      }),
      signal: AbortSignal.timeout(90000),
    },
  );
  if (!response.ok)
    throw new Error(`Ollama 返回 ${response.status}，请检查服务及已安装模型`);
  const data = (await response.json()) as { message?: { content?: string } };
  return JSON.parse(data.message?.content || "");
}
export async function decide(
  task: Task,
  root: string,
  _model: string,
): Promise<Verdict> {
  const result = (
    outcome: Verdict["outcome"],
    reason: string,
    evidence = "",
    confidence: number | null = null,
  ): Verdict => ({
    outcome,
    reason,
    evidence,
    confidence,
    checkedAt: new Date().toISOString(),
  });
  try {
    const rule = task.rule;
    if (rule.type === "manual") return result("review", "等待你确认完成");
    if (rule.type === "llm")
      return result("review", "模型验收已停用，请手动确认；不会调用任何模型");
    let path: string;
    try {
      path = await evidencePath(rule.path, root, rule.type === "reading_notes");
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === "ENOENT")
        return result("pending", "尚未找到证据文件");
      throw e;
    }
    if (rule.type === "file_exists")
      return result("pass", "已找到约定的证据文件", rule.path, 1);
    if (rule.type === "reading_notes") {
      const v = await checkReadingNotes(
        path,
        rule.papers,
        rule.autoComplete,
        async (candidate) => readEvidence(await evidencePath(candidate, root)),
      );
      return result(v.outcome, v.reason, v.evidence);
    }
    const text = await readEvidence(path);
    if (rule.type === "markdown_checklist" || rule.type === "email_draft") {
      const v =
        rule.type === "markdown_checklist"
          ? checkChecklist(text, rule.items)
          : checkEmailDraft(text, rule.recipient, rule.autoComplete);
      return result(v.outcome, v.reason, v.evidence);
    }
    if (rule.type === "file_contains")
      return text.includes(rule.text)
        ? result("pass", "证据包含约定文本", rule.text, 1)
        : result("pending", "证据尚未包含约定文本");
    if (rule.type === "json_equals") {
      const data: unknown = JSON.parse(text);
      let value: unknown = data;
      for (const key of rule.key.split(".")) {
        if (!value || typeof value !== "object" || !Object.hasOwn(value, key)) {
          value = undefined;
          break;
        }
        value = (value as Record<string, unknown>)[key];
      }
      return value === rule.value
        ? result(
            "pass",
            `${rule.key} 已达到预期值`,
            JSON.stringify({ key: rule.key, value }),
            1,
          )
        : result("pending", `${rule.key} 尚未达到预期值`);
    }
    return result("error", "未知验收规则，请改用手动确认");
  } catch (e) {
    return result("error", e instanceof Error ? e.message : "检查失败");
  }
}
