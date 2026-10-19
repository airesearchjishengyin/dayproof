import AppKit
import SwiftUI
import Combine
import ImageIO

@MainActor
final class DayproofModel: ObservableObject {
    let backend: Backend
    @Published var state: AppState?
    @Published var error = ""
    @Published var ready = false
    @Published var busy = false
    @Published var route = "today"
    @Published var selectedDay = Date()
    @Published var editor: DayTask?
    @Published var showEditor = false
    @Published var showPlan = false
    @Published var models: [String] = []
    @Published var modelAvailable = false
    @Published var petPack: ImagePetPack?
    @Published var petMessage = "今天也一起，慢慢来。"
    @Published var celebrating = false
    @Published var patCount = 0
    @Published var quiet = false { didSet { defaults.set(quiet, forKey: "quiet") } }
    @Published var floatPinned = true { didSet { defaults.set(floatPinned, forKey: "pinned"); onPinChange?(floatPinned) } }
    @Published var petVisible = true { didSet { defaults.set(petVisible, forKey: "petVisible"); onPetVisibility?(petVisible) } }
    @Published var collapsed = false
    var onPinChange: ((Bool) -> Void)?
    var onPetVisibility: ((Bool) -> Void)?
    var onShowMain: (() -> Void)?
    var onShowFloat: (() -> Void)?
    var onHideFloat: (() -> Void)?
    var onChange: (() -> Void)?
    private var timer: Timer?
    private var previousDone: Set<String>?
    private var lastToday = ""
    private var refreshing = false
    private var celebrationTask: Task<Void, Never>?
    private var companionTask: Task<Void, Never>?
    private var defaults: UserDefaults
    init(config: DesktopConfig) {
        backend = Backend(config: config)
        defaults = config.smoke ? UserDefaults(suiteName: "app.dayproof.smoke.\(ProcessInfo.processInfo.processIdentifier)")! : .standard
        quiet = defaults.bool(forKey: "quiet")
        floatPinned = defaults.object(forKey: "pinned") as? Bool ?? true
        petVisible = defaults.object(forKey: "petVisible") as? Bool ?? true
        let current = config.support.appendingPathComponent("pet")
        if FileManager.default.fileExists(atPath: current.appendingPathComponent("pet.json").path) {
            petPack = Self.validPack(at: current)
        }
    }
    var todayTasks: [DayTask] { sorted(state?.tasks.filter { $0.day == state?.today } ?? []) }
    var todayDone: Int { todayTasks.filter(\.done).count }
    var selectedTasks: [DayTask] {
        let date = dayString(selectedDay, timezone: state?.timezone ?? "Asia/Shanghai")
        return sorted(state?.tasks.filter { route == "all" || $0.day == date } ?? [])
    }
    var nextTask: DayTask? { todayTasks.first { !$0.done } }
    var progress: Double { todayTasks.isEmpty ? 0 : Double(todayDone) / Double(todayTasks.count) }
    func sorted(_ tasks: [DayTask]) -> [DayTask] {
        tasks.sorted {
            if $0.done != $1.done { return !$0.done }
            let rank = ["high": 0, "normal": 1, "low": 2]
            if rank[$0.priority] != rank[$1.priority] { return (rank[$0.priority] ?? 1) < (rank[$1.priority] ?? 1) }
            return ($0.deadline ?? "z") < ($1.deadline ?? "z")
        }
    }
    func launch() async {
        error = ""
        ready = false
        do {
            try await backend.start()
            ready = true
            try await refresh()
            await loadModels()
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.ready else { return }
                    do { try await self.refresh() } catch { self.error = "本地服务暂时不可用：\(error.localizedDescription)" }
                }
            }
        } catch { self.error = error.localizedDescription }
        onChange?()
    }
    func refresh() async throws {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let fresh: AppState = try await backend.request("/state")
        let done = Set(fresh.tasks.filter(\.done).map(\.id))
        if let previous = previousDone, !done.subtracting(previous).isEmpty, !quiet {
            celebrate()
        }
        if lastToday != fresh.today {
            if lastToday.isEmpty || dayString(selectedDay, timezone: fresh.timezone) == lastToday { selectedDay = Date() }
            lastToday = fresh.today
        }
        previousDone = done
        state = fresh
        onChange?()
    }
    func perform(_ operation: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = ""
        Task {
            defer { busy = false }
            do { try await operation(); try await refresh() }
            catch { self.error = error.localizedDescription }
        }
    }
    func toggle(_ task: DayTask) {
        perform { [self] in
            let _: DayTask = try await backend.request("/tasks/\(task.id)/status", method: "PATCH", body: jsonBody(["done": !task.done]))
        }
    }
    func check(_ task: DayTask) {
        perform { [self] in
            let _: DayTask = try await backend.request("/tasks/\(task.id)/check", method: "POST", body: jsonBody([:]))
        }
    }
    func save(_ draft: TaskDraft, replacing id: String?) async throws {
        let _: DayTask = try await backend.request(id.map { "/tasks/\($0)" } ?? "/tasks", method: id == nil ? "POST" : "PUT", body: encoded(draft))
        try await refresh()
    }
    func delete(_ task: DayTask) async throws {
        let _: OK = try await backend.request("/tasks/\(task.id)", method: "DELETE")
        try await refresh()
    }
    func newTask() { editor = nil; showEditor = true; onShowMain?() }
    func edit(_ task: DayTask) { editor = task; showEditor = true; onShowMain?() }
    func celebrate() {
        celebrationTask?.cancel()
        celebrating = true
        petMessage = ["又完成一件，我都看见啦！", "这一小步，也很值得庆祝。", "辛苦啦！给你一朵小花。"].randomElement()!
        celebrationTask = Task {
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            guard !Task.isCancelled else { return }
            celebrating = false
            petMessage = "按自己的节奏，我陪着你。"
        }
    }
    func pat() {
        patCount += 1
        petMessage = ["呼噜呼噜…收到你的摸摸啦。", "陪你待一会儿，也很好。", "不用一直高效，也可以休息一下。", "今天的你，已经很努力了。"].randomElement()!
        companionTask?.cancel()
        companionTask = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled, !celebrating else { return }
            petMessage = "今天也一起，慢慢来。"
        }
    }
    func feed() { patCount += 1; petMessage = "小鱼干收到了！分你一半好心情。" }
    func loadModels() async {
        if let info: ModelInfo = try? await backend.request("/ollama") { models = info.models; modelAvailable = info.available }
    }
    func setModel(_ name: String) {
        perform { [self] in
            let _: ModelSettings = try await backend.request("/settings", method: "POST", body: encoded(ModelSettings(model: name)))
        }
    }
    func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "dayproof-\(state?.today ?? dayString()).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform { [self] in
            // Keep all JSON export fields, including audit records, exactly as provided by the API.
            let token = try String(contentsOf: backend.config.data.appendingPathComponent("token"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            var req = URLRequest(url: URL(string: backend.config.base + "/api/export")!)
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            let (data, response) = try await backend.session.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NativeError(message: "导出失败") }
            try data.write(to: url, options: .atomic)
        }
    }
    func chooseEvidence() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.prompt = "选择证据目录"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        defaults.set(url.path, forKey: "evidenceRoot")
        Task { timer?.invalidate(); backend.stop(); await launch() }
    }
    func importPet() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.prompt = "导入宠物包"
        panel.message = "选择含 pet.json 和精灵图的文件夹（AgentPet / Petdex 格式）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try installPet(from: url) } catch { self.error = error.localizedDescription }
    }
    func installPet(from url: URL) throws {
        guard let pack = Self.validPack(at: url), let data = try? Data(contentsOf: url.appendingPathComponent("pet.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let sheet = manifest["spritesheetPath"] as? String
        else { throw NativeError(message: "无法读取宠物包。需要有效的 pet.json、透明精灵图和相对文件路径（最多 1600 万像素）。") }
        let target = backend.config.support.appendingPathComponent("pet")
        let staging = backend.config.support.appendingPathComponent("pet-import-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let image = url.appendingPathComponent(sheet)
        var metadata = manifest
        metadata["spritesheetPath"] = "spritesheet." + image.pathExtension
        try JSONSerialization.data(withJSONObject: metadata).write(to: staging.appendingPathComponent("pet.json"))
        try fm.copyItem(at: image, to: staging.appendingPathComponent(metadata["spritesheetPath"] as! String))
        for name in ["LICENSE", "LICENSE.md", "LICENSE.txt", "CREDITS.md"] where fm.fileExists(atPath: url.appendingPathComponent(name).path) {
            try fm.copyItem(at: url.appendingPathComponent(name), to: staging.appendingPathComponent(name))
        }
        guard Self.validPack(at: staging) != nil else { throw NativeError(message: "宠物包复制校验失败，已保留当前宠物。") }
        let backup = backend.config.support.appendingPathComponent("pet-backup-\(UUID().uuidString)")
        let hadOld = fm.fileExists(atPath: target.path)
        if hadOld { try fm.moveItem(at: target, to: backup) }
        do { try fm.moveItem(at: staging, to: target) }
        catch { if hadOld { try? fm.moveItem(at: backup, to: target) }; throw error }
        try? fm.removeItem(at: backup)
        petPack = Self.validPack(at: target)
        petMessage = "你好呀，我是\(pack.displayName)！"
    }
    static func validPack(at directory: URL) -> ImagePetPack? {
        let manifest = directory.appendingPathComponent("pet.json").resolvingSymlinksInPath()
        let root = directory.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard manifest.path.hasPrefix(root),
              let attrs = try? FileManager.default.attributesOfItem(atPath: manifest.path),
              (attrs[.size] as? Int ?? Int.max) <= 65536,
              let data = try? Data(contentsOf: manifest),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = object["spritesheetPath"] as? String, !path.hasPrefix("/"),
              let id = object["id"] as? String, !id.isEmpty,
              let name = object["displayName"] as? String, !name.isEmpty else { return nil }
        let sheet = directory.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard sheet.path.hasPrefix(root),
              let attrs = try? FileManager.default.attributesOfItem(atPath: sheet.path),
              (attrs[.size] as? Int ?? Int.max) <= 20_000_000,
              let source = CGImageSourceCreateWithURL(sheet as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, w <= 8192, h <= 8192, w * h <= 16_000_000,
              let pack = SpriteSlicer.loadPack(directory: directory),
              pack.clips.reduce(0, { $0 + $1.count }) <= 240 else { return nil }
        return pack
    }
    func useDefaultPet() {
        try? FileManager.default.removeItem(at: backend.config.support.appendingPathComponent("pet"))
        petPack = nil; petMessage = "年糕回来陪你啦。"
    }
    func stop() { timer?.invalidate(); celebrationTask?.cancel(); companionTask?.cancel(); backend.stop() }
}
