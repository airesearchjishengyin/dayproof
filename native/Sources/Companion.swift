import AppKit
import SwiftUI

let sage = Color(red: 0.28, green: 0.43, blue: 0.35)
let paper = Color(red: 0.97, green: 0.97, blue: 0.94)
let ink = Color(red: 0.20, green: 0.26, blue: 0.22)

struct Companion: View {
    @ObservedObject var model: DayproofModel
    var size: CGFloat = 110
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.16, paused: reduceMotion || model.quiet)) { context in
            let time = reduceMotion || model.quiet ? 0 : context.date.timeIntervalSinceReferenceDate
            Group {
                if let pack = model.petPack {
                    let clip = pack.clip(model.celebrating ? min(2, pack.clipCount - 1) : 0)
                    if !clip.isEmpty {
                        Image(nsImage: clip[Int(time * 6) % clip.count])
                            .resizable().interpolation(.none).scaledToFit()
                    }
                } else {
                    CatDrawing(blink: Int(time * 6) % 37 == 0, happy: model.celebrating || model.patCount > 0)
                }
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(model.celebrating ? sin(time * 9) * 5 : sin(time * 1.5) * 1.5))
            .offset(y: model.celebrating ? -abs(sin(time * 6)) * 9 : sin(time * 2) * 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.pat() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("摸摸\(model.petPack?.displayName ?? "年糕")")
        .accessibilityAddTraits(.isButton)
        .help("点击摸摸，拖动空白处移动")
    }
}

struct PetWindowView: View {
    @ObservedObject var model: DayproofModel
    var body: some View {
        VStack(spacing: 3) {
            if !model.quiet {
                Text(model.petMessage)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(ink)
                    .multilineTextAlignment(.center).padding(12)
                    .frame(maxWidth: 205, minHeight: 46)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.6)))
            }
            Companion(model: model, size: 124)
                .contextMenu {
                    Button("摸摸") { model.pat() }
                    Button("喂一条小鱼干") { model.feed() }
                    Button("查看计划") { model.onShowFloat?() }
                    Button("打开 Dayproof") { model.onShowMain?() }
                    Divider()
                    Toggle("安静陪伴", isOn: $model.quiet)
                    Button("隐藏桌宠") { model.petVisible = false }
                }
        }
        .frame(width: 230, height: 218, alignment: .bottom)
        .padding(.bottom, 8)
    }
}

struct FloatingPlan: View {
    @ObservedObject var model: DayproofModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "pawprint.fill").foregroundStyle(sage)
                Text("今天的计划").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(model.todayDone)/\(model.todayTasks.count)").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                Button { model.floatPinned.toggle() } label: { Image(systemName: model.floatPinned ? "pin.fill" : "pin") }.help(model.floatPinned ? "取消置顶" : "置顶")
                Button { withAnimation { model.collapsed.toggle() } } label: { Image(systemName: model.collapsed ? "chevron.down" : "chevron.up") }.help("展开或收起计划")
                Button { model.onHideFloat?() } label: { Image(systemName: "xmark") }.help("隐藏小窗，菜单栏可重新打开")
            }.buttonStyle(.plain).padding(16)
            if !model.collapsed {
                ProgressView(value: model.progress).tint(sage).padding(.horizontal, 16)
                if !model.ready {
                    Text(model.error.isEmpty ? "正在准备今天的计划…" : model.error).font(.caption).foregroundStyle(.secondary).padding(20)
                } else if model.todayTasks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "sun.max").font(.title2).foregroundStyle(sage)
                        Text("先从一件小事开始。").font(.system(size: 13))
                        Button("添加今天的任务") { model.newTask() }.buttonStyle(.borderedProminent).tint(sage)
                    }.frame(maxWidth: .infinity).padding(.vertical, 28)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(model.todayTasks.prefix(6))) { task in
                                CompactTask(model: model, task: task).padding(.vertical, 10)
                                if task.id != model.todayTasks.prefix(6).last?.id { Divider() }
                            }
                        }.padding(.horizontal, 16)
                    }.frame(maxHeight: 235)
                }
                HStack(spacing: 6) {
                    Companion(model: model, size: 52)
                    Text(model.quiet ? "按自己的节奏，一件一件来。" : model.petMessage)
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 0)
                }.padding(.horizontal, 12).padding(.vertical, 5)
                Divider()
                HStack {
                    Button { model.newTask() } label: { Label("添加", systemImage: "plus") }
                    Spacer()
                    Button("完整计划 ↗") { model.onShowMain?() }
                }.font(.system(size: 12, weight: .medium)).buttonStyle(.plain).foregroundStyle(sage).padding(14)
            }
        }
        .foregroundStyle(ink)
        .frame(width: 332)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.5)))
        .padding(7)
    }
}
struct CompactTask: View {
    @ObservedObject var model: DayproofModel
    let task: DayTask
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { model.toggle(task) } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19)).foregroundStyle(task.done ? sage : .secondary)
            }.buttonStyle(.plain).disabled(model.busy).help(task.done ? "重新打开任务" : "手动确认完成")
            VStack(alignment: .leading, spacing: 5) {
                Text(task.title).font(.system(size: 12, weight: .medium)).strikethrough(task.done).lineLimit(2)
                HStack(spacing: 6) {
                    if let deadline = task.deadline.flatMap(isoDate) {
                        Text(deadline, style: .time)
                    } else { Text("未设截止时间") }
                    if task.canCheck { Image(systemName: "checkmark.shield") }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !task.done && task.canCheck {
                Button { model.check(task) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).font(.caption).help("立即验收").disabled(model.busy)
            }
        }
        .contextMenu { Button("编辑任务") { model.edit(task) }; Button("立即验收") { model.check(task) } }
    }
}
