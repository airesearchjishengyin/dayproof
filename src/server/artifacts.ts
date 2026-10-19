// Pure artifact predicates. These check declarations/structure, not understanding
// or writing quality. No model, command execution, or network access.
import { readdir } from "node:fs/promises";
import { join } from "node:path";

export type ArtifactResult = {
  outcome: "pass" | "pending" | "review";
  reason: string;
  evidence: string;
};

// Ignore fenced code and comments: example checkboxes are not progress records.
export function markdownLines(text: string): string[] {
  let fence: { char: string; length: number } | null = null;
  return text
    .replace(/<!--[\s\S]*?-->/g, "")
    .split(/\r?\n/)
    .filter((line) => {
      const m = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(line);
      if (fence) {
        if (
          m &&
          m[1][0] === fence.char &&
          m[1].length >= fence.length &&
          !m[2].trim()
        )
          fence = null;
        return false;
      }
      if (m) {
        fence = { char: m[1][0], length: m[1].length };
        return false;
      }
      return true;
    });
}

export function checkChecklist(text: string, items: string[]): ArtifactResult {
  const entries = markdownLines(text).flatMap((line) => {
    const m = /^ {0,3}[-*+] \[([ xX])\] (.+?)\s*$/.exec(line);
    return m ? [{ checked: m[1].toLowerCase() === "x", label: m[2] }] : [];
  });
  const missing = items.filter((item) => {
    const matches = entries.filter((e) => e.label === item);
    return matches.length !== 1 || !matches[0].checked;
  });
  return missing.length
    ? {
        outcome: "pending",
        reason: `以下条目未唯一勾选：${missing.join("、")}`,
        evidence: "",
      }
    : {
        outcome: "pass",
        reason: "约定条目均已勾选（按进度声明验收）",
        evidence: items.map((i) => `- [x] ${i}`).join("\n"),
      };
}

export function paperKey(raw: string): string {
  const url = new URL(raw);
  if (!["https:", "http:"].includes(url.protocol))
    throw new Error("论文链接须为 HTTP(S)");
  // Different arXiv versions/PDF links still identify the same paper.
  if (
    ["arxiv.org", "www.arxiv.org", "export.arxiv.org"].includes(url.hostname)
  ) {
    const m = /^\/(?:abs|pdf)\/(.+)$/.exec(url.pathname);
    if (m) return `arxiv:${m[1].replace(/\.pdf$/i, "").replace(/v\d+$/, "")}`;
  }
  url.hash = "";
  return url.toString();
}

export async function checkReadingNotes(
  directory: string,
  papers: string[],
  autoComplete: boolean,
  read: (path: string) => Promise<string>,
): Promise<ArtifactResult> {
  const wanted = papers.map(paperKey);
  if (new Set(wanted).size !== wanted.length)
    throw new Error("论文清单存在重复论文（含 arXiv 不同版本）");
  const files = await readdir(directory, { withFileTypes: true });
  if (files.length > 1000)
    throw new Error("笔记目录超过 1000 项，请使用专用子目录");
  const found = new Map<string, string[]>();
  for (const file of files.sort((a, b) => a.name.localeCompare(b.name))) {
    // Follow candidate symlinks only through the caller's evidence-root checks.
    if (!(file.isFile() || file.isSymbolicLink()) || !/\.md$/i.test(file.name))
      continue;
    const lines = markdownLines(await read(join(directory, file.name)));
    const sources = lines.filter((l) => /^paper:\s*/i.test(l));
    if (sources.length !== 1) continue;
    let key: string;
    try {
      key = paperKey(sources[0].replace(/^paper:\s*/i, "").trim());
    } catch {
      continue;
    }
    if (!wanted.includes(key)) continue;
    // Each agreed heading needs a nonempty substantive body, not another heading.
    const valid = ["问题", "方法", "我的理解"].every((heading) => {
      const starts = lines.flatMap((l, i) =>
        l.trim() === `## ${heading}` ? [i] : [],
      );
      if (starts.length !== 1) return false;
      const body: string[] = [];
      for (
        let i = starts[0] + 1;
        i < lines.length && !/^#{1,6}\s/.test(lines[i]);
        i++
      )
        body.push(lines[i]);
      return body.join("").replace(/\s/g, "").length >= 30;
    });
    if (valid) found.set(key, [...(found.get(key) || []), file.name]);
  }
  const missing = wanted.filter((key) => !found.has(key));
  if (missing.length)
    return {
      outcome: "pending",
      reason: `笔记结构达标 ${wanted.length - missing.length}/${wanted.length} 篇；每篇需问题、方法、我的理解各至少 30 个非空白字符`,
      evidence: `缺少：${missing.join("、")}`,
    };
  return {
    outcome: autoComplete ? "pass" : "review",
    reason: autoComplete
      ? "指定论文的笔记结构均达标（按笔记产物验收）"
      : "笔记结构均达标；阅读完成与内容质量由你确认",
    evidence: wanted
      .map((key) => `${key}: ${found.get(key)!.join(", ")}`)
      .join("\n"),
  };
}

export function checkEmailDraft(
  text: string,
  recipient: string,
  autoComplete: boolean,
): ArtifactResult {
  const parts = /\r?\n\r?\n/.exec(text);
  if (!parts)
    return {
      outcome: "pending",
      reason: "请保存为含 To、Subject 和空行后正文的 UTF-8 纯文本 .eml 草稿",
      evidence: "",
    };
  const headerLines = text
    .slice(0, parts.index)
    .replace(/\r?\n[ \t]+/g, " ")
    .split(/\r?\n/);
  const headers = (name: string) =>
    headerLines
      .filter((line) => line.toLowerCase().startsWith(`${name}:`))
      .map((line) => line.slice(name.length + 1).trim());
  const to = headers("to"),
    subjects = headers("subject");
  const address =
    to.length === 1 ? /^[^<>]*<([^<>]+)>$/.exec(to[0])?.[1] || to[0] : "";
  if (
    address.toLowerCase() !== recipient.toLowerCase() ||
    headers("cc").some(Boolean) ||
    headers("bcc").some(Boolean)
  )
    return {
      outcome: "pending",
      reason: "草稿需仅包含约定收件人，且无其他抄送/密送",
      evidence: "",
    };
  if (subjects.length !== 1 || !subjects[0])
    return {
      outcome: "pending",
      reason: "草稿缺少唯一的非空 Subject",
      evidence: "",
    };
  const types = headers("content-type"),
    encodings = headers("content-transfer-encoding");
  if (
    types.length > 1 ||
    (types.length && !/^text\/plain(?:\s*;|$)/i.test(types[0])) ||
    encodings.length > 1 ||
    (encodings.length && !/^(7bit|8bit)$/i.test(encodings[0]))
  )
    return {
      outcome: "review",
      reason: "目前仅检查未编码的纯文本草稿；HTML、附件及编码正文请手动确认",
      evidence: "",
    };
  const body = text.slice(parts.index + parts[0].length);
  if (body.replace(/\s/g, "").length < 100)
    return {
      outcome: "pending",
      reason: "草稿正文不足 100 个非空白字符",
      evidence: "",
    };
  return {
    outcome: autoComplete ? "pass" : "review",
    reason: autoComplete
      ? "收件人、主题与正文结构达标（仅验收草稿，未发送）"
      : "草稿结构达标；申请内容与附件请你确认，未发送",
    evidence: `To: ${to[0]}\nSubject: ${subjects[0]}`,
  };
}
