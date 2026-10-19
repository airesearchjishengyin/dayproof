# 桌面 / 办公 Agent Verifier 开源调研

核查日期：2026-10-19。范围：自然语言任务验收、桌面/办公程序化验证、自动生成 reward、可复用 skill/插件，以及 agent RL 的连接方式。

方法：实时检索候选工作，直接读取官方论文、仓库 README、许可证和关键代码；对 OpenComputer 的单个离线验证模块执行本机小样例。搜索结果只用于发现，核心判断以列出的第一方来源为依据。这不是完整系统综述，也没有运行全部框架。部分搜索请求被后端拒绝，相关核心项目通过 GitHub/API/raw 文件及 arXiv 直接核查。

后续深入核查见：[从桌面评测到低成本自动验收：源码综述](verifier-review-2026-10-19.md)。重要补充：Prime Verifiers 当前版本已经有默认调用 `cloudflare/clef` 的 `DecisionJudge`；不能把现有框架统称为“只有代码或生成式 LLM judge”。新版综述另比较 Jev、Clef、OpenDecider、OpenDecision 与 OpenJev，区分权重许可、中文/上下文限制、编写与运行成本，并补充 OfficeBench 局部反例实验。

## 结论

1. **现成可复用部件确实存在。** OpenComputer 最接近“通用应用检查函数 + 模型填参 + 自动扩展验证器”，OSWorld 有丰富的办公 evaluator，DocOps 更适合原生办公文件的细粒度检查。
2. **“LLM 生成可执行 verifier，用于电脑 agent RL”已经有直接相关研究。** CUA-Gym、OpenComputer、ScaleCUA/VeriGen 等覆盖了重要部分，不能以此笼统主张首次创新。
3. **本次没有确认一个可以直接替换 Dayproof 的成品。** 已查框架主要面向可重置的实验环境或绑定自身执行器；没有核实到一个同时满足自然语言验收编译、独立观察人/多种 agent 的真实桌面工作、跨应用证据绑定、事件缓存、严格推理预算和原生计划器体验的现成组合。该结论只限本次范围，不能推导成“市场上不存在”。
4. 建议采用 **Dayproof 产品外壳 + 经适配的 OpenComputer / DocOps / OSWorld 验证原语 + 独立的组合与证据运行时**。RL 适配器后置，避免把重型训练环境一起塞进个人桌面应用。

## 重点项目对照

| 项目 | 已核查到的能力 | 对我们的复用价值 | 主要缺口 / 成本 | 许可核查 |
|---|---|---|---|---|
| [OpenComputer][1] | 论文与 README 报告 33 应用、1,000 任务；每应用 Python CLI/JSON 状态端点；生成、测试、修复 verifier；程序化检查优先，可选 LLM judge | 第一优先：应用状态检查接口、参数化检查、测试流程 | 当前发布环境为 Ubuntu/XFCE 沙箱；宿主 macOS 和真实账户需适配；运行器含自由表达式 `eval`，不适合直接接受终端用户输入 | Apache-2.0 |
| [OSWorld][2] | 文档/表格/幻灯片/文件/浏览器等 getter 与 metric；execution-based evaluation | 选择性提取已有办公判据，不必从零写全部格式检查 | evaluator 经常依赖任务特定参考文件、VM 控制器和软件状态；文档模块有 OCR/图像库等重依赖 | Apache-2.0 |
| [DocOps][3] | 官方仓库列出 210 个 Harbor 任务；XLSX/DOCX/PPTX/PDF；检查目标修改、格式/结构及未要求修改的属性是否保留 | 原生文档验证函数与负例设计非常有价值 | 多数 test 为具体任务编写；需要参数化并拆分依赖。能检查已知语义目标，不代表能理解任意新方案 | 根仓库 Apache-2.0；自带 skills/third_party 需逐项保留许可 |
| [CUA-Gym][4] | 共生成 task/environment/reward；Generator 与 Discriminator 分离；执行检查 golden=1、initial=0；领域 skills；可选受约束的 LLM judge | 借鉴验证器生成、正反例测试、领域知识 skill | 面向合成训练任务/可控环境，含大量 mock 网站；生成流程需要 agent/环境资源；不是零成本个人桌面后台服务 | LICENSE 为 Apache-2.0；README 另列数据 CC-BY-4.0 |
| [ScaleCUA / VeriGen][5] | 生成并验证 evaluator；轨迹引导任务拆分/组合；已有函数的领域 skill 文档；online RL 管线 | 检查函数目录与 skill 描述组织方式、生成后的动态测试 | 编写/修复阶段依赖 coding agent 和沙箱。当前读取版本未看到根许可证，不能据“公开仓库”直接复制 | 根许可未确认，复用前逐文件核查 |
| [Prime Intellect Verifiers][6] | RL/eval 环境库；代码、生成式及决策模型 judge；`DecisionJudge` 默认 Clef；独立评分沙箱与私有测试 | 决策接口、计费 trace、将来导出 RL 环境 | 默认决策 judge 评最后回复，不独立读取桌面结果；实际检查器仍需适配 | MIT |
| [Heliox OS][7] | 原生桌面 agent + Verifier 类；文件/进程等动作有后置条件检查 | 真实桌面集成的补充参考 | README 明确只有部分动作有独立观察；源码允许无独立证据时按 executor 结果通过，不满足我们的严格任务验收标准 | MIT |

以上任务数量来自项目发布说明，未逐个跑通，也不拿不同 benchmark 的任务数或榜单分数比较 verifier 质量。

## OpenComputer：直接命中“会议纪要”例子

固定核查版本：`76c5ec32221045a68c4ca47a799e0abc4b303d6a`。

其 [Writer 文档][8] 提供：

- `parse-text <path>`、`parse-paragraphs <path>`、`parse-tables <path>`：离线读 ODT。
- `check-file-exists <path>`、`check-heading-exists <heading> <level>`、`check-table-cell ...` 等参数化检查。
- UNO 通道读取正在运行的 LibreOffice 内容；离线 ODF 通道只读已保存文件。

其 [meeting_minutes 任务][9] 已将“创建会议纪要”分为：标题、参会人、行动表格、负责人、已保存与路径存在等检查。任务 JSON 为已有命令填参数，这正是我们要避免重复生成整段代码的机制。

需要区分：它能证明指定标题/内容/结构存在，不能仅凭这些判据证明新技术方案可落地。未知业务语义仍需要明确 rubric、额外原始资料或模型/人工判断。

### 本机小样例

直接下载固定提交的 [Writer Python 模块][10] 到临时目录，核对 SHA-256 后执行离线方法；使用自己生成的最小 ODT XML ZIP，不读用户文档，不连接 UNO/E2B，不调用 LLM。

结果：正文提取、段落顺序、表格内容、缺失文件、损坏文件处理共 5 项检查通过。

同时实测两个限制：

1. `parse_file_text` 先收集正文段落，再收集标题，因此可能改变原始顺序。
2. 此全文函数不包含表格单元格；独立 `parse_file_tables` 能读到表格。

不能直接把该全文函数的输出当成完整文档交给 decision model。适配器应在原顺序上整合段落、表格与可定位证据，明确不支持的内容。测试也不证明所有 ODT 格式、GUI 集成或整个项目都已验证。

复现脚本：[scripts/research/smoke_opencomputer.py](../scripts/research/smoke_opencomputer.py)。结果：[research/opencomputer-offline-smoke.json](research/opencomputer-offline-smoke.json)。Python 要求至少 3.10；本机使用 3.11，系统默认 3.9 无法导入上游的类型注解。

另一个源码观察：[verification.py][11] 存在 `eval(check["eval"])` 和 `judge: llm` 分支。我们可以复用具体检查函数，不能把这个运行器未经调整就挂到自然语言用户输入后面。LLM 分支必须接 Dayproof 的授权、预算和数据范围控制。

## DocOps：更适合 DOCX / XLSX / PPTX / PDF

固定版本：`ccf7a751bc5c8a69c1cdd0400125d53455b33be3`。仓库基于原生文件状态判定，不只检查屏幕文字。

实际阅读的 [verifier_utils.py][12] 包括文件预检、文本归一化、必需/禁止短语、正则、段落/字体签名、表格/公式相关辅助函数。一个 [Word 任务测试][13] 检查标题层级、重复或旧标签、目录项和样式一致性。

价值在于提取通用函数和“必须保留什么”的检查思路。不能把任务 test 函数名中的 `semantic` 理解为它调用了通用语义模型；本次读到的样例是确定性的 Python 断言。检查固定标签与样式无法直接判断任意会议技术方案的质量。

建议 Dayproof 的文档入口同时关注：格式可读、要求达成、未要求修改的关键属性未被破坏。对应的检查器要按实际文档类型加载依赖，避免导入一个函数就加载全部 PDF/图像库。

## 其他已核查相关工作

- [WorkArena][14]：ServiceNow 知识工作与组合任务，有 `validate` 接口和服务端状态核查。适合借鉴业务状态验证；需 ServiceNow 实例，不是通用桌面 validator。实际 LICENSE 标明 Apache-2.0。
- [OfficeBench][15]：跨应用办公流程，含读取文件、发送邮件等操作，采用精确/模糊/执行式评测。说明跨应用办公验收不是新问题；其任务定义可作为样例，但不是独立观察真实个人办公的现成服务。
- [Windows Agent Arena][16]：Windows 桌面评测平台，MIT；需要相应 Windows 环境。更适合未来 Windows 评测，当前 macOS 个人计划器不宜整体集成。
- [CLI-Anything][17]：可复用 CLI + skill + 结构化输出。非常贴合插件分发机制，但主体是操作软件的能力库，不是独立 outcome verifier。读取/检查接口可审查后利用，写操作不要随验证任务一起暴露。
- [AgentRewardBench][18]：评估自动评委的 benchmark，论文包含人工核查的 agent 轨迹。适合设计“verifier 本身是否可靠”的评测。当前 API 未识别根代码许可证，不作为可直接复制的部件；数据与代码许可分别核查。
- [BenchJack][19]：研究并审计 agent benchmark 的 reward hacking。公开 README 也说明生成 exploit PoC 并非全部自动验证；只能作为漏洞分类与审计思路参考，不能把工具报告直接当作已证实漏洞。
- [GUI vs. CLI][20]：已研究相同目标/状态/verifier 下的 GUI 与 skill-mediated CLI，并分析 verifier-guided skill augmentation。进一步表明“skill + verifier”组合已有直接相关工作。

## 复用方案：通用函数 + 填参 + skill + 插件

用户提出的方案合理。建议把实现分为四层，以便 agent 少写代码、运行时无需 agent 常驻。

| 层 | 内容 | 什么时候需要模型 |
|---|---|---|
| 证据适配器 | 固定路径读取、DOCX/ODT 解析、应用只读状态、消息/附件关联 | 通常不需要 |
| 验证原语 | 文件存在、结构符合、值比较、保留属性、引用位置 | 通常不需要 |
| 验收配方 | 将原语组合成“完成文档”“交付给指定人”等任务图；参数 schema 与缓存策略 | 首次从自然语言映射时可用模型 |
| 语义节点 | 逐项解释“步骤具体、满足业务条件”等无法完全枚举的要求 | 仅在证据变化且授权/预算允许时调用 |

skill 负责告诉模型“何时选哪个函数、参数含义、如何处理不确定”；插件提供实际代码、输入输出 schema、依赖、版本、权限和正反例。`SKILL.md` 不是调度器，不必每次定时检查都重新读取并启动 coding agent。

推荐目录（设计示例，尚未实现）：

```text
verifiers/document/
  manifest.json       # ID、版本、格式、权限、能力与是否调用模型
  input.schema.json   # path、checks、preserve、semanticRubric
  inspect.py          # 解析为带位置的证据，不作任意模型调用
  predicates.py       # 代码判据
  tests/              # 正例、漏项、旧版本、相似但不合格等负例
skills/verify-document/SKILL.md
recipes/document-delivery.json
```

“文件存在且内容满足要求”的入口可以统一，但不要把“满足要求”隐藏成一个没有成本声明的万能函数：

```json
{
  "verifier": "document.acceptance@1",
  "path": "/用户指定目录/会议纪要.docx",
  "checks": [
    {"op": "file.exists"},
    {"op": "document.section_exists", "text": "技术方案"}
  ],
  "semantic": {
    "rubric": ["给出与会议目标对应的具体实施步骤和验收方法"],
    "provider": "local",
    "requiresConsent": true,
    "trigger": "content_hash_changed",
    "maxAttemptsTotal": 10
  }
}
```

这是建议的 DSL 示例，不能直接提交给现有 Dayproof API。运行器还必须独立执行授权与预算，不能因为模型在 JSON 写了 `requiresConsent` 就视为控制已经生效。路径与输入材料只用于选定任务范围；文档内的提示词不能创建额外权限。

现成插件命中则填参；已有原语能覆盖则组合；确实没有能力时才进入“生成新插件 → 正反例测试 → 人工/代码审查 → 注册”的较慢流程。插件一经测试可跨任务复用，但不能让验证器只迎合生成它的单个正例。

## 能否做 Agent RL / paper

### 已经被覆盖的宽泛方向

程序化桌面评测、LLM 生成 reward、按应用复用检查接口、skill 辅助、任务分解、用 verifier 改进 agent，都有相关工作。仅组合这些功能或做成悬浮计划器，并不足以确立研究新颖性；产品实用性与论文贡献是两件分别验证的事。

### 值得验证的研究假设

**预算约束下，从真实用户自然语言任务编译可复用验收计划：在跨任务/跨应用条件下，能否比“每次写 verifier code”与“每次 LLM judge”保持相近或更低的错误打勾率，同时降低调用次数、配置时间与生成失败率？**

潜在贡献应由实验确认，可组合：

1. 小模型填参/组合，未覆盖时受控扩展新插件；测能力复用与新任务泛化。
2. 多种任务执行者（人、不同 agent）共用独立证据接口，跨文档版本与发送记录绑定，避免依赖执行者自报。
3. 不确定时拒绝自动完成；在固定错误打勾率下测自动验收覆盖率与成本，而非只报总准确率。

本次没证实这些组合已经构成未发表的新颖贡献；还需围绕具体假设做更系统的相关工作检索。可命名为“budgeted compositional task verification”研究问题，但不要把命名当成新方法证明。

### RL 的额外要求

日常任务的验收器可以成为终局 reward 的组成部分，但单个真实用户的任务日志不能直接当成可无限训练的环境。

- 明确 instruction、初始状态、可观察状态、终止条件与 episode；在测试账号/文档副本/沙箱中可重置、重放，不能反复用真实领导账号进行训练发送。
- 冻结该轮 verifier，保证 solver 无法修改评分器、审批、证据缓存或伪造状态文件；独立读取实际产物。可借鉴 Verifiers 的独立 grading sandbox。
- 避免 agent 通过标题/关键词堆砌拿奖励；设置“形式满足但内容不符”的负例和 agent 定向作弊测试。
- 各检查条件可记录部分得分用于诊断，但“全部完成”仍需所有必要项通过；部分奖励加权可能鼓励投机，不能随意拿平均分替代完成标准。
- `unknown`/连接器故障/预算耗尽不等于任务失败；输出有效性掩码，无法可靠评分的 episode 不应当作可信 0/1 奖励训练。
- 正负对照、mutation 测试、独立人工标签和留出任务共同验证 reward；initial=0 / golden=1 是必要的基础检查，但两个样本远不足以证明正确。

### 最小研究验证（建议规模，未执行）

先建约 60–100 个任务、3 个任务族：文档修改/生成、表格处理、文档交付（在测试环境模拟或测试账号发送）。这是试验建议，不是论文统计功效保证。

对比：固定规则、直接 LLM judge、逐任务生成 Python、检索并组合插件。使用同一模型与输入预算，再单独比较小模型与较强模型。

按模板族/文档样式/组合方式划分训练与测试，避免同一任务换文件名就算泛化。每项包含正确结果、缺失条件、相似但不符、旧附件/错误接收人、提示注入等变体，人工盲评目标是否真正满足。

指标：错误完成率、误拒绝率、自动覆盖率、放弃/未知率、生成与配置耗时、端到端延迟、每任务模型调用/输入量、本地算力消耗和缓存命中率。增加去缓存、去模板复用、去跨产物绑定等消融。

只有上述结果显示实际优势，再决定做方法论文/benchmark/系统论文，或先做好产品。RL 训练应在 verifier 质量已建立之后另做小规模验证，避免 verifier 错误被策略放大。

## 具体建议

第一步不用 fork 整个训练平台。先审查并包装 OpenComputer 的离线 ODT 检查与 DocOps/OSWorld 的 DOCX 原语，用同一套 `inspect → predicates → optional semantic` 返回结构，在 Dayproof 侧实现版本绑定、授权、预算与缓存。已有运行器的任意表达式与外部模型调用不能原样带入。

第二步才增加“自然语言 → 插件选择/填参”的编译器，测它相对生成整段代码的效果。第三步接一个只读交付记录适配器。最后把统一结果导出到 RL/eval，不把“提供 reward”误称为“已经具备 RL 训练能力”。

本次只新增调研与离线复现材料：没有安装框架到 Dayproof、修改用户任务、连接个人通信账号、调用第三方模型验收或启动 RL 训练。

## 来源（第一方）

[1]: https://github.com/echo0715/OpenComputer/tree/76c5ec32221045a68c4ca47a799e0abc4b303d6a
[2]: https://github.com/xlang-ai/OSWorld/tree/b138d348256078fa634fc3b73567a7337c793e6b/desktop_env/evaluators
[3]: https://github.com/icip-cas/DocOps/tree/ccf7a751bc5c8a69c1cdd0400125d53455b33be3
[4]: https://github.com/xlang-ai/CUA-Gym/tree/1e50b797200f8afd6f11ca8e3ee04412de97b0f2
[5]: https://github.com/THUDM/SCALE-CUA/tree/3929e2fe364623153f2caa94ead71dc1aea50fb0/VeriGen
[6]: https://github.com/PrimeIntellect-ai/verifiers/blob/266c21963d8368d2e9faaf79d61046daad018c9f/docs/building-environments.md
[7]: https://github.com/VyomKulshrestha/Heliox-OS/blob/a2f72421566d0ebd14e8f96a394011dfc4372547/daemon/pilot/agents/verifier.py
[8]: https://github.com/echo0715/OpenComputer/blob/76c5ec32221045a68c4ca47a799e0abc4b303d6a/verifiers/libreoffice_writer/README.md
[9]: https://github.com/echo0715/OpenComputer/blob/76c5ec32221045a68c4ca47a799e0abc4b303d6a/task_generator/tasks/libreoffice_writer_meeting_minutes/task.json
[10]: https://github.com/echo0715/OpenComputer/blob/76c5ec32221045a68c4ca47a799e0abc4b303d6a/verifiers/libreoffice_writer/libreoffice_writer.py
[11]: https://github.com/echo0715/OpenComputer/blob/76c5ec32221045a68c4ca47a799e0abc4b303d6a/evaluation/runtime/verification.py
[12]: https://github.com/icip-cas/DocOps/blob/ccf7a751bc5c8a69c1cdd0400125d53455b33be3/tasks/atomic__word_001_engineering_report_toc_hierarchy_seed/tests/verifier_utils.py
[13]: https://github.com/icip-cas/DocOps/blob/ccf7a751bc5c8a69c1cdd0400125d53455b33be3/tasks/atomic__word_001_engineering_report_toc_hierarchy_seed/tests/test_outputs.py
[14]: https://github.com/ServiceNow/WorkArena/tree/e885130962f61fb64ac305497996a46cfc7d18f0
[15]: https://github.com/zlwang-cs/OfficeBench/tree/b978b808667c32b52ce19a67ce1def1de9ae02b7
[16]: https://github.com/microsoft/WindowsAgentArena
[17]: https://github.com/HKUDS/CLI-Anything/tree/34f519533bc175d2fe287ab8316b0dd99bb9cc43
[18]: https://arxiv.org/abs/2504.08942
[19]: https://github.com/benchjack/benchjack/tree/22c554f217357da5b3107c6e3fd7a128cef42d3b
[20]: https://arxiv.org/abs/2606.24551

补充论文：[OpenComputer](https://arxiv.org/abs/2605.19769)、[CUA-Gym](https://arxiv.org/abs/2605.25624)、[DocOps](https://arxiv.org/abs/2607.19865)、[ScaleCUA](https://arxiv.org/abs/2607.11185)、[BenchJack](https://arxiv.org/abs/2605.12673)。论文/README 的效果声明未在本次独立复现。
