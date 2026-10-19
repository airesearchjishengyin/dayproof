import AppKit
import SwiftUI

struct PlannerView: View {
    @ObservedObject var model: DayproofModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                if !model.error.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.circle")
                        Text(model.error).font(.caption).textSelection(.enabled)
                        Spacer()
                        if !model.ready { Button("重试") { Task { await model.launch() } } }
                        Button { model.error = "" } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }.padding(14).background(Color.orange.opacity(0.10))
                }
                if !model.ready {
                    Spacer(); ProgressView(); Text("正在准备你的工作日…").padding(); Spacer()
                } else {
                    switch model.route {
                    case "pet": CompanionSettings(model: model)
                    case "settings": DesktopSettings(model: model)
                    case "activity": ActivityView(model: model)
                    default: daily
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(paper).foregroundStyle(ink)
        .frame(minWidth: 820, minHeight: 600)
        .sheet(isPresented: $model.showEditor) { TaskEditor(model: model, task: model.editor) }
        .sheet(isPresented: $model.showPlan) { PlanComposer(model: model) }
        .preferredColorScheme(.light)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Image(systemName: "pawprint.fill").font(.system(size: 23)).foregroundStyle(sage)
                Text("Dayproof").font(.system(size: 22, weight: .semibold, design: .rounded))
            }.padding(.bottom, 4)
            Text("留一点空间，好好过今天。")
                .font(.system(size: 10)).foregroundStyle(.secondary).padding(.bottom, 28)
            nav("today", "每日计划", "sun.max")
            nav("all", "全部任务", "checklist")
            nav("activity", "验收记录", "checkmark.shield")
            nav("pet", "我的陪伴", "heart")
            nav("settings", "工具与设置", "slider.horizontal.3")
            Spacer()
            VStack(alignment: .leading, spacing: 9) {
                Text("随时看一眼").font(.caption).foregroundStyle(.secondary)
                Button { model.onShowFloat?() } label: { Label("打开悬浮计划", systemImage: "pin") }
                Toggle("桌面小伙伴", isOn: $model.petVisible).toggleStyle(.switch).font(.caption)
            }.buttonStyle(.plain).foregroundStyle(sage)
            Divider().padding(.vertical, 12)
            Text("本地保存 · 不催促，也不扣分")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(24).frame(width: 200).background(Color.white.opacity(0.45))
    }
    private func nav(_ id: String, _ title: String, _ icon: String) -> some View {
        Button { model.route = id } label: {
            Label(title, systemImage: icon).font(.system(size: 13, weight: model.route == id ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 11)
                .background(model.route == id ? sage.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).foregroundStyle(model.route == id ? sage : ink.opacity(0.75))
    }
    private var daily: some View {
        VStack(alignment: .leading, spacing: 21) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.route == "all" ? "YOUR OWN PACE" : "A LITTLE EVERY DAY")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(sage)
                    Text(model.route == "all" ? "每一件，都算数。" : "今天，慢慢来。")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text(model.route == "all" ? "看看所有计划，再决定下一步。" : "把想做的写下来，让每一步都有着落。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.showPlan = true } label: { Label("帮我规划", systemImage: "sparkles") }
                    .buttonStyle(.bordered).tint(sage)
            }
            HStack {
                if model.route != "all" {
                    Button { model.selectedDay = Calendar.current.date(byAdding: .day, value: -1, to: model.selectedDay)! } label: { Image(systemName: "chevron.left") }
                    DatePicker("计划日期", selection: $model.selectedDay, displayedComponents: .date).labelsHidden()
                        .environment(\.timeZone, TimeZone(identifier: model.state?.timezone ?? "Asia/Shanghai")!)
                    Button { model.selectedDay = Calendar.current.date(byAdding: .day, value: 1, to: model.selectedDay)! } label: { Image(systemName: "chevron.right") }
                    Button("今天") { model.selectedDay = Date() }
                }
                Spacer()
                Text("\(model.selectedTasks.filter(\.done).count) / \(model.selectedTasks.count) 已完成")
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                Button { model.newTask() } label: { Label("新建任务", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).tint(sage).keyboardShortcut("n", modifiers: .command)
            }.buttonStyle(.borderless)
            if model.selectedTasks.isEmpty {
                VStack(spacing: 12) {
                    Companion(model: model, size: 150)
                    Text("今天想先完成哪一件小事？").font(.system(size: 17, weight: .medium))
                    Text("写下任务、截止时间和验收标准，剩下的我们一起。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("写下第一件事") { model.newTask() }.buttonStyle(.borderedProminent).tint(sage).padding(.top, 5)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.selectedTasks) { task in NativeTaskCard(model: model, task: task) }
                    }.padding(.vertical, 2)
                }
            }
        }.padding(30)
    }
}

struct NativeTaskCard: View {
    @ObservedObject var model: DayproofModel
    let task: DayTask
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button { model.toggle(task) } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24)).foregroundStyle(task.done ? sage : Color.gray.opacity(0.45))
            }.buttonStyle(.plain).disabled(model.busy).padding(.top, 2)
                .help(task.done ? "重新打开任务" : "手动确认完成")
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(task.title).font(.system(size: 15, weight: .medium)).strikethrough(task.done).foregroundStyle(task.done ? Color.secondary : ink)
                    Spacer()
                    Button { model.edit(task) } label: { Image(systemName: "pencil") }.buttonStyle(.plain).foregroundStyle(.secondary).help("编辑任务")
                }
                HStack(spacing: 10) {
                    Label(task.priority == "high" ? "优先处理" : task.priority == "low" ? "慢慢来" : "普通", systemImage: "flag")
                        .foregroundStyle(task.priority == "high" ? Color.orange : sage)
                    if let deadline = task.deadline.flatMap(isoDate) {
                        Label { Text(deadline, format: .dateTime.month().day().hour().minute()) } icon: { Image(systemName: "clock") }
                            .foregroundStyle(!task.done && deadline < Date() ? Color.orange : Color.secondary)
                    } else { Label("未设截止时间", systemImage: "clock").foregroundStyle(.secondary) }
                    Text("\(task.estimate) 分钟").foregroundStyle(.secondary)
                }.font(.system(size: 10))
                if !task.criteria.isEmpty {
                    Text(task.criteria).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    Label(ruleName(task.rule.type), systemImage: "checkmark.shield").font(.system(size: 10)).foregroundStyle(sage)
                    Text(task.source).font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer()
                    if !task.done && task.canCheck {
                        Button { model.check(task) } label: { Label("立即验收", systemImage: "arrow.clockwise") }
                            .buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(sage).disabled(model.busy)
                    }
                }
                if let v = task.lastCheck {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(v.reason).font(.system(size: 11)).foregroundStyle(v.outcome == "pass" ? sage : Color.secondary)
                        if !v.evidence.isEmpty { Text(v.evidence).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled) }
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(paper, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }.padding(18).background(.white.opacity(task.done ? 0.55 : 0.92), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(sage.opacity(0.08)))
            .environment(\.timeZone, TimeZone(identifier: model.state?.timezone ?? "Asia/Shanghai")!)
    }
}
func ruleName(_ type: String) -> String {
    ["manual": "手动确认", "file_exists": "文件存在", "file_contains": "文本匹配", "json_equals": "JSON 状态", "markdown_checklist": "进度清单（纯代码）", "reading_notes": "论文笔记（纯代码）", "email_draft": "邮件草稿（纯代码）", "llm": "模型验收已停用"][type] ?? type
}

struct ActivityView: View {
    @ObservedObject var model: DayproofModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("每一步，有迹可循。").font(.system(size: 28, weight: .semibold))
            Text("最近 50 条验收和手动确认记录。任务完成，以证据为准。")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(Array((model.state?.events ?? []).enumerated()), id: \.offset) { _, event in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(event.title ?? "任务记录").font(.system(size: 13, weight: .medium))
                            Text(event.reason ?? event.source ?? "状态已更新").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            if let time = event.checkedAt.flatMap(isoDate) { Text(time, style: .date).font(.caption2).foregroundStyle(.tertiary) }
                        }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }.padding(30)
    }
}
