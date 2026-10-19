import AppKit
import Foundation

struct NativeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct DesktopConfig {
    let resources: URL
    let support: URL
    let data: URL
    let port: Int
    let smoke: Bool
    var base: String { "http://127.0.0.1:\(port)" }
    var node: URL { resources.appendingPathComponent("node") }
    var backend: URL { resources.appendingPathComponent("backend") }
    var evidence: URL {
        if let path = ProcessInfo.processInfo.environment["DAYPROOF_EVIDENCE_ROOT"] { return URL(fileURLWithPath: path) }
        if let path = UserDefaults.standard.string(forKey: "evidenceRoot") { return URL(fileURLWithPath: path) }
        if let data = try? Data(contentsOf: resources.appendingPathComponent("bootstrap.json")),
           let config = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let path = config["evidenceRoot"], FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return support.appendingPathComponent("Evidence")
    }
    init() {
        let env = ProcessInfo.processInfo.environment
        resources = Bundle.main.resourceURL!
        smoke = env["DAYPROOF_SMOKE_TEST"] == "1"
        support = env["DAYPROOF_SUPPORT_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Dayproof")
        data = support.appendingPathComponent("data")
        port = Int(env["DAYPROOF_PORT"] ?? "4317") ?? 4317
    }
    func mcpCommand(client: String) -> String {
        let prefix = client == "claude" ? "claude mcp add --transport stdio dayproof" : "codex mcp add dayproof"
        return "\(prefix) --env \(shellQuote("DATA_DIR=" + data.path)) --env \(shellQuote("DAYPROOF_URL=" + base)) -- \(shellQuote(node.path)) \(shellQuote(backend.appendingPathComponent("mcp.mjs").path))"
    }
    var mcpJSON: String {
        let value: [String: Any] = ["mcpServers": ["dayproof": ["command": node.path,
            "args": [backend.appendingPathComponent("mcp.mjs").path],
            "env": ["DATA_DIR": data.path, "DAYPROOF_URL": base]]]]
        return String(data: try! JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!
    }
}
func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

@MainActor
final class Backend {
    let config: DesktopConfig
    private var process: Process?
    private var log: FileHandle?
    let session = URLSession(configuration: .ephemeral)
    init(config: DesktopConfig) { self.config = config }
    func start() async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: config.data, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.createDirectory(at: config.evidence, withIntermediateDirectories: true)
        if !config.smoke,
           !fm.fileExists(atPath: config.data.appendingPathComponent("dayproof.sqlite").path),
           let bootstrap = try? Data(contentsOf: config.resources.appendingPathComponent("bootstrap.json")),
           let object = try? JSONSerialization.jsonObject(with: bootstrap) as? [String: String],
           let legacy = object["legacyData"], fm.fileExists(atPath: legacy + "/dayproof.sqlite") {
            let migration = Process()
            migration.executableURL = config.node
            migration.arguments = [config.backend.appendingPathComponent("migrate.mjs").path, legacy, config.data.path]
            migration.currentDirectoryURL = config.backend
            try migration.run()
            migration.waitUntilExit()
            guard migration.terminationStatus == 0 else { throw NativeError(message: "旧版数据迁移失败，原数据保留。") }
        }
        // Never attach silently to or terminate a different process already using this port.
        var probe = URLRequest(url: URL(string: config.base + "/api/session")!)
        probe.timeoutInterval = 0.5
        if (try? await session.data(for: probe)) != nil {
            throw NativeError(message: "端口 \(config.port) 已被使用。请退出旧版 Dayproof 服务，再点重试。")
        }
        let logURL = config.support.appendingPathComponent("desktop.log")
        if !fm.fileExists(atPath: logURL.path) { fm.createFile(atPath: logURL.path, contents: nil) }
        log = try FileHandle(forWritingTo: logURL)
        try log?.seekToEnd()
        let child = Process()
        child.executableURL = config.node
        child.arguments = [config.backend.appendingPathComponent("index.mjs").path]
        child.currentDirectoryURL = config.backend
        var env = ProcessInfo.processInfo.environment
        env["PORT"] = String(config.port)
        env["DATA_DIR"] = config.data.path
        env["EVIDENCE_ROOT"] = config.evidence.path
        env["DAYPROOF_NODE"] = config.node.path
        env["DAYPROOF_MCP_ENTRY"] = config.backend.appendingPathComponent("mcp.mjs").path
        child.environment = env
        child.standardOutput = log
        child.standardError = log
        try child.run()
        process = child
        for _ in 0..<100 {
            guard child.isRunning else { throw NativeError(message: "本地服务未能启动，请在设置中打开运行日志。") }
            if fm.fileExists(atPath: config.data.appendingPathComponent("token").path),
               let _: AppState = try? await request("/state") {
                try config.mcpJSON.write(to: config.support.appendingPathComponent("mcp-config.json"), atomically: true, encoding: .utf8)
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        stop()
        throw NativeError(message: "本地服务启动超时，请重试。")
    }
    func stop() {
        if let child = process, child.isRunning {
            child.terminate()
            let deadline = Date().addingTimeInterval(3)
            while child.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.03) }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
        process = nil
        try? log?.close()
        log = nil
    }
    func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        let token = try String(contentsOf: config.data.appendingPathComponent("token"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        var request = URLRequest(url: URL(string: config.base + "/api" + path)!)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = path == "/plan/generate" ? 100 : 120
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(APIError.self, from: data)
            throw NativeError(message: error?.error ?? "本地服务连接失败")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
struct APIError: Decodable { let error: String }
struct OK: Decodable { let ok: Bool }
struct ModelInfo: Decodable { let available: Bool; let models: [String] }
struct ModelSettings: Codable { let model: String }
struct PlanResult: Codable { let tasks: [TaskDraft] }
struct AppState: Decodable {
    let tasks: [DayTask]
    let events: [CheckEvent]
    let today: String
    let timezone: String
    let evidenceRoot: String
    let settings: ModelSettings
}
struct CheckEvent: Decodable, Identifiable {
    var id: String { (checkedAt ?? "") + (title ?? "") + (reason ?? "") }
    let title: String?
    let reason: String?
    let checkedAt: String?
    let source: String?
}
struct Verdict: Codable {
    let outcome: String
    let reason: String
    let evidence: String
    let checkedAt: String
}
enum Primitive: Codable {
    case string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else { self = .string(try c.decode(String.self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .string(let s): try c.encode(s); case .number(let n): try c.encode(n); case .bool(let b): try c.encode(b); case .null: try c.encodeNil() }
    }
    var json: String { String(data: try! JSONEncoder().encode(self), encoding: .utf8)! }
}
struct TaskRule: Codable {
    var type: String = "manual"
    var path: String?
    var text: String?
    var key: String?
    var value: Primitive?
    var autoComplete: Bool?
    var items: [String]?
    var papers: [String]?
    var recipient: String?
}
struct TaskDraft: Codable {
    var title: String
    var day: String
    var deadline: String?
    var priority: String = "normal"
    var source: String = "Dayproof 桌面"
    var criteria: String = ""
    var estimate: Int = 30
    var intervalMinutes: Int = 5
    var rule: TaskRule = TaskRule()
}
struct DayTask: Codable, Identifiable {
    let id: String
    var title: String
    var day: String
    var deadline: String?
    var priority: String
    var source: String
    var criteria: String
    var estimate: Int
    var intervalMinutes: Int
    var rule: TaskRule
    let status: String
    let lastCheck: Verdict?
    var done: Bool { status == "done" }
    var canCheck: Bool { rule.type != "manual" && rule.type != "llm" }
    var draft: TaskDraft { TaskDraft(title: title, day: day, deadline: deadline, priority: priority, source: source, criteria: criteria, estimate: estimate, intervalMinutes: intervalMinutes, rule: rule) }
}
func encoded<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
func jsonBody(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
func isoDate(_ value: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}
func dayString(_ date: Date = Date(), timezone: String = "Asia/Shanghai") -> String {
    let f = DateFormatter(); f.timeZone = TimeZone(identifier: timezone); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
}
