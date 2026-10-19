import { z } from "zod";
export const Day = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/)
  .refine(
    (v) =>
      !Number.isNaN(Date.parse(v)) &&
      new Date(v).toISOString().slice(0, 10) === v,
    "Invalid calendar date",
  );
export const Rule = z.discriminatedUnion("type", [
  z.object({ type: z.literal("manual") }).strict(),
  z
    .object({
      type: z.literal("file_exists"),
      path: z.string().min(1).max(2048),
    })
    .strict(),
  z
    .object({
      type: z.literal("file_contains"),
      path: z.string().min(1).max(2048),
      text: z.string().min(1).max(2000),
    })
    .strict(),
  z
    .object({
      type: z.literal("json_equals"),
      path: z.string().min(1).max(2048),
      key: z.string().min(1).max(200),
      value: z.union([z.string(), z.number(), z.boolean(), z.null()]),
    })
    .strict(),
  z
    .object({
      type: z.literal("markdown_checklist"),
      path: z.string().min(1).max(2048),
      items: z
        .array(z.string().trim().min(1).max(300))
        .min(1)
        .max(100)
        .refine((v) => new Set(v).size === v.length, "检查项不能重复"),
    })
    .strict(),
  z
    .object({
      type: z.literal("reading_notes"),
      path: z.string().min(1).max(2048),
      papers: z
        .array(
          z
            .string()
            .url()
            .max(2048)
            .refine((v) => /^https?:\/\//i.test(v), "论文链接须为 HTTP(S)"),
        )
        .min(1)
        .max(100),
      autoComplete: z.boolean().default(false),
    })
    .strict(),
  z
    .object({
      type: z.literal("email_draft"),
      path: z.string().min(1).max(2048),
      recipient: z.string().email().max(320),
      autoComplete: z.boolean().default(false),
    })
    .strict(),
  z
    .object({
      type: z.literal("llm"),
      path: z.string().min(1).max(2048),
      autoComplete: z.boolean().default(false),
    })
    .strict(),
]);
export const TaskInput = z
  .object({
    title: z.string().trim().min(1).max(200),
    day: Day,
    deadline: z.string().datetime({ offset: true }).nullable().default(null),
    priority: z.enum(["high", "normal", "low"]).default("normal"),
    source: z.string().trim().min(1).max(80).default("手动"),
    criteria: z.string().trim().max(2000).default(""),
    estimate: z.number().int().min(5).max(1440).default(30),
    intervalMinutes: z.number().int().min(1).max(1440).default(5),
    rule: Rule.default({ type: "manual" }),
  })
  .strict()
  .superRefine((v, c) => {
    if (v.rule.type === "llm" && !v.criteria)
      c.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["criteria"],
        message: "模型判断需要明确的验收标准",
      });
  });
export const SettingsInput = z
  .object({ model: z.string().trim().min(1).max(100) })
  .strict();
export type TaskDraft = z.infer<typeof TaskInput>;
// Legacy model rules remain readable, but task verification never calls a model.
export function canAutoCheck(rule: TaskDraft["rule"]): boolean {
  return rule.type !== "manual" && rule.type !== "llm";
}
export type Verdict = {
  outcome: "pass" | "pending" | "review" | "error";
  reason: string;
  confidence: number | null;
  evidence: string;
  checkedAt: string;
};
export type Task = TaskDraft & {
  id: string;
  status: "todo" | "done";
  createdAt: string;
  completedAt: string | null;
  completionSource: string | null;
  lastCheck: Verdict | null;
  nextCheckAt: string | null;
  revision: number;
};
export function today(): string {
  return new Date().toLocaleDateString("en-CA", {
    timeZone: process.env.TZ || "Asia/Shanghai",
  });
}
