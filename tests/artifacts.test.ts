import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { checkChecklist, checkEmailDraft } from "../src/server/artifacts.ts";
import { decide } from "../src/server/decision.ts";
import { Store } from "../src/server/store.ts";
import { TaskInput } from "../src/shared/schema.ts";

test("checklist matches exact, unique completed items, excluding examples and comments", () => {
  const check = (text: string) =>
    checkChecklist(text, ["第 1 课作业", "登录模块"]);
  assert.equal(check("- [x] 第 1 课作业\n- [X] 登录模块").outcome, "pass");
  for (const text of [
    "- [x] 第 1 课作业\n- [ ] 登录模块",
    "- [x] 第 1 课作业\n- [x] 计划完成登录模块",
    "- [x] 第 1 课作业\n```md\n- [x] 登录模块\n```",
    "- [x] 第 1 课作业\n<!--\n- [x] 登录模块\n-->",
    "- [x] 第 1 课作业\n- [x] 登录模块\n- [ ] 登录模块",
  ])
    assert.notEqual(check(text).outcome, "pass");
});

test("email draft defaults to review; wrong recipient, missing subject, encoded/MIME bodies do not auto-pass", () => {
  const body =
    "这里说明我申请的岗位、相关开发经历和可以提供的项目成果。".repeat(6);
  const text = `To: Hiring <jobs@example.com>\nSubject: 游戏开发岗位申请\n\n${body}`;
  assert.equal(
    checkEmailDraft(text, "jobs@example.com", false).outcome,
    "review",
  );
  assert.equal(checkEmailDraft(text, "jobs@example.com", true).outcome, "pass");
  for (const changed of [
    text.replace("jobs@example.com", "other@example.com"),
    text.replace("Subject: 游戏开发岗位申请", "Subject:"),
    text.replace("Subject:", "Cc: other@example.com\nSubject:"),
    text.replace("Subject:", "Content-Type: multipart/mixed\nSubject:"),
    text.replace("Subject:", "Content-Transfer-Encoding: base64\nSubject:"),
    text.slice(0, text.indexOf("\n\n")) + "\n\nTODO",
  ])
    assert.notEqual(
      checkEmailDraft(changed, "jobs@example.com", true).outcome,
      "pass",
    );
});

test("ten paper notes require ten unique agreed identities and actual sections; symlinks stay inside evidence root; zero network", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dayproof-notes-"));
  const outside = await mkdtemp(join(tmpdir(), "dayproof-notes-outside-"));
  const store = new Store(join(dir, "db.sqlite"));
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => {
    calls++;
    throw new Error("no network");
  };
  try {
    await mkdir(join(dir, "notes"));
    const papers = Array.from(
      { length: 10 },
      (_, i) => `https://arxiv.org/abs/2601.${String(i + 1).padStart(5, "0")}`,
    );
    const note = (url: string) =>
      `paper: ${url}\n\n` +
      ["问题", "方法", "我的理解"]
        .map(
          (h) =>
            `## ${h}\n这是用于测试的结构完整笔记内容。`.repeat(1) +
            "具体内容需要用户自行确认。".repeat(4),
        )
        .join("\n");
    const create = (autoComplete = false, list = papers) =>
      store.add(
        TaskInput.parse({
          title: "阅读论文",
          day: "2026-10-19",
          rule: {
            type: "reading_notes",
            path: "notes",
            papers: list,
            autoComplete,
          },
        }),
      );
    const check = async (auto = false) => decide(create(auto), dir, "unused");
    for (let i = 0; i < 9; i++)
      await writeFile(join(dir, "notes", `${i}.md`), note(papers[i]));
    // Ten files, only nine identities: copying a note cannot satisfy the count.
    await writeFile(join(dir, "notes", "copy.md"), note(papers[0]));
    assert.equal((await check(true)).outcome, "pending");
    await writeFile(
      join(dir, "notes", "9.md"),
      note(papers[9]).replace("## 我的理解", "## 其他"),
    );
    assert.equal((await check(true)).outcome, "pending");
    await writeFile(
      join(dir, "notes", "9.md"),
      note(papers[9].replace("/abs/", "/pdf/") + "v2.pdf"),
    );
    assert.equal((await check()).outcome, "review");
    assert.equal((await check(true)).outcome, "pass");
    const duplicate = create(true, [
      papers[0],
      papers[0].replace("/abs/", "/pdf/") + "v2.pdf",
    ]);
    assert.equal((await decide(duplicate, dir, "unused")).outcome, "error");
    await writeFile(join(outside, "external.md"), note(papers[9]));
    await symlink(
      join(outside, "external.md"),
      join(dir, "notes", "external.md"),
    );
    assert.equal((await check(true)).outcome, "error");
    assert.equal(calls, 0);
  } finally {
    globalThis.fetch = original;
    store.db.close();
    await rm(dir, { recursive: true, force: true });
    await rm(outside, { recursive: true, force: true });
  }
});
