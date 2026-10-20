# Mac App Store 发布评估

检查日期：2026-10-19。结论：**目前不能把现有 Dayproof 构建直接提交到 Mac App Store。** 这不是补一个图标或证书就能解决的事。

## 本机与构建证据

- `xcode-select -p` 指向 `/Library/Developer/CommandLineTools`；`xcodebuild -version` 无法运行，机器未选用完整 Xcode。
- `security find-identity -v -p codesigning` 返回 `0 valid identities found`。
- 当前 `build/Dayproof.app` 使用 ad-hoc 签名：`Signature=adhoc`、`TeamIdentifier=not set`；`spctl --assess` 拒绝它。这适合本机开发测试，不是 App Store 签名。
- 构建 Info.plist 没有 `com.apple.security.app-sandbox` entitlement，也没有 App Store provisioning profile。
- App 在启动时创建 Swift 子进程运行随包 Node 服务和 SQLite；服务会打开本机 HTTP/MCP 端点，持续检查任务。证据目录允许用户选择或设定任意文件夹。
- 构建使用仓库自定义 Swift 编译与打包脚本，并非 Xcode 的 App Store archive/export 流程。
- 当前只确认本机没有签名 identity；没有读取或确认开发者的 Apple Developer Program/App Store Connect 账号状态。

## 需要处理的实质工作

1. 先确定保留原生计划、MCP/HTTP、后台验收哪些功能，再做 App Store 目标。Apple 要求 Mac App Store 应用启用 App Sandbox；沙盒需要显式声明网络和文件权限。现在的广泛证据目录访问需要迁移为用户通过系统面板选择文件/目录并使用 security-scoped bookmarks，数据写入应用容器。
2. 设计沙盒内的任务服务生命周期。Node 子进程本身不自动等于违规，但必须由主应用拥有、随退出停止、在 sandbox 与 review 规则下可行，并且不能变成可执行用户代码的通道。需要针对这一具体架构做 Xcode archive 和审核策略验证。
3. 新建或迁移到 Xcode 项目/target，创建 App Store distribution 签名与 provisioning profile，使用有效 bundle ID。当前 `app.dayproof.desktop` 尚未核实归属或注册状态。
4. 在 App Store Connect 建立应用记录，完成隐私问卷、年龄分级、分类、地区、价格、商店说明和截图，并使用 Xcode/Transporter 上传。账号需有相应 App Store Connect 角色。
5. 用沙盒归档测试任务创建、文件授权持久化、MCP 连接、关窗/退出和后台检查；整理审核备注，说明非显然的后台检查行为。

这意味着应评估一个专用的 App Store 版本与当前 GitHub/直接下载版本的功能差异。不能先承诺 MCP/本地服务按现状一定会被接受。

Apple 当前规则和流程：

- [App Review Guidelines 2.4.5](https://developer.apple.com/app-store/review/guidelines/)：Mac App Store 应用需适当沙盒化、使用 Xcode 支持的打包方式、自包含；后台启动/进程需符合用户同意要求。
- [配置 macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)：App Sandbox entitlement 是 Mac App Store review 的要求之一。
- [上传 App Store build](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)：上传前需 App Store Connect app record，构建通过 Xcode、Transporter 等认可路径上传。
- [Apple Developer Program membership details](https://developer.apple.com/programs/whats-included/)：会员身份验证后提供团队身份、证书、标识符和配置文件。

## 当前可做的发布路线

**直接提交 App Store：目前不可行。** 缺完整 Xcode、有效签名身份、沙盒版本、应用记录和审核元数据。

**外部直接分发：架构上更贴近当前版本**，可以保留本机目录和 MCP 服务；仍需要 Developer ID 签名、公证与安装包/更新流程。本机当前也没有 Developer ID 证书，所以目前同样不能完成签名公证发布。GitHub 源码可以继续公开；用户可按 README 从源码构建，但 ad-hoc `.app` 不应宣传为已签名发行版。
