import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  ArrowUpRight,
  Check,
  CheckCheck,
  ChevronLeft,
  ChevronRight,
  Plus,
  LayoutDashboard,
  ListTodo,
  Activity,
  Plug,
  Settings,
  ArrowRight,
  Clock,
  FileCheck2,
  Sparkles,
  X,
  MoreHorizontal,
  RefreshCw,
  Trash2,
  Download,
  Copy,
  Sun,
  CalendarDays,
  AlertCircle,
  CheckCircle2,
  Terminal,
  ExternalLink,
  Pencil,
} from "lucide-react";
import { canAutoCheck, type Task, type TaskDraft } from "../shared/schema";
import "./style.css";
type State = {
  tasks: Task[];
  events: Record<string, unknown>[];
  settings: { model: string };
  today: string;
  timezone: string;
  evidenceRoot: string;
  projectRoot: string;
  dataDir: string;
  mcp: { command: string; args: string[] };
  checking: string[];
};
async function api<T = unknown>(
  path: string,
  method = "GET",
  body?: unknown,
): Promise<T> {
  const r = await fetch("/api" + path, {
    method,
    headers: { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const data = await r.json();
  if (!r.ok) throw new Error(data.error || "请求失败");
  return data as T;
}
const priorities = { high: "优先处理", normal: "普通", low: "低优先" };
const ruleLabels = {
  manual: "手动确认",
  file_exists: "文件存在",
  file_contains: "文本匹配",
  json_equals: "JSON 状态",
  markdown_checklist: "进度清单（纯代码）",
  reading_notes: "论文笔记（纯代码）",
  email_draft: "邮件草稿（纯代码）",
  llm: "模型验收已停用 · 手动确认",
};
const verdictLabels = {
  pass: "验收通过",
  pending: "等待证据",
  review: "待你确认",
  error: "检查出错",
};
function dateLabel(day: string) {
  return new Date(day + "T12:00:00").toLocaleDateString("zh-CN", {
    month: "long",
    day: "numeric",
    weekday: "long",
  });
}
function deadlineLabel(t: Task, tz: string) {
  return t.deadline
    ? new Date(t.deadline).toLocaleString("zh-CN", {
        timeZone: tz,
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
      })
    : "未设截止时间";
}
function localInput(iso: string | null, tz: string) {
  if (!iso) return "";
  const parts = new Intl.DateTimeFormat("sv-SE", {
    timeZone: tz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(new Date(iso));
  return parts.replace(" ", "T");
}
function isoInput(value: string, tz: string): string | null {
  if (!value) return null; // infer offset from configured IANA timezone for the selected day
  const wall = new Date(value + "Z");
  const parts = new Intl.DateTimeFormat("sv-SE", {
    timeZone: tz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  })
    .format(wall)
    .replace(" ", "T");
  const offset = new Date(parts + "Z").getTime() - wall.getTime();
  return new Date(wall.getTime() - offset).toISOString();
}
function App() {
  const [state, setState] = useState<State | null>(null),
    [view, setView] = useState("today"),
    [day, setDay] = useState(""),
    [filter, setFilter] = useState("all"),
    [modal, setModal] = useState<Task | "new" | null>(null),
    [plan, setPlan] = useState(false),
    [toast, setToast] = useState(""),
    [error, setError] = useState(""),
    [busy, setBusy] = useState<string[]>([]);
  const refresh = async () => {
    const s = await api<State>("/state");
    setState(s);
    setDay((d) => d || s.today);
  };
  useEffect(() => {
    let mounted = true;
    api("/session")
      .then(async () => {
        if (mounted) await refresh();
      })
      .catch((e) => setError(e.message));
    const timer = setInterval(() => {
      if (mounted) refresh().catch((e) => setError(e.message));
    }, 8000);
    return () => {
      mounted = false;
      clearInterval(timer);
    };
  }, []);
  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(""), 4500);
    return () => clearTimeout(t);
  }, [toast]);
  const action = async (
    key: string,
    fn: () => Promise<unknown>,
    message?: string,
  ) => {
    setBusy((b) => [...b, key]);
    try {
      await fn();
      await refresh();
      setError("");
      if (message) setToast(message);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy((b) => b.filter((x) => x !== key));
    }
  };
  if (!state)
    return (
      <div className="loading">
        <div className="brand-mark">
          d<span>·</span>
        </div>
        <h2>Dayproof</h2>
        <p>{error || "正在打开你的工作日…"}</p>
        {error && <button onClick={() => location.reload()}>重新加载</button>}
      </div>
    );
  const dayTasks = state.tasks.filter((t) => view === "all" || t.day === day),
    done = dayTasks.filter((t) => t.status === "done").length,
    overdue = state.tasks.filter(
      (t) =>
        t.status !== "done" &&
        ((t.deadline && Date.parse(t.deadline) < Date.now()) ||
          t.day < state.today),
    );
  const tasks = dayTasks
    .filter((t) =>
      filter === "done"
        ? t.status === "done"
        : filter === "todo"
          ? t.status === "todo"
          : filter === "auto"
            ? canAutoCheck(t.rule)
            : true,
    )
    .sort(
      (a, b) =>
        Number(a.status === "done") - Number(b.status === "done") ||
        { high: 0, normal: 1, low: 2 }[a.priority] -
          { high: 0, normal: 1, low: 2 }[b.priority] ||
        (a.deadline || "z").localeCompare(b.deadline || "z"),
    );
  const shift = (n: number) => {
    const d = new Date(day + "T12:00:00");
    d.setDate(d.getDate() + n);
    setDay(
      `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`,
    );
  };
  const pendingCount = dayTasks.length - done,
    minutes = dayTasks
      .filter((t) => t.status === "todo")
      .reduce((a, t) => a + t.estimate, 0),
    automatic = dayTasks.filter((t) => canAutoCheck(t.rule)).length;
  return (
    <div className="app-shell">
      <aside className="sidebar">
        <a className="brand" href="/" aria-label="Dayproof 首页">
          <div className="brand-mark">
            d<span>·</span>
          </div>
          <span>
            dayproof<i>把计划变成已完成</i>
          </span>
        </a>
        <div className="workspace">
          <div className="avatar">我</div>
          <div>
            我的工作空间<small>LOCAL WORKSPACE</small>
          </div>
          <span className="local-dot" />
        </div>
        <div className="nav-label">工作台</div>
        <nav>
          {[
            { id: "today", label: "每日计划", icon: LayoutDashboard },
            { id: "all", label: "全部任务", icon: ListTodo },
            { id: "activity", label: "验收记录", icon: Activity },
          ].map((n) => (
            <button
              key={n.id}
              className={view === n.id ? "active" : ""}
              onClick={() => {
                setView(n.id);
                setFilter("all");
              }}
            >
              <n.icon size={18} />
              {n.label}
              {n.id === "today" && (
                <span className="nav-count">
                  {
                    state.tasks.filter(
                      (t) => t.day === state.today && t.status === "todo",
                    ).length
                  }
                </span>
              )}
            </button>
          ))}
        </nav>
        <div className="nav-label">连接与偏好</div>
        <nav>
          <button
            className={view === "connections" ? "active" : ""}
            onClick={() => setView("connections")}
          >
            <Plug size={18} />
            工具接入
            <ArrowUpRight size={14} className="nav-end" />
          </button>
          <button
            className={view === "settings" ? "active" : ""}
            onClick={() => setView("settings")}
          >
            <Settings size={18} />
            模型与设置
          </button>
        </nav>
        <div className="sidebar-note">
          <div>
            <FileCheck2 size={18} />
            <b>完成，要有依据。</b>
          </div>
          <p>
            先定义验收标准，
            <br />
            再让证据替你打勾。
          </p>
          <span>
            本地存储 · 自主掌控 <ArrowUpRight size={13} />
          </span>
        </div>
        <div className="profile">
          <span className="local-dot" />
          <span>
            本地服务已连接<small>Dayproof / v0.1.0</small>
          </span>
        </div>
      </aside>
      <main className="main">
        <header className="topbar">
          <div>
            <span className="breadcrumb">工作空间</span>
            <ChevronRight size={13} />
            {
              (
                {
                  today: "每日计划",
                  all: "全部任务",
                  activity: "验收记录",
                  connections: "工具接入",
                  settings: "模型与设置",
                } as Record<string, string>
              )[view]
            }
          </div>
          <span className="top-local">
            <span className="local-dot" /> LOCAL FIRST{" "}
            <span className="top-separator">/</span> {state.timezone}
          </span>
        </header>
        <div className="content">
          {error && (
            <div className="error-banner">
              <AlertCircle size={17} />
              <span>{error}</span>
              <button aria-label="关闭错误" onClick={() => setError("")}>
                <X size={16} />
              </button>
            </div>
          )}
          {(view === "today" || view === "all") && (
            <>
              <div className="page-heading">
                <div>
                  <div className="eyebrow">
                    <Sun size={15} />
                    {view === "today"
                      ? "MAKE ROOM FOR WHAT MATTERS"
                      : "EVERYTHING, IN ONE PLACE"}
                  </div>
                  <h1>
                    {view === "today"
                      ? day === state.today
                        ? "今天，专注于重要的事。"
                        : dateLabel(day)
                      : "每一件事，都有着落。"}
                  </h1>
                  <p>定好目标，留出时间。让完成的证据，成为今天的进展。</p>
                </div>
                <button className="primary" onClick={() => setModal("new")}>
                  <Plus size={17} />
                  新建任务
                </button>
              </div>
              <section className="overview">
                <div className="overview-main">
                  <span className="section-kicker">
                    {view === "all" ? "全部进展" : "当日进展"}
                  </span>
                  <div className="progress-count">
                    {done}
                    <span>/ {dayTasks.length}</span>
                    <small>项已完成</small>
                  </div>
                  <div className="progress-track">
                    <span
                      style={{
                        width: `${dayTasks.length ? (done / dayTasks.length) * 100 : 0}%`,
                      }}
                    />
                  </div>
                  <p>
                    {dayTasks.length === 0
                      ? "从一件重要的小事开始。"
                      : done === dayTasks.length
                        ? "今天的计划已全部完成，给自己一点休息。"
                        : `还有 ${pendingCount} 件事，按照自己的节奏来。`}
                  </p>
                </div>
                <div className="overview-stat">
                  <div className="stat-icon">
                    <Clock size={19} />
                  </div>
                  <strong>
                    {minutes < 60 ? minutes : (minutes / 60).toFixed(1)}
                    <small>{minutes < 60 ? "分钟" : "小时"}</small>
                  </strong>
                  <span>预计剩余投入</span>
                </div>
                <div className="overview-stat">
                  <div className="stat-icon">
                    <FileCheck2 size={19} />
                  </div>
                  <strong>
                    {automatic}
                    <small>项任务</small>
                  </strong>
                  <span>已设置自动验收</span>
                </div>
                <div className="overview-prompt">
                  <span className="sparkle-block">
                    <Sparkles size={20} />
                  </span>
                  <b>让想法，变成可执行的计划。</b>
                  <p>写下今天的目标，拆成清晰的小步骤。</p>
                  <button onClick={() => setPlan(true)}>
                    开始规划 <ArrowRight size={15} />
                  </button>
                </div>
              </section>
              <div className="task-toolbar">
                <div className="date-selector">
                  <button aria-label="前一天" onClick={() => shift(-1)}>
                    <ChevronLeft size={17} />
                  </button>
                  <CalendarDays size={17} />
                  <input
                    aria-label="选择计划日期"
                    type="date"
                    value={day}
                    onChange={(e) => e.target.value && setDay(e.target.value)}
                  />
                  <button aria-label="后一天" onClick={() => shift(1)}>
                    <ChevronRight size={17} />
                  </button>
                  {day !== state.today && (
                    <button
                      className="today-link"
                      onClick={() => setDay(state.today)}
                    >
                      今天
                    </button>
                  )}
                </div>
                <button
                  className="text-button"
                  disabled={busy.includes("checkall")}
                  onClick={() =>
                    action(
                      "checkall",
                      () => api("/check", "POST", { day }),
                      "检查已完成",
                    )
                  }
                >
                  <RefreshCw
                    size={14}
                    className={busy.includes("checkall") ? "spinning" : ""}
                  />
                  检查{view === "all" ? "所选日期" : "当天"}任务
                </button>
              </div>
              <div className="tabs">
                {[
                  { id: "all", label: "全部任务", n: dayTasks.length },
                  { id: "todo", label: "待完成", n: pendingCount },
                  { id: "done", label: "已完成", n: done },
                  { id: "auto", label: "自动验收", n: automatic },
                ].map((t) => (
                  <button
                    key={t.id}
                    className={filter === t.id ? "selected" : ""}
                    onClick={() => setFilter(t.id)}
                  >
                    {t.label}
                    <span>{t.n}</span>
                  </button>
                ))}
                <span className="sort-label">按优先级与截止时间排序</span>
              </div>
              <div className="task-list">
                {tasks.length === 0 ? (
                  <div className="empty-state">
                    <div className="empty-icon">
                      <CheckCheck size={32} />
                    </div>
                    <h3>
                      {dayTasks.length
                        ? "这里暂时没有任务"
                        : "给今天一个清晰的开始"}
                    </h3>
                    <p>
                      {dayTasks.length
                        ? "换个筛选条件，看看其他任务。"
                        : "写下要做的事、截止时间，以及怎样才算完成。"}
                    </p>
                    <button className="primary" onClick={() => setModal("new")}>
                      <Plus size={16} />
                      添加第一个任务
                    </button>
                    <button
                      className="text-button"
                      onClick={() => setPlan(true)}
                    >
                      或者，批量规划今天 <ArrowRight size={14} />
                    </button>
                  </div>
                ) : (
                  tasks.map((t) => (
                    <article
                      key={t.id}
                      className={`task-card ${t.status === "done" ? "completed" : ""}`}
                    >
                      <button
                        className="task-checkbox"
                        title={
                          t.status === "done" ? "重新打开" : "手动确认完成"
                        }
                        aria-label={`${t.status === "done" ? "重新打开" : "完成"} ${t.title}`}
                        onClick={() =>
                          action(t.id, () =>
                            api(`/tasks/${t.id}/status`, "PATCH", {
                              done: t.status !== "done",
                            }),
                          )
                        }
                      >
                        {t.status === "done" && <Check size={15} />}
                      </button>
                      <div className="task-body">
                        <div className="task-title-line">
                          <button
                            onClick={() => setModal(t)}
                            className="task-title"
                          >
                            {t.title}
                          </button>
                          <span className={`priority ${t.priority}`}>
                            <span />
                            {priorities[t.priority]}
                          </span>
                        </div>
                        {t.criteria && (
                          <p className="task-criteria">{t.criteria}</p>
                        )}
                        <div className="task-meta">
                          <span
                            className={
                              t.status !== "done" &&
                              t.deadline &&
                              Date.parse(t.deadline) < Date.now()
                                ? "late"
                                : ""
                            }
                          >
                            <Clock size={13} />
                            {deadlineLabel(t, state.timezone)}
                          </span>
                          <span>{t.estimate} 分钟</span>
                          <span className="source-chip">{t.source}</span>
                          <span className="rule-chip">
                            <FileCheck2 size={12} />
                            {ruleLabels[t.rule.type]}
                          </span>
                          {view === "all" && <span>{t.day}</span>}
                        </div>
                        {t.lastCheck && (
                          <div className={`verdict ${t.lastCheck.outcome}`}>
                            <span className="verdict-dot" />
                            <b>{verdictLabels[t.lastCheck.outcome]}</b>
                            <span>{t.lastCheck.reason}</span>
                            <small>
                              {new Date(
                                t.lastCheck.checkedAt,
                              ).toLocaleTimeString("zh-CN", {
                                timeZone: state.timezone,
                                hour: "2-digit",
                                minute: "2-digit",
                              })}
                            </small>
                          </div>
                        )}
                        {t.status === "done" && (
                          <div className="completion-note">
                            <CheckCircle2 size={12} />
                            {t.completionSource}
                          </div>
                        )}
                      </div>
                      <div className="task-actions">
                        {canAutoCheck(t.rule) && t.status !== "done" && (
                          <button
                            title="立即检查证据"
                            aria-label={`检查 ${t.title}`}
                            disabled={
                              busy.includes(t.id) ||
                              state.checking.includes(t.id)
                            }
                            onClick={() =>
                              action(t.id, () =>
                                api(`/tasks/${t.id}/check`, "POST", {}),
                              )
                            }
                          >
                            <RefreshCw
                              size={16}
                              className={
                                busy.includes(t.id) ||
                                state.checking.includes(t.id)
                                  ? "spinning"
                                  : ""
                              }
                            />
                          </button>
                        )}
                        <button
                          title="编辑任务"
                          aria-label={`编辑 ${t.title}`}
                          onClick={() => setModal(t)}
                        >
                          <Pencil size={15} />
                        </button>
                      </div>
                    </article>
                  ))
                )}
              </div>
              {overdue.length > 0 && view === "today" && (
                <div className="carry-note">
                  <AlertCircle size={15} />
                  {overdue.length} 项未完成任务已逾期或来自之前的日期。
                  <button
                    onClick={() => {
                      setView("all");
                      setFilter("todo");
                    }}
                  >
                    查看并重新安排 <ArrowRight size={13} />
                  </button>
                </div>
              )}
              <div className="bottom-note">
                <span>
                  <span className="local-dot" />
                  验收服务运行中 · 按各任务的检查频率执行
                </span>
                <button
                  className="text-button"
                  onClick={() => setView("connections")}
                >
                  在 AI 工具中直接创建计划 <ArrowUpRight size={13} />
                </button>
              </div>
            </>
          )}
          {view === "activity" && (
            <>
              <PageTitle
                eyebrow="THE EVIDENCE TRAIL"
                title="每一次完成，都可追溯。"
                description="查看自动检查的依据，以及你亲自确认的进展。"
              />
              {state.events.length === 0 ? (
                <div className="empty-state">
                  <Activity size={32} />
                  <h3>第一条验收记录，在路上。</h3>
                  <p>检查任务或手动确认完成后，记录会出现在这里。</p>
                </div>
              ) : (
                <div className="activity-list">
                  {state.events.map((e, i) => (
                    <article key={i}>
                      <div className={`activity-icon ${e.outcome || ""}`}>
                        {e.outcome === "pass" ? (
                          <CheckCircle2 size={19} />
                        ) : (
                          <Activity size={19} />
                        )}
                      </div>
                      <div>
                        <strong>{String(e.title || "任务")}</strong>
                        <p>{String(e.reason || "")}</p>
                        {!!e.evidence && <pre>{String(e.evidence)}</pre>}
                        <span>
                          {e.confidence != null
                            ? `置信度 ${Math.round(Number(e.confidence) * 100)}% · `
                            : ""}
                          {String(
                            e.source ||
                              (
                                {
                                  pass: "自动验收",
                                  pending: "等待证据",
                                  review: "需要确认",
                                  error: "检查失败",
                                } as Record<string, string>
                              )[String(e.outcome)] ||
                              "",
                          )}
                        </span>
                      </div>
                      <time>
                        {new Date(String(e.at)).toLocaleString("zh-CN", {
                          timeZone: state.timezone,
                        })}
                      </time>
                    </article>
                  ))}
                </div>
              )}
            </>
          )}
          {view === "connections" && (
            <Connections
              root={state.projectRoot}
              dataDir={state.dataDir}
              mcp={state.mcp}
              notify={setToast}
            />
          )}
          {view === "settings" && (
            <SettingsView state={state} action={action} busy={busy} />
          )}
          <footer>
            <span>
              dayproof <span className="footer-dot">·</span>{" "}
              少一点悬而未决，多一点踏实。
            </span>
            <span>YOUR DAY. YOUR PROOF.</span>
          </footer>
        </div>
      </main>
      {toast && (
        <div role="status" className="toast">
          <CheckCircle2 size={17} />
          {toast}
        </div>
      )}
      {modal && (
        <TaskModal
          task={modal}
          day={day}
          state={state}
          close={() => setModal(null)}
          save={async (d) => {
            await api(
              modal === "new" ? "/tasks" : `/tasks/${modal.id}`,
              modal === "new" ? "POST" : "PUT",
              d,
            );
            await refresh();
            setModal(null);
            setToast(
              "new" === modal ? "任务已加入计划" : "任务已更新，将重新验收",
            );
          }}
          remove={
            modal === "new"
              ? undefined
              : async () => {
                  await api(`/tasks/${modal.id}`, "DELETE");
                  await refresh();
                  setModal(null);
                }
          }
        />
      )}
      {plan && (
        <PlanModal
          day={day}
          close={() => setPlan(false)}
          imported={async () => {
            await refresh();
            setPlan(false);
            setToast("计划已加入任务列表");
          }}
        />
      )}
    </div>
  );
}
function PageTitle(p: { eyebrow: string; title: string; description: string }) {
  return (
    <div className="page-heading">
      <div>
        <div className="eyebrow">{p.eyebrow}</div>
        <h1>{p.title}</h1>
        <p>{p.description}</p>
      </div>
    </div>
  );
}
function Dialog({
  children,
  close,
  wide = false,
}: {
  children: React.ReactNode;
  close: () => void;
  wide?: boolean;
}) {
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape") close();
    };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, [close]);
  return (
    <div
      className="modal-backdrop"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) close();
      }}
    >
      <section
        role="dialog"
        aria-modal="true"
        className={`modal ${wide ? "wide" : ""}`}
      >
        <button className="close-modal" aria-label="关闭窗口" onClick={close}>
          <X size={20} />
        </button>
        {children}
      </section>
    </div>
  );
}
function TaskModal({
  task,
  day,
  state,
  close,
  save,
  remove,
}: {
  task: Task | "new";
  day: string;
  state: State;
  close: () => void;
  save: (d: TaskDraft) => Promise<void>;
  remove?: () => Promise<void>;
}) {
  const d = task === "new" ? null : task;
  const [title, setTitle] = useState(d?.title || ""),
    [taskDay, setTaskDay] = useState(d?.day || day),
    [deadline, setDeadline] = useState(
      localInput(d?.deadline || null, state.timezone),
    ),
    [priority, setPriority] = useState(d?.priority || "normal"),
    [criteria, setCriteria] = useState(d?.criteria || ""),
    [estimate, setEstimate] = useState(d?.estimate || 30),
    [source, setSource] = useState(d?.source || "手动"),
    [kind, setKind] = useState<Task["rule"]["type"]>(
      d?.rule.type === "llm" ? "manual" : d?.rule.type || "manual",
    ),
    [path, setPath] = useState(
      d?.rule.type !== "manual" && d?.rule ? d.rule.path : "",
    ),
    [text, setText] = useState(
      d?.rule.type === "file_contains" ? d.rule.text : "",
    ),
    [key, setKey] = useState(
      d?.rule.type === "json_equals" ? d.rule.key : "subscription.active",
    ),
    [value, setValue] = useState(
      d?.rule.type === "json_equals" ? JSON.stringify(d.rule.value) : "true",
    ),
    [interval, setInterval] = useState(d?.intervalMinutes || 5),
    [auto, setAuto] = useState(
      d?.rule.type === "reading_notes" || d?.rule.type === "email_draft"
        ? d.rule.autoComplete
        : false,
    ),
    [items, setItems] = useState(
      d?.rule.type === "markdown_checklist" ? d.rule.items.join("\n") : "",
    ),
    [papers, setPapers] = useState(
      d?.rule.type === "reading_notes" ? d.rule.papers.join("\n") : "",
    ),
    [recipient, setRecipient] = useState(
      d?.rule.type === "email_draft" ? d.rule.recipient : "",
    ),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [confirmDelete, setConfirmDelete] = useState(false);
  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      let rule: TaskDraft["rule"] = { type: "manual" };
      if (kind === "file_exists") rule = { type: kind, path };
      if (kind === "file_contains") rule = { type: kind, path, text };
      if (kind === "json_equals") {
        const parsed = JSON.parse(value);
        if (
          parsed !== null &&
          !["boolean", "number", "string"].includes(typeof parsed)
        )
          throw new Error("预期值应为 JSON 字符串、数字、布尔值或 null");
        rule = { type: kind, path, key, value: parsed };
      }
      if (kind === "markdown_checklist")
        rule = {
          type: kind,
          path,
          items: items
            .split(/\r?\n/)
            .map((v) => v.trim())
            .filter(Boolean),
        };
      if (kind === "reading_notes")
        rule = {
          type: kind,
          path,
          papers: papers
            .split(/\r?\n/)
            .map((v) => v.trim())
            .filter(Boolean),
          autoComplete: auto,
        };
      if (kind === "email_draft")
        rule = { type: kind, path, recipient, autoComplete: auto };
      await save({
        title,
        day: taskDay,
        deadline: isoInput(deadline, state.timezone),
        priority,
        criteria,
        estimate,
        source,
        intervalMinutes: interval,
        rule,
      });
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <Dialog close={close}>
      <div className="eyebrow">A SMALL STEP, CLEARLY DEFINED</div>
      <h2>{d ? "编辑任务" : "接下来，完成什么？"}</h2>
      <p className="modal-subtitle">
        一个清楚的目标，配上一个可核对的完成标准。
      </p>
      <form onSubmit={submit}>
        <label>
          任务名称
          <input
            autoFocus
            required
            maxLength={200}
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="例如：完成 Claude Code 订阅"
          />
        </label>
        <div className="form-row">
          <label>
            计划日期
            <input
              type="date"
              required
              value={taskDay}
              onChange={(e) => setTaskDay(e.target.value)}
            />
          </label>
          <label>
            截止时间 <small>{state.timezone}</small>
            <input
              type="datetime-local"
              value={deadline}
              onChange={(e) => setDeadline(e.target.value)}
            />
          </label>
        </div>
        <div className="form-row thirds">
          <label>
            优先级
            <select
              value={priority}
              onChange={(e) => setPriority(e.target.value as Task["priority"])}
            >
              <option value="high">优先处理</option>
              <option value="normal">普通</option>
              <option value="low">低优先</option>
            </select>
          </label>
          <label>
            预计用时 / 分钟
            <input
              type="number"
              min={5}
              max={1440}
              required
              value={estimate}
              onChange={(e) => setEstimate(Number(e.target.value))}
            />
          </label>
          <label>
            任务来源
            <input
              required
              maxLength={80}
              value={source}
              onChange={(e) => setSource(e.target.value)}
            />
          </label>
        </div>
        <label>
          怎样才算完成？
          <textarea
            rows={2}
            maxLength={2000}
            value={criteria}
            onChange={(e) => setCriteria(e.target.value)}
            placeholder="例如：订阅状态为 active，且有可核对的付款或账号凭证"
          />
        </label>
        <div className="form-divider" />
        <label>
          完成验收方式
          <select
            value={kind}
            onChange={(e) => setKind(e.target.value as Task["rule"]["type"])}
          >
            {Object.entries(ruleLabels)
              .filter(([k]) => k !== "llm")
              .map(([k, v]) => (
                <option key={k} value={k}>
                  {v}
                </option>
              ))}
          </select>
        </label>
        {kind === "manual" ? (
          <p className="field-help">
            完成后由你点击勾选，适用于暂时没有可读取证据的任务。
          </p>
        ) : (
          <>
            <label>
              {kind === "reading_notes" ? "笔记目录路径" : "证据文件路径"}
              <input
                required
                value={path}
                onChange={(e) => setPath(e.target.value)}
                placeholder="例如 evidence/subscription.json"
              />
            </label>
            <p className="field-help">
              相对于证据目录：<code>{state.evidenceRoot}</code>
              。只读取该目录内的文件。现有文件也会作为证据；请为每次任务使用独立路径。
            </p>
            {kind === "file_contains" && (
              <label>
                必须包含的原文
                <input
                  required
                  value={text}
                  onChange={(e) => setText(e.target.value)}
                  placeholder="subscription confirmed"
                />
              </label>
            )}
            {kind === "json_equals" && (
              <div className="form-row">
                <label>
                  JSON 字段路径
                  <input
                    required
                    value={key}
                    onChange={(e) => setKey(e.target.value)}
                    placeholder="subscription.active"
                  />
                </label>
                <label>
                  预期值（JSON 格式）
                  <input
                    required
                    value={value}
                    onChange={(e) => setValue(e.target.value)}
                    placeholder='true 或 "active"'
                  />
                </label>
              </div>
            )}
            <label>
              每隔多少分钟检查？
              <input
                type="number"
                min={1}
                max={1440}
                required
                value={interval}
                onChange={(e) => setInterval(Number(e.target.value))}
              />
            </label>
            {kind === "markdown_checklist" && (
              <label>
                需要勾选的条目（每行一个，与 Markdown 原文精确匹配）
                <textarea
                  required
                  rows={4}
                  value={items}
                  onChange={(e) => setItems(e.target.value)}
                  placeholder="完成第 1 课作业"
                />
                <small>
                  读取 - [x] 条目。按进度声明验收，不执行测试或判断内容。
                </small>
              </label>
            )}
            {kind === "reading_notes" && (
              <label>
                指定论文链接（每行一篇，去重）
                <textarea
                  required
                  rows={4}
                  value={papers}
                  onChange={(e) => setPapers(e.target.value)}
                  placeholder="https://arxiv.org/abs/…"
                />
                <small>
                  只检查目录直接包含的 .md。每篇需 paper: 链接，以及“## 问题”“##
                  方法”“## 我的理解”各至少 30
                  个非空白字符。论文是否最新、是否读懂由你确认。
                </small>
              </label>
            )}
            {kind === "email_draft" && (
              <label>
                约定收件人邮箱
                <input
                  required
                  type="email"
                  value={recipient}
                  onChange={(e) => setRecipient(e.target.value)}
                />
                <small>
                  UTF-8 纯文本 .eml，需 To、Subject、空行后正文至少 100
                  个非空白字符。不检查附件，不发送邮件。
                </small>
              </label>
            )}
            {(kind === "reading_notes" || kind === "email_draft") && (
              <label className="check-label">
                <input
                  type="checkbox"
                  checked={auto}
                  onChange={(e) => setAuto(e.target.checked)}
                />
                我接受上述产物结构作为完成依据，达标后自动打勾；未勾选时由我最终确认。全过程不调用模型。
              </label>
            )}
          </>
        )}
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
        <div className="modal-footer">
          {remove && (
            <button
              type="button"
              className="danger text-button"
              disabled={busy}
              onClick={async () => {
                if (!confirmDelete) {
                  setConfirmDelete(true);
                  return;
                }
                setBusy(true);
                try {
                  await remove();
                } catch (e) {
                  setError((e as Error).message);
                  setBusy(false);
                }
              }}
            >
              <Trash2 size={15} />
              {confirmDelete ? "再次点击删除" : "删除任务"}
            </button>
          )}
          <button type="button" onClick={close}>
            取消
          </button>
          <button className="primary" disabled={busy} type="submit">
            {busy ? "保存中…" : d ? "保存修改" : "加入计划"}
            <ArrowRight size={15} />
          </button>
        </div>
      </form>
    </Dialog>
  );
}
function PlanModal({
  day,
  close,
  imported,
}: {
  day: string;
  close: () => void;
  imported: () => Promise<void>;
}) {
  const [goal, setGoal] = useState(""),
    [draft, setDraft] = useState(""),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const localDraft = () => {
    const lines = goal
      .split("\n")
      .map((s) => s.replace(/^\s*(?:[-*]|\d+[.、])\s*/, "").trim())
      .filter(Boolean);
    if (!lines.length) {
      setError("先写下至少一个目标");
      return;
    }
    setDraft(
      JSON.stringify(
        {
          tasks: lines.map((title) => ({
            title,
            day,
            criteria: "",
            estimate: 30,
            priority: "normal",
            source: "批量规划",
            rule: { type: "manual" },
          })),
        },
        null,
        2,
      ),
    );
    setError("");
  };
  const generate = async () => {
    setBusy(true);
    setError("");
    try {
      setDraft(
        JSON.stringify(
          await api("/plan/generate", "POST", { goal, day }),
          null,
          2,
        ),
      );
    } catch (e) {
      setError(
        (e as Error).message +
          "。也可以使用“一行一任务”，或在已接入的 AI 工具中生成计划。",
      );
    } finally {
      setBusy(false);
    }
  };
  return (
    <Dialog close={close} wide>
      <div className="eyebrow">TURN INTENTIONS INTO ACTION</div>
      <h2>给这一天，安排得刚刚好。</h2>
      <p className="modal-subtitle">
        {dateLabel(day)} · 先生成草稿，确认后再加入计划。
      </p>
      <label>
        今天想完成什么？
        <textarea
          autoFocus
          rows={4}
          value={goal}
          maxLength={4000}
          onChange={(e) => setGoal(e.target.value)}
          placeholder={"完成 Claude Code 订阅\n整理项目需求\n预留半小时复盘"}
        />
      </label>
      <div className="plan-buttons">
        <button onClick={localDraft}>
          <ListTodo size={15} />
          一行一任务
        </button>
        <button
          className="primary"
          disabled={busy || !goal.trim()}
          onClick={generate}
        >
          <Sparkles size={15} />
          {busy ? "本地模型规划中…" : "Ollama 帮我拆解"}
        </button>
      </div>
      <p className="field-help">
        模型功能需要本机运行 Ollama 并安装模型；一行一任务无需模型或 API。
      </p>
      <label>
        计划草稿 / JSON <small>可直接粘贴 Codex、Claude 生成的计划</small>
        <textarea
          className="code-textarea"
          rows={10}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder={
            '{"tasks":[{"title":"任务名称","day":"' +
            day +
            '","criteria":"验收标准"}]}'
          }
        />
      </label>
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      <div className="modal-footer">
        <button onClick={close}>取消</button>
        <button
          className="primary"
          disabled={busy || !draft.trim()}
          onClick={async () => {
            setBusy(true);
            setError("");
            try {
              const body = JSON.parse(draft);
              await api("/plan/import", "POST", body);
              await imported();
            } catch (e) {
              setError((e as Error).message);
            } finally {
              setBusy(false);
            }
          }}
        >
          确认并加入计划 <ArrowRight size={15} />
        </button>
      </div>
    </Dialog>
  );
}
function Connections({
  root,
  dataDir,
  mcp,
  notify,
}: {
  root: string;
  dataDir: string;
  mcp: { command: string; args: string[] };
  notify: (s: string) => void;
}) {
  const quote = (value: string) => "'" + value.replaceAll("'", "'\\''") + "'";
  const serverUrl = window.location.origin;
  const commandArgs = `--env ${quote("DATA_DIR=" + dataDir)} --env ${quote("DAYPROOF_URL=" + serverUrl)} -- ${quote(mcp.command)} ${mcp.args.map(quote).join(" ")}`;
  const commands = [
    {
      name: "Codex",
      sub: "STDIO · 官方 MCP 配置方式",
      code: `codex mcp add dayproof ${commandArgs}`,
    },
    {
      name: "Claude Code",
      sub: "STDIO · MCP 命令行接入",
      code: `claude mcp add --transport stdio dayproof ${commandArgs}`,
    },
    {
      name: "WorkBuddy / DeepSeek harness",
      sub: "取决于具体客户端是否支持 MCP；也可通过 REST API",
      code: JSON.stringify(
        {
          mcpServers: {
            dayproof: {
              command: mcp.command,
              args: mcp.args,
              env: { DATA_DIR: dataDir, DAYPROOF_URL: serverUrl },
            },
          },
        },
        null,
        2,
      ),
    },
  ];
  return (
    <>
      <PageTitle
        eyebrow="ONE PLAN. MANY COPILOTS."
        title="你常用的 AI，共用一份计划。"
        description="通过 MCP 让工具直接创建计划、读取进展、触发证据验收。首次配置后，在对应工具中启用。"
      />
      <div className="info-card">
        <Plug size={21} />
        <div>
          <b>接口已就绪，等待客户端配置</b>
          <p>
            本页面显示接入方法，不代表这些应用已经连接。配置已包含当前服务地址和数据目录；请保持本地服务运行。
          </p>
        </div>
      </div>
      {commands.map((c, i) => (
        <section className="connection-card" key={c.name}>
          <div className="connection-heading">
            <div className="tool-logo">
              {i === 0 ? <Terminal size={22} /> : i === 1 ? "✳" : "↗"}
            </div>
            <div>
              <h3>{c.name}</h3>
              <p>{c.sub}</p>
            </div>
            <span className="tag">待配置</span>
          </div>
          <pre>{c.code}</pre>
          <button
            onClick={() =>
              navigator.clipboard
                .writeText(c.code)
                .then(() => notify("接入配置已复制"))
                .catch(() => notify("请手动选择并复制配置"))
            }
          >
            <Copy size={14} />
            复制配置
          </button>
        </section>
      ))}
      <section className="prompt-card">
        <Sparkles size={19} />
        <div>
          <h3>接入后，可以这样说</h3>
          <p>
            “请先读取 Dayproof 今天的任务，帮我安排今天的工作，写清 deadline
            和验收标准，避免重复任务。完成后调用检查工具验证证据。”
          </p>
          <small>
            任务来源由客户端提交。自动验收仅证明约定规则通过，不能代替真实账号或付款系统的验证。
          </small>
        </div>
      </section>
    </>
  );
}
function SettingsView({
  state,
  action,
  busy,
}: {
  state: State;
  action: (
    key: string,
    fn: () => Promise<unknown>,
    message?: string,
  ) => Promise<void>;
  busy: string[];
}) {
  const [model, setModel] = useState(state.settings.model),
    [ollamaState, setOllamaState] = useState<{
      available: boolean;
      models: string[];
    } | null>(null);
  useEffect(() => {
    api<{ available: boolean; models: string[] }>("/ollama")
      .then(setOllamaState)
      .catch(() => setOllamaState({ available: false, models: [] }));
  }, []);
  return (
    <>
      <PageTitle
        eyebrow="PRIVATE BY DEFAULT"
        title="自己的节奏，自己的模型。"
        description="验收只用代码；需要理解内容的部分由你确认。本地模型仅用于主动生成计划。"
      />
      <section className="settings-card">
        <div className="settings-section-title">
          <div className="stat-icon">
            <Sparkles size={20} />
          </div>
          <div>
            <h3>Ollama 本地模型</h3>
            <p>用于拆解计划与辅助验收</p>
          </div>
          <span
            className={`status-badge ${ollamaState?.available ? "available" : ""}`}
          >
            {ollamaState === null
              ? "检测中"
              : ollamaState.available
                ? "服务可用"
                : "尚未检测到"}
          </span>
        </div>
        <label>
          模型名称
          <input
            list="models"
            value={model}
            onChange={(e) => setModel(e.target.value)}
            placeholder="qwen3:4b"
          />
          <datalist id="models">
            {ollamaState?.models.map((m) => (
              <option key={m}>{m}</option>
            ))}
          </datalist>
        </label>
        {ollamaState?.available && (
          <p className="field-help">
            已安装：
            {ollamaState.models.join("、") || "尚无模型，请先 ollama pull"}
          </p>
        )}
        <p className="field-help">
          默认地址 http://127.0.0.1:11434；可通过服务端 OLLAMA_URL 配置。使用{" "}
          <code>ollama pull qwen3:4b</code> 安装模型。模型在本机运行，无按次 API
          费用，性能取决于硬件。
        </p>
        <button
          className="primary"
          disabled={busy.includes("model") || !model.trim()}
          onClick={() =>
            action(
              "model",
              () => api("/settings", "POST", { model }),
              "模型设置已保存",
            )
          }
        >
          保存模型设置
        </button>
      </section>
      <section className="settings-card">
        <h3>数据与运行环境</h3>
        <div className="setting-line">
          <span>默认时区</span>
          <b>{state.timezone}</b>
        </div>
        <div className="setting-line">
          <span>证据目录</span>
          <code>{state.evidenceRoot}</code>
        </div>
        <div className="setting-line">
          <span>定时检查</span>
          <span>服务端持续运行；每 10 秒扫描到期任务</span>
        </div>
        <p className="field-help">
          关闭网页后继续检查；本地服务退出或电脑休眠时暂停，下次启动补查。验收不调用模型；旧模型规则已停用，请改用代码规则或手动确认。
        </p>
        <a className="button-link" href="/api/export" download>
          <Download size={16} />
          导出任务与验收记录
        </a>
        <p className="field-help">
          JSON
          导出包含任务状态及近期记录。批量导入只接受计划字段，恢复完整数据库请备份
          data 目录。
        </p>
      </section>
    </>
  );
}
createRoot(document.getElementById("root")!).render(<App />);
