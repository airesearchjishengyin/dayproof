import AppKit
import SwiftUI

struct TaskEditor: View {
    @ObservedObject var model: DayproofModel
    let task: DayTask?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TaskDraft
    @State private var deadline: Date
    @State private var hasDeadline: Bool
    @State private var value = "true"
    @State private var items = ""
    @State private var papers = ""
    @State private var saving = false
    @State private var error = ""
    @State private var deleting = false
    init(model: DayproofModel, task: DayTask?) {
        self.model = model; self.task = task
        let d = task?.draft ?? TaskDraft(title: "", day: dayString(model.selectedDay, timezone: model.state?.timezone ?? "Asia/Shanghai"))
        var initial = d
        if initial.rule.type == "llm" { initial.rule = TaskRule() }
        _draft = State(initialValue: initial)
        _items = State(initialValue: d.rule.items?.joined(separator: "\n") ?? "")
        _papers = State(initialValue: d.rule.papers?.joined(separator: "\n") ?? "")
        _deadline = State(initialValue: d.deadline.flatMap(isoDate) ?? model.selectedDay)
        _hasDeadline = State(initialValue: d.deadline != nil)
        _value = State(initialValue: d.rule.value?.json ?? "true")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(task == nil ? "写下一件事" : "编辑任务").font(.title2.bold())
            ScrollView {
                Form {
                    TextField("任务", text: $draft.title)
                    TextField("计划日期 YYYY-MM-DD", text: $draft.day)
                    Toggle("设置截止时间", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("截止时间", selection: $deadline).environment(\.timeZone, TimeZone(identifier: model.state?.timezone ?? "Asia/Shanghai")!) }
                    Picker("优先级", selection: $draft.priority) { Text("优先处理").tag("high"); Text("普通").tag("normal"); Text("慢慢来").tag("low") }
                    Stepper("预计 \(draft.estimate) 分钟", value: $draft.estimate, in: 5...1440, step: 5)
                    TextField("来源", text: $draft.source)
                    Text("什么结果，才算完成？").font(.headline)
                    TextEditor(text: $draft.criteria).frame(height: 75).border(Color.gray.opacity(0.2))
                    Picker("验收方式", selection: $draft.rule.type) {
                        ForEach(["manual", "file_exists", "file_contains", "json_equals", "markdown_checklist", "reading_notes", "email_draft"], id: \.self) { Text(ruleName($0)).tag($0) }
                    }
                    if draft.rule.type != "manual" {
                        TextField("证据文件（相对路径）", text: Binding(get: { draft.rule.path ?? "" }, set: { draft.rule.path = $0 }))
                        Text("证据目录：\(model.state?.evidenceRoot ?? "")").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Stepper("每 \(draft.intervalMinutes) 分钟检查", value: $draft.intervalMinutes, in: 1...1440)
                    }
                    if draft.rule.type == "file_contains" { TextField("需要包含的文字", text: Binding(get: { draft.rule.text ?? "" }, set: { draft.rule.text = $0 })) }
                    if draft.rule.type == "json_equals" {
                        TextField("JSON 字段（如 subscription.active）", text: Binding(get: { draft.rule.key ?? "" }, set: { draft.rule.key = $0 }))
                        TextField("期望值（JSON，如 true 或 \"active\"）", text: $value)
                    }
                    if draft.rule.type == "markdown_checklist" {
                        Text("需要勾选的条目（每行一项，与 Markdown 原文精确匹配）").font(.caption)
                        TextEditor(text: $items).frame(height: 90).border(Color.gray.opacity(0.2))
                        Text("读取 - [x] 条目。按进度声明验收，不执行测试或判断内容。").font(.caption).foregroundStyle(.secondary)
                    }
                    if draft.rule.type == "reading_notes" {
                        Text("上方路径填笔记目录；下方填写指定论文链接，每行一篇").font(.caption)
                        TextEditor(text: $papers).frame(height: 90).border(Color.gray.opacity(0.2))
                        Text("只检查目录直接包含的 .md。每篇需 paper: 链接，以及 ## 问题、## 方法、## 我的理解三节各至少 30 个非空白字符。不判断论文新旧或理解质量。").font(.caption).foregroundStyle(.secondary)
                    }
                    if draft.rule.type == "email_draft" {
                        TextField("约定收件人邮箱", text: Binding(get: { draft.rule.recipient ?? "" }, set: { draft.rule.recipient = $0 }))
                        Text("UTF-8 纯文本 .eml，含 To、Subject、空行后正文至少 100 个非空白字符。不检查附件，不发送。").font(.caption).foregroundStyle(.secondary)
                    }
                    if draft.rule.type == "reading_notes" || draft.rule.type == "email_draft" {
                        Toggle("接受产物结构达标后自动打勾", isOn: Binding(get: { draft.rule.autoComplete ?? false }, set: { draft.rule.autoComplete = $0 }))
                        Text("默认由你最终确认。勾选表示以所示结构条件作为完成依据；全过程不调用模型。").font(.caption).foregroundStyle(.secondary)
                    }
                    if task != nil { Text("保存修改后会重新验收此任务。").font(.caption).foregroundStyle(.secondary) }
                }.textFieldStyle(.roundedBorder).padding(3)
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled) }
            HStack {
                if task != nil { Button("删除", role: .destructive) { deleting = true }.confirmationDialog("删除这个任务？", isPresented: $deleting) { Button("删除任务", role: .destructive) { remove() } } }
                Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(saving ? "保存中…" : "保存任务") { save() }.buttonStyle(.borderedProminent).tint(sage).disabled(saving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 600, height: 650).background(paper)
    }
    private func save() {
        saving = true; error = ""
        Task {
            defer { saving = false }
            do {
                var d = draft
                d.deadline = hasDeadline ? ISO8601DateFormatter().string(from: deadline) : nil
                var r = TaskRule(type: d.rule.type)
                if r.type != "manual" { r.path = d.rule.path ?? "" }
                if r.type == "file_contains" { r.text = d.rule.text ?? "" }
                if r.type == "json_equals" { r.key = d.rule.key ?? ""; r.value = try JSONDecoder().decode(Primitive.self, from: Data(value.utf8)) }
                if r.type == "markdown_checklist" { r.items = items.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                if r.type == "reading_notes" { r.papers = papers.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                if r.type == "email_draft" { r.recipient = d.rule.recipient ?? "" }
                if r.type == "reading_notes" || r.type == "email_draft" { r.autoComplete = d.rule.autoComplete ?? false }
                d.rule = r
                try await model.save(d, replacing: task?.id); dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
    private func remove() {
        guard let task else { return }; saving = true
        Task { do { try await model.delete(task); dismiss() } catch { self.error = error.localizedDescription; saving = false } }
    }
}

struct PlanComposer: View {
    @ObservedObject var model: DayproofModel
    @Environment(\.dismiss) private var dismiss
    @State private var goal = ""
    @State private var preview = ""
    @State private var busy = false
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("给今天一个方向").font(.title2.bold())
            Text("\(dayString(model.selectedDay, timezone: model.state?.timezone ?? "Asia/Shanghai")) · 先生成草稿，再确认加入。")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $goal).frame(height: 95).border(Color.gray.opacity(0.2))
            HStack {
                Button("每行一项 → 草稿") { makeDraft() }.disabled(busy || goal.isEmpty)
                Button { generate() } label: { Label(busy ? "正在规划…" : "本地 AI 拆解", systemImage: "sparkles") }.disabled(busy || goal.isEmpty || !model.modelAvailable)
                Spacer(); Text(model.state?.settings.model ?? "").font(.caption).foregroundStyle(.secondary)
            }
            Text("草稿 JSON · 可以直接修改标题、deadline 和验收方式").font(.caption)
            TextEditor(text: $preview).font(.system(size: 11, design: .monospaced)).frame(minHeight: 210).border(Color.gray.opacity(0.2))
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Spacer()
                Button("确认加入计划") { importDraft() }.buttonStyle(.borderedProminent).tint(sage).disabled(busy || preview.isEmpty)
            }
        }.padding(26).frame(width: 650, height: 590).background(paper)
    }
    private func setPreview(_ plan: PlanResult) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        preview = String(data: try encoder.encode(plan), encoding: .utf8)!
    }
    private func makeDraft() {
        do { try setPreview(PlanResult(tasks: goal.split(separator: "\n").prefix(50).map { TaskDraft(title: String($0), day: dayString(model.selectedDay, timezone: model.state?.timezone ?? "Asia/Shanghai")) })); error = "" }
        catch { self.error = error.localizedDescription }
    }
    private func generate() {
        busy = true; error = ""
        Task {
            defer { busy = false }
            do {
                let result: PlanResult = try await model.backend.request("/plan/generate", method: "POST", body: jsonBody(["goal": goal, "day": dayString(model.selectedDay, timezone: model.state?.timezone ?? "Asia/Shanghai")]))
                try setPreview(result)
            } catch { self.error = error.localizedDescription }
        }
    }
    private func importDraft() {
        busy = true; error = ""
        Task {
            defer { busy = false }
            do {
                let plan = try JSONDecoder().decode(PlanResult.self, from: Data(preview.utf8))
                let _: [DayTask] = try await model.backend.request("/plan/import", method: "POST", body: encoded(plan))
                try await model.refresh(); dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
