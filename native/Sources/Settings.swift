import AppKit
import SwiftUI

struct CompanionSettings: View {
    @ObservedObject var model: DayproofModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("一点陪伴，一点好心情。").font(.system(size: 28, weight: .semibold, design: .rounded))
                HStack(spacing: 30) {
                    Companion(model: model, size: 180)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.petPack?.displayName ?? "年糕").font(.title2.bold())
                        Text(model.petMessage).foregroundStyle(.secondary)
                        HStack { Button("摸摸") { model.pat() }; Button("喂小鱼干") { model.feed() } }
                    }
                }.frame(maxWidth: .infinity).padding(22).background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
                Toggle("显示桌面小伙伴（可以拖动）", isOn: $model.petVisible)
                Toggle("安静陪伴：关闭动画和完成庆祝", isOn: $model.quiet)
                Text("完成一项任务，小猫会陪你庆祝。没有饥饿惩罚，也不会因为没做完计划而责怪你。")
                    .foregroundStyle(.secondary).font(.callout)
                Divider()
                Text("换个小伙伴").font(.headline)
                Text("支持 AgentPet / Petdex 格式的本地素材包：pet.json + 透明精灵图。空白间隔自动切分动画，第一行动画用于待机，第三行（若有）用于庆祝。请遵守素材作者的许可。")
                    .font(.callout).foregroundStyle(.secondary)
                HStack { Button("导入宠物文件夹…") { model.importPet() }; Button("恢复年糕") { model.useDefaultPet() } }
                Link("AgentPet 开源项目 ↗", destination: URL(string: "https://github.com/ntd4996/agentpet")!)
                Text("已集成 AgentPet 的 MIT 开源精灵图切片模块。内置年糕由原生绘图生成。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(32)
        }
    }
}

struct DesktopSettings: View {
    @ObservedObject var model: DayproofModel
    @State private var copied = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("工具与设置").font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Dayproof 0.2 · 原生 macOS 版").foregroundStyle(.secondary)
                GroupBox("悬浮计划") {
                    HStack {
                        Toggle("始终置顶", isOn: $model.floatPinned)
                        Spacer(); Button("显示悬浮窗") { model.onShowFloat?() }
                    }.padding(10)
                }
                GroupBox("本地免费模型 · Ollama") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Picker("当前模型", selection: Binding(get: { model.state?.settings.model ?? "" }, set: { model.setModel($0) })) {
                                ForEach(Array(Set(model.models + [model.state?.settings.model ?? "qwen2.5:0.5b"])).sorted(), id: \.self) { Text($0).tag($0) }
                            }.frame(maxWidth: 330)
                            Button("刷新") { Task { await model.loadModels() } }
                        }
                        Text(model.modelAvailable ? "Ollama 已连接，仅在你主动生成计划时使用。任务验收不调用模型。" : "Ollama 未连接。手动任务和文件 / JSON 规则仍可使用。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("让 AI 工具把计划写进来") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("复制命令到相应终端执行；支持 MCP 的其他工具可以使用通用配置。应用运行时，AI 可读写计划、提交证据并请求验收。")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            copyButton("Codex 命令", model.backend.config.mcpCommand(client: "codex"))
                            copyButton("Claude Code 命令", model.backend.config.mcpCommand(client: "claude"))
                            copyButton("通用 MCP JSON", model.backend.config.mcpJSON)
                        }
                        if !copied.isEmpty { Text("已复制：\(copied)").font(.caption).foregroundStyle(sage) }
                        Text("WorkBuddy / DeepSeek harness 的接法取决于其 MCP 支持；不支持 MCP 时可使用本地 HTTP API。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(10)
                }
                GroupBox("数据和证据") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("证据目录：\(model.state?.evidenceRoot ?? "")").font(.caption).textSelection(.enabled)
                        Text("数据目录：\(model.backend.config.data.path)").font(.caption).textSelection(.enabled)
                        HStack {
                            Button("更换证据目录…") { model.chooseEvidence() }
                            Button("打开数据目录") { NSWorkspace.shared.open(model.backend.config.data) }
                            Button("导出 JSON…") { model.export() }
                            Button("运行日志") { NSWorkspace.shared.open(model.backend.config.support.appendingPathComponent("desktop.log")) }
                        }
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("关闭主窗口后继续自动验收；从菜单栏退出 Dayproof 才会停止。电脑睡眠或应用退出期间不检查。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(30)
        }
    }
    private func copyButton(_ title: String, _ text: String) -> some View { Button(title) { model.copy(text); copied = title } }
}
