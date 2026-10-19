import AppKit
import SwiftUI
import Darwin

extension AppDelegate {
    func runSmoke() async {
        let support = model.backend.config.support
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DAYPROOF_SMOKE_OUTPUT"] ?? support.path)
        var checks = [String]()
        func expect(_ ok: Bool, _ name: String) throws {
            guard ok else { throw NativeError(message: "Smoke assertion: " + name) }
            checks.append(name)
        }
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try expect(model.ready && model.state != nil, "native startup owns bundled backend")
            let day = model.state!.today
            var draft = TaskDraft(title: "完成订阅流程，并保存验收结果", day: day, deadline: ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)), priority: "high", criteria: "subscription.active 为 true，保留真实验证结果", rule: TaskRule(type: "json_equals", path: "subscription.json", key: "subscription.active", value: .bool(true)))
            let created: DayTask = try await model.backend.request("/tasks", method: "POST", body: encoded(draft))
            let pending: DayTask = try await model.backend.request("/tasks/\(created.id)/check", method: "POST", body: jsonBody([:]))
            try expect(!pending.done, "missing evidence never marks task complete")
            try "{\"subscription\":{\"active\":true}}".write(to: model.backend.config.evidence.appendingPathComponent("subscription.json"), atomically: true, encoding: .utf8)
            let passed: DayTask = try await model.backend.request("/tasks/\(created.id)/check", method: "POST", body: jsonBody([:]))
            try expect(passed.done && passed.lastCheck?.outcome == "pass", "JSON evidence automatically completes task")
            try await model.refresh()
            try expect(model.celebrating && model.todayDone == 1, "completion updates native progress and celebrates")
            draft.title = "订阅流程复查"
            try await model.save(draft, replacing: created.id)
            try expect(model.state?.tasks.first?.done == false, "editing resets completion for revalidation")
            let _: DayTask = try await model.backend.request("/tasks/\(created.id)/check", method: "POST", body: jsonBody([:]))
            let plan = PlanResult(tasks: [TaskDraft(title: "整理今日计划，留一点休息时间", day: day, criteria: "写下三项要做的事"), TaskDraft(title: "给项目补上使用说明", day: day, source: "Claude Code", criteria: "README 包含启动和验收方法", rule: TaskRule(type: "file_contains", path: "README.md", text: "验收"))])
            let imported: [DayTask] = try await model.backend.request("/plan/import", method: "POST", body: encoded(plan))
            try await model.refresh()
            try expect(imported.count == 2 && model.todayTasks.count == 3, "agent plan import reaches native list")
            let _: DayTask = try await model.backend.request("/tasks/\(imported[0].id)/status", method: "PATCH", body: jsonBody(["done": true]))
            try await model.refresh()
            try expect(model.todayDone == 2, "manual completion supported")
            let evidence = model.backend.config.evidence
            try "- [x] 保存与加载\n".write(to: evidence.appendingPathComponent("progress.md"), atomically: true, encoding: .utf8)
            try FileManager.default.createDirectory(at: evidence.appendingPathComponent("notes"), withIntermediateDirectories: true)
            let paper = "https://arxiv.org/abs/2601.00001"
            let note = "paper: \(paper)\n" + ["问题", "方法", "我的理解"].map { "## \($0)\n" + String(repeating: "这是测试笔记的占位正文，不代表阅读完成。", count: 4) }.joined(separator: "\n")
            try note.write(to: evidence.appendingPathComponent("notes/paper.md"), atomically: true, encoding: .utf8)
            let mail = "To: jobs@example.com\nSubject: 游戏岗位申请\n\n" + String(repeating: "这是用于结构测试的邮件正文，不是实际申请。", count: 8)
            try mail.write(to: evidence.appendingPathComponent("application.eml"), atomically: true, encoding: .utf8)
            let codeRules: [(TaskRule, String)] = [
                (TaskRule(type: "markdown_checklist", path: "progress.md", items: ["保存与加载"]), "pass"),
                (TaskRule(type: "reading_notes", path: "notes", autoComplete: false, papers: [paper]), "review"),
                (TaskRule(type: "email_draft", path: "application.eml", autoComplete: false, recipient: "jobs@example.com"), "review"),
                (TaskRule(type: "llm", path: "missing.txt", autoComplete: true), "review")
            ]
            for (rule, outcome) in codeRules {
                let fixture = TaskDraft(title: "纯代码验收演示：\(rule.type)", day: day, criteria: "仅验收约定产物或声明，不证明内容质量", rule: rule)
                let saved: DayTask = try await model.backend.request("/tasks", method: "POST", body: encoded(fixture))
                let checked: DayTask = try await model.backend.request("/tasks/\(saved.id)/check", method: "POST", body: jsonBody([:]))
                try expect(checked.lastCheck?.outcome == outcome && checked.rule.type == rule.type, "native rule roundtrip: " + rule.type)
                if rule.type == "markdown_checklist" {
                    model.edit(checked)
                    try await Task.sleep(nanoseconds: 400_000_000)
                    try expect(mainWindow.sheets.count == 1, "native code-checklist editor opens")
                    if let sheet = mainWindow.sheets.first { try snapshot(sheet, to: output.appendingPathComponent("native-checklist-editor.png")) }
                    model.showEditor = false
                    try await Task.sleep(nanoseconds: 300_000_000)
                }
                let _: OK = try await model.backend.request("/tasks/\(saved.id)", method: "DELETE")
            }
            try await model.refresh()
            model.pat(); try expect(model.patCount == 1 && !model.petMessage.isEmpty, "pet responds to touch")
            model.feed(); try expect(model.petMessage.contains("小鱼干"), "pet feeding responds")
            try expect(floatWindow.level == .floating && !petWindow.isOpaque && petWindow.isVisible, "floating transparent native panels")
            model.floatPinned = false; try expect(floatWindow.level == .normal, "unpin changes window level")
            model.floatPinned = true
            model.petVisible = false; try expect(!petWindow.isVisible, "pet hides independently")
            model.petVisible = true
            mainWindow.performClose(nil)
            let _: AppState = try await model.backend.request("/state")
            try expect(!mainWindow.isVisible, "closing main window leaves verifier running")
            showMain()
            try testSpritePack(support: support, checks: &checks)
            model.useDefaultPet()
            model.quiet = true; model.petMessage = "今天的每一小步，我都看见啦。"
            resizeFloat()
            try await Task.sleep(nanoseconds: 600_000_000)
            try snapshot(mainWindow, to: output.appendingPathComponent("native-planner.png"))
            try snapshot(floatWindow, to: output.appendingPathComponent("native-floating.png"))
            try snapshot(petWindow, to: output.appendingPathComponent("native-pet.png"))
            model.collapsed = true; resizeFloat()
            try expect(floatWindow.frame.height == 94, "floating plan collapses")
            model.collapsed = false; resizeFloat()
            model.route = "settings"
            try await Task.sleep(nanoseconds: 400_000_000)
            try snapshot(mainWindow, to: output.appendingPathComponent("native-settings.png"))
            model.route = "today"; model.newTask()
            try await Task.sleep(nanoseconds: 400_000_000)
            try expect(mainWindow.sheets.count == 1, "native task editor sheet opens")
            if let sheet = mainWindow.sheets.first { try snapshot(sheet, to: output.appendingPathComponent("native-editor.png")) }
            model.showEditor = false
            try await Task.sleep(nanoseconds: 300_000_000)
            model.showPlan = true
            try await Task.sleep(nanoseconds: 400_000_000)
            try expect(mainWindow.sheets.count == 1, "native plan composer sheet opens")
            if let sheet = mainWindow.sheets.first { try snapshot(sheet, to: output.appendingPathComponent("native-composer.png")) }
            try jsonBody(["ok": true, "checks": checks]).write(to: output.appendingPathComponent("native-result.json"))
        } catch {
            try? jsonBody(["ok": false, "error": error.localizedDescription, "checks": checks]).write(to: output.appendingPathComponent("native-result.json"))
        }
        for sheet in mainWindow.sheets { mainWindow.endSheet(sheet) }
        model.stop()
        Darwin.exit(0)
    }
    private func snapshot(_ window: NSWindow, to url: URL) throws {
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw NativeError(message: "Native snapshot failed") }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw NativeError(message: "PNG encoding failed") }
        try png.write(to: url)
    }
    private func testSpritePack(support: URL, checks: inout [String]) throws {
        let pack = support.appendingPathComponent("fixture-pack")
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 50, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        NSColor.orange.setFill(); NSBezierPath(ovalIn: NSRect(x: 10, y: 10, width: 25, height: 30)).fill()
        NSBezierPath(ovalIn: NSRect(x: 65, y: 10, width: 25, height: 30)).fill()
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: pack.appendingPathComponent("sheet.png"))
        try jsonBody(["id": "fixture", "displayName": "Fixture", "spritesheetPath": "sheet.png"]).write(to: pack.appendingPathComponent("pet.json"))
        try model.installPet(from: pack)
        guard let loaded = model.petPack, loaded.clips.reduce(0, { $0 + $1.count }) >= 2 else { throw NativeError(message: "AgentPet slicer did not split fixture") }
        checks.append("AgentPet sprite slicer and local pack installation")
        try jsonBody(["id": "escape", "displayName": "Escape", "spritesheetPath": "../outside.png"]).write(to: pack.appendingPathComponent("pet.json"))
        guard DayproofModel.validPack(at: pack) == nil else { throw NativeError(message: "Path escape accepted") }
        checks.append("pet pack rejects path escape")
    }
}
