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

/// Original vector cat. No external artwork, neural rendering or network calls.
struct CatDrawing: View {
    let blink: Bool
    let happy: Bool
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 140
            ctx.scaleBy(x: s, y: s)
            func ellipse(_ rect: CGRect, _ color: Color) { ctx.fill(Path(ellipseIn: rect), with: .color(color)) }
            let fur = Color(red: 0.97, green: 0.86, blue: 0.67)
            let line = Color(red: 0.37, green: 0.29, blue: 0.22)
            ellipse(CGRect(x: 23, y: 123, width: 100, height: 10), .black.opacity(0.10))
            var tail = Path(); tail.move(to: CGPoint(x: 110, y: 109)); tail.addCurve(to: CGPoint(x: 124, y: 85), control1: CGPoint(x: 137, y: 120), control2: CGPoint(x: 140, y: 85))
            ctx.stroke(tail, with: .color(fur), style: StrokeStyle(lineWidth: 13, lineCap: .round))
            ellipse(CGRect(x: 30, y: 68, width: 80, height: 60), fur)
            var ears = Path()
            ears.move(to: CGPoint(x: 29, y: 43)); ears.addLine(to: CGPoint(x: 29, y: 13)); ears.addQuadCurve(to: CGPoint(x: 57, y: 34), control: CGPoint(x: 36, y: 10)); ears.closeSubpath()
            ears.move(to: CGPoint(x: 84, y: 34)); ears.addQuadCurve(to: CGPoint(x: 112, y: 13), control: CGPoint(x: 107, y: 7)); ears.addLine(to: CGPoint(x: 113, y: 47)); ears.closeSubpath()
            ctx.fill(ears, with: .color(fur))
            var inner = Path(); inner.move(to: CGPoint(x: 34, y: 34)); inner.addLine(to: CGPoint(x: 34, y: 21)); inner.addLine(to: CGPoint(x: 48, y: 34)); inner.closeSubpath()
            inner.move(to: CGPoint(x: 94, y: 34)); inner.addLine(to: CGPoint(x: 107, y: 21)); inner.addLine(to: CGPoint(x: 107, y: 38)); inner.closeSubpath()
            ctx.fill(inner, with: .color(Color(red: 0.88, green: 0.62, blue: 0.57)))
            ellipse(CGRect(x: 22, y: 28, width: 98, height: 76), fur)
            ellipse(CGRect(x: 44, y: 82, width: 54, height: 43), .white.opacity(0.35))
            ellipse(CGRect(x: 31, y: 113, width: 31, height: 17), fur)
            ellipse(CGRect(x: 78, y: 113, width: 31, height: 17), fur)
            for x in [48.0, 90.0] {
                if blink || happy {
                    var eye = Path(); eye.move(to: CGPoint(x: x - 5, y: 62)); eye.addQuadCurve(to: CGPoint(x: x + 5, y: 62), control: CGPoint(x: x, y: 56))
                    ctx.stroke(eye, with: .color(line), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                } else {
                    ellipse(CGRect(x: x - 3, y: 55, width: 7, height: 10), line)
                    ellipse(CGRect(x: x - 1, y: 56, width: 2, height: 3), .white)
                }
            }
            ellipse(CGRect(x: 32, y: 69, width: 17, height: 8), .pink.opacity(0.30))
            ellipse(CGRect(x: 94, y: 69, width: 17, height: 8), .pink.opacity(0.30))
            var nose = Path(); nose.move(to: CGPoint(x: 66, y: 67)); nose.addLine(to: CGPoint(x: 75, y: 67)); nose.addLine(to: CGPoint(x: 70.5, y: 72)); nose.closeSubpath()
            ctx.fill(nose, with: .color(line))
            var smile = Path(); smile.move(to: CGPoint(x: 60, y: 74)); smile.addQuadCurve(to: CGPoint(x: 70.5, y: 75), control: CGPoint(x: 65, y: 83)); smile.addQuadCurve(to: CGPoint(x: 81, y: 74), control: CGPoint(x: 76, y: 83))
            ctx.stroke(smile, with: .color(line), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            for y in [67.0, 75.0] {
                var whisker = Path(); whisker.move(to: CGPoint(x: 18, y: y - 2)); whisker.addLine(to: CGPoint(x: 32, y: y)); whisker.move(to: CGPoint(x: 109, y: y)); whisker.addLine(to: CGPoint(x: 125, y: y - 2))
                ctx.stroke(whisker, with: .color(line.opacity(0.4)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            if happy { ctx.draw(Text("✦").font(.system(size: 18)).foregroundColor(.orange), at: CGPoint(x: 125, y: 35)) }
        }
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
