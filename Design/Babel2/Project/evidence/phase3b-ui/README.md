# Phase3B UI evidence

这是 Phase3B 的最小、可长期复核的 UI driver evidence 包。它记录目标 iPhone 17 / iOS 27 Simulator 上真实无参数启动、Feeds 根页、当前 UI 顺序的单一 source、缓存文章正文、Open Original 系统交接，以及 article/feed 返回根页。入口是 [manifest.json](manifest.json)，构建与 test-without-building 摘要见 [build-summary.json](build-summary.json)，脱敏 runtime 探针见 [runtime-probe.json](runtime-probe.json)，截图清单见 [screenshot-inventory.json](screenshot-inventory.json)。

实际 test count 为 1。r1 的 `UI_SELECTOR_TIMEOUT` 是修复稳定 table identifier 之前的失败轮次；r2 与 r3 均为 1/1 passed。Open Original 的 deterministic assertion 是 `SafariViewService` 进入 foreground，不断言网络或外部页面内容。reader 与 after-browser 原始附件只保留在 `/private/tmp/babel2-phase3b-ui-*` xcresult，不复制正文、标题、URL、hierarchy 或凭据到仓库；持久化截图仅保留 root/feed/back，其中 `screenshots/feed.png` 已按 [screenshot-inventory.json](screenshot-inventory.json) 的源附件和裁剪命令确定性裁为 1206×390 的顶部 status/header/feed name/count 区域，不含文章标题、日期、正文或 URL。

数据边界必须按事实解释：安装和测试序列中观察到 `articles/statuses/search` `424 → 425 → 426`，并伴随 data-container UUID 轮换；同一 r2 产物的 r3 重复为 `426 → 426`。因此状态是 `UNEXPECTED_DATA_MUTATION`，原因未证实，不能称为 read-only，也不能无证据归因后台同步。FeedSettings 维持 10，SQLite integrity 每次为 `ok`。

本轮已应用截图和 bundle tree digest 的 P1 evidence correction；独立只读复核结果为 `pass`，manifest 状态为 `phase3b_evidence_gate_closed_after_independent_recheck`，范围仅为 Phase3B implementation + automation + persistent evidence。复核没有重跑 build/test/install/launch。`P0/P1=0` 仅指实现代码复审；Phase1A、真实物理 iPhone、旧 storyboard/nib 与 3 个 appex allowlist、完整 scene 恢复、视觉/性能验收，以及 cache 先读后验证/无界 cache、同名 tie-break 和 Open Original 无 URL 语义缺口等 P2 仍 OPEN。r2/r3 的 enabled Open Original → SafariViewService 真实路径仍保留为已通过证据，但无 URL 时按钮行为尚未有独立语义验证。旧 Phase3 package/full-test/build/runtime 证据仍在 [../phase3/README.md](../phase3/README.md) 及其同目录 JSON 中，没有被本包覆盖。无 commit、无 push。

原始临时 log、xcresult、derived data 和 simulator probe 目录只通过 manifest/build-summary 的路径、SHA 与精简结果索引；本目录不保存大型 xcresult。
