# Babel 2.0 文档更新协议

目的：让任何接手者都能从当前文件、Git 和证据重建真实状态。文档是记录系统，不是把计划包装成完成的发布说明。

## 每次任务开始

1. 按固定顺序读取 [README.md](README.md) → [PRODUCT-CONTRACT.md](../PRODUCT-CONTRACT.md) 与 [MOTION-CONTRACT.md](../MOTION-CONTRACT.md) → [STATUS.md](STATUS.md) → [REQUIREMENTS.md](REQUIREMENTS.md) → [DECISIONS.md](DECISIONS.md) → [VALIDATION.md](VALIDATION.md) → [LESSONS.md](LESSONS.md) → [HANDOFF.md](HANDOFF.md) → [UPDATE-PROTOCOL.md](UPDATE-PROTOCOL.md)。
2. 记录当前日期/时区、分支、`HEAD`、remote-tracking ref 和 `git status --short --branch`。
3. 列出本任务允许修改的精确路径；列出工作树里已有但不属于本任务的改动。
4. 查看其他代理的实际状态和工作树文件；报告、意图或锁文件不能单独证明任务仍在运行。
5. 在 STATUS 中把下一任务标为 in-progress；不要把“准备开始”写成实现完成。

## 开始实现前的范围门

- 需求必须在 REQUIREMENTS 中有 Slice、模块、自动测试、模拟器和真机验收位置。
- 新代码/资源/测试/文档使用 Babel/Babel2 命名；历史名称只在 `audit-only historical reference` 审计段落或明确兼容边界出现。
- 先检查是否会触及共享 motion owner、WebView session、持久化 identity、asset catalog target membership 或 dirty worktree；如果会，先更新 DECISIONS 并由 root 明确拆分。
- 每个界面状态必须指定唯一 owner；禁止用第二个 spinner、第二个 navigator 或复制 controller 绕过既有 owner。

## 提交前

1. 重新记录 Git 状态和实际 diff；只审查授权路径，不覆盖别人的文件。
2. 在 VALIDATION 中写入本次真正运行的命令、提交候选范围、日期、SDK/设备、退出码、测试数量和缺口；如果尚无 commit，明确写 `uncommitted worktree`。
3. 更新 REQUIREMENTS 的状态，但只有对应证据存在才能从 pending 改为 done；计划、代码存在或静态截图不能单独关闭运行时需求。
4. 如有新判断，写入 DECISIONS：日期、选择、理由、被否决方案和重新评估触发。
5. 写入 LESSONS 的新失败模式或 gate；不得只写结论而没有症状/根因。
6. 检查 Markdown 内部链接、表格、重复/矛盾状态，并运行 `git diff --check`；新文件未被 Git 索引时，也要对文件本身做尾随空白检查。

## 提交后

- 将精确 commit SHA、提交内容、测试/构建证据和未覆盖范围回填 VALIDATION。
- 将 STATUS 的 HEAD、已完成/进行中/未开始和下一步更新为提交后的事实。
- 如果提交包含图标或设计资产，同时记录母版、生成/派生关系、用户接受状态、静态 QA 和 runtime 缺口。
- 不要因为提交成功就关闭设备、视觉、性能或用户验收项。

## 推送后

- 记录推送的分支、精确 commit、remote-tracking ref 和实际推送结果。
- 本地 remote-tracking ref 与 hosted remote 的实时状态要分开描述；没有重新获取 hosted remote 证据时，不称为实时远端核验。
- 若推送后发生新的工作树修改，立即在 STATUS 中分开“已推送提交”和“未提交工作树”。

## 受控推送

- 本地已提交不等于允许推送；涉及安全审查或用户明确要求的 commit，必须记录对具体 SHA 的授权后才能执行非 force push。
- 等待授权期间，STATUS/VALIDATION/HANDOFF 必须分别写清 local committed、remote-tracking/hosted remote 当前 SHA 和 push pending，不得把本地 QA PASS 写成远端已发布。

## 代理交接

- 发送给下一个代理的内容必须包含：当前 SHA、允许路径、禁止路径、已验证证据、明确缺口、下一步和停止条件。
- 等待时只轮询真实存在的 agent/process/tool handle；观察超时不是完成，也不是失败。
- 子代理报告必须经过 root 复审并绑定实际文件/命令输出，不能直接升级为完成声明。

## 完成与阻塞规则

- 只有 REQUIREMENTS 中所有必要行都有相匹配的自动化、模拟器、真机和用户接受证据，且 STATUS 没有未关闭的必需项，才可称 Babel 2.0 完成并创建 v2.0。
- 任何一项证据弱于需求范围，都保持 open 并继续推进。
- 不能因为工作量大、测试慢、视觉尚未检查或旧命名难迁移就标记 blocked；只有同一真实外部阻塞连续重复且没有安全替代路径时，才按上层目标规则报告 blocked。
