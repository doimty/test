
## 2026-06-20 - Task: 添加仓库执行规范 AGENTS
### What was done
在温控仓库根目录新增 `AGENTS.md`，将用户提供的执行规范原样落库，作为该仓库后续模型/代理执行的统一约束。

### Testing
- 确认目标仓库 `repos/insulation` 原先不存在 `AGENTS.md`，本次已成功创建。
- 通过文件写入结果确认仓库根目录存在新文件 `AGENTS.md`。

### Notes
- `AGENTS.md`：新增仓库级执行规范，约束 scope、验证、记录、高风险确认与回复结构。
- 回滚方式：删除仓库根目录 `AGENTS.md` 即可恢复到添加前状态。


## 2026-06-20 - Task: 收口仓库文档落点并补 README 导航
### What was done
将根目录分散的构建说明、热修复总结和实验阶段文档归档到 `docs/` 子目录，按 build / releases / experiments 分类放置；同时在 `README.md` 增加文档导航入口，并修正实验准备说明中的文档路径。

### Testing
- 确认 `docs/build`、`docs/releases`、`docs/experiments` 下的新文档路径全部存在。
- 检查 `README.md` 已包含指向新文档路径的导航列表。
- 搜索旧文档名引用，确认仓库内剩余引用均已指向新路径。

### Notes
- `README.md`：新增文档导航，作为仓库文档统一入口。
- `docs/build/docs-objc-port-build.md`：从根目录迁入 build 分类，保留 ObjC 迁移与构建说明。
- `docs/releases/HOTFIX-0.1.31.2-SUMMARY.md`：从根目录迁入 releases 分类，保留 0.1.31.2 热修复总结。
- `docs/releases/HOTFIX-0.1.31.4-CRITICAL.md`：从根目录迁入 releases 分类，保留 0.1.31.4 紧急修复说明。
- `docs/experiments/EXPERIMENT_SUMMARY.txt`：从根目录迁入 experiments 分类，保留实验快速参考。
- `docs/experiments/PUSH_SUCCESS.txt`：从根目录迁入 experiments 分类，保留实验分支推送后的构建跟踪说明。
- `docs/experiments/READY.txt`：从根目录迁入 experiments 分类，并修正文档引用路径。
- 回滚方式：将上述文档移回仓库根目录，并删除 `README.md` 新增的文档导航段落。


## 2026-06-20 - Task: 第一阶段清理旧架构残留并收口 ObjC 主线口径
### What was done
删除仓库中已不参与当前 ObjC/C runtime 主线的高置信旧架构残留文件，包括旧 Orion 入口、废弃控制文件、迁移期备份脚本和过时热修复验证脚本；同步更新主 Makefile、静态校验脚本、Linux/Theos 环境引导说明和构建文档，使仓库口径明确为当前 ObjC 主线而非“仍在迁移中的双路径”。

### Testing
- 确认 `Sources/insulationC/Tweak.m`、`control.swift.deprecated`、`scripts/check-objc-port.sh.backup`、`scripts/verify-hotfix-0312.sh` 已删除。
- 搜索旧路径与旧口径引用，确认仓库内不再残留已删除文件的失效引用。
- 运行 `bash scripts/check-objc-port.sh`，全部检查通过。

### Notes
- `Makefile`：移除对已删除 `Tweak.m` 的排除分支，源文件发现逻辑与现状一致。
- `scripts/check-objc-port.sh`：改为校验当前 active source trees 不含 Swift/Orion 残留，并要求旧 Orion 入口文件不存在。
- `scripts/setup-linux-theos-env.sh`：更新构建探针命令，去掉过时的 `USE_OBJC_PORT=1` 探针写法。
- `docs/build/docs-objc-port-build.md`：更新为当前 ObjC 主线构建说明，移除“默认 Swift/Orion、ObjC opt-in shadow、control.objc”旧口径。
- `Sources/insulationC/Tweak.m`：删除旧 Orion 入口文件。
- `control.swift.deprecated`：删除废弃的旧控制文件快照。
- `scripts/check-objc-port.sh.backup`：删除迁移期备份校验脚本。
- `scripts/verify-hotfix-0312.sh`：删除仍依赖不存在 `control.objc` 的过时热修复验证脚本。
- 回滚方式：从 Git 恢复上述删除文件与对应脚本/文档改动，或执行 `git checkout -- Makefile scripts/check-objc-port.sh scripts/setup-linux-theos-env.sh docs/build/docs-objc-port-build.md Sources/insulationC/Tweak.m control.swift.deprecated scripts/check-objc-port.sh.backup scripts/verify-hotfix-0312.sh`。


## 2026-06-20 - Task: 第二阶段清理 SwiftPM 壳子并收口 CI 触发条件
### What was done
删除仓库根目录与 `InsulationPrefs/` 下已不再参与当前 ObjC 主线构建的 `Package.swift` 壳文件；同步更新 `.github/workflows/build.yml`，移除对 `Package.swift` 的触发依赖，避免 CI 继续把已废弃的 SwiftPM 入口当作有效构建信号。

### Testing
- 确认 `Package.swift` 与 `InsulationPrefs/Package.swift` 已删除。
- 搜索 `Package.swift`、`make spm`、`spm_config` 等残留引用，确认仓库内已无失效依赖。
- 检查 `.github/workflows/build.yml`，确认触发路径中已移除 `Package.swift`。

### Notes
- `.github/workflows/build.yml`：移除 `Package.swift` 触发路径，CI 与当前 ObjC 主线保持一致。
- `Package.swift`：删除不再使用的根目录 SwiftPM 壳文件。
- `InsulationPrefs/Package.swift`：删除不再使用的偏好面板 SwiftPM 壳文件。
- 回滚方式：从 Git 恢复 `.github/workflows/build.yml`、`Package.swift`、`InsulationPrefs/Package.swift` 即可。


## 2026-06-20 - Task: 第三阶段收口主线 workflow 并移除重复 CI 定义
### What was done
将主线构建职责统一收口到 `.github/workflows/build.yml`，把该 workflow 提升到与重复 ObjC workflow 一致的校验、打包与产物检查流程；同时删除重复的 `.github/workflows/objc-macos-build.yml` 与 `.github/workflows/insulation-objc-build.yml`，避免主线 CI 定义并存、命名不一致和流程漂移。

### Testing
- 确认 `.github/workflows/objc-macos-build.yml` 与 `.github/workflows/insulation-objc-build.yml` 已删除。
- 检查 `.github/workflows/build.yml`，确认其包含 `scripts/check-objc-port.sh`、`scripts/build-objc-package.sh` 和产物切片检查步骤。
- 搜索 workflow 残留引用，确认仓库内不再引用已删除的两个重复 workflow 文件。

### Notes
- `.github/workflows/build.yml`：统一为主线构建 workflow，补齐 ObjC 主线所需的校验、打包与产物检查步骤。
- `.github/workflows/objc-macos-build.yml`：删除重复的主线 ObjC workflow 定义。
- `.github/workflows/insulation-objc-build.yml`：删除重复的主线 ObjC workflow 定义。
- 回滚方式：从 Git 恢复 `.github/workflows/build.yml`、`.github/workflows/objc-macos-build.yml`、`.github/workflows/insulation-objc-build.yml`。


## 2026-06-20 - Task: 第四阶段收口实验区口径并移除硬编码凭据
### What was done
对实验区做最小收口：将 `README.md` 中的一次性实验准备/构建跟踪快照移出主导航，只保留实验摘要入口；将 `experiment-build.yml` 的默认支持范围收回到当前文档和推送脚本实际覆盖的 `exp-a/b/c`；同时移除 `monitor-builds.sh` 中硬编码的 GitHub token 和仓库地址，改为必须通过环境变量和参数显式传入。

### Testing
- 检查 `README.md`，确认实验区主导航仅保留 `docs/experiments/EXPERIMENT_SUMMARY.txt`。
- 检查 `.github/workflows/experiment-build.yml`，确认默认实验分支仅剩 `exp-a/b/c`。
- 搜索 `exp-d-combined`、`exp-e-delay-50ms` 和旧 `monitor-builds.sh` 用法残留，确认已从当前实验流程口径中移除。
- 运行 `bash -n monitor-builds.sh push-experiments.sh scripts/build-objc-package.sh scripts/check-objc-port.sh scripts/setup-linux-theos-env.sh`，语法检查通过。

### Notes
- `README.md`：将实验准备快照与构建跟踪快照移出主导航，仅保留实验摘要入口。
- `.github/workflows/experiment-build.yml`：默认实验分支收回到 `exp-a-no-boot-guard`、`exp-b-reduce-calls`、`exp-c-aggressive-pressure`。
- `monitor-builds.sh`：移除硬编码 GitHub token 与仓库地址，改为 `GITHUB_TOKEN` + `<owner/repo>` 显式传入。
- `docs/experiments/PUSH_SUCCESS.txt`：标记为阶段性历史快照，并更新 `monitor-builds.sh` 的安全调用方式。
- `docs/experiments/READY.txt`：标记为实验准备阶段快照，提示长期参考优先看 `EXPERIMENT_SUMMARY.txt`。
- 回滚方式：从 Git 恢复 `README.md`、`.github/workflows/experiment-build.yml`、`monitor-builds.sh`、`docs/experiments/PUSH_SUCCESS.txt`、`docs/experiments/READY.txt`。


## 2026-06-20 - Task: 构建级验证第四阶段清理未影响主线出包
### What was done
在本地 Theos 环境下，对当前 ObjC/C runtime 主线执行完整构建验证：先运行 `scripts/check-objc-port.sh` 静态 gate，再分别执行 `scripts/build-objc-package.sh rootless` 和 `scripts/build-objc-package.sh roothide`，确认第四阶段清理未破坏实际出包链路。

### Testing
- `bash scripts/check-objc-port.sh`：通过，active source trees、hook selector、helper API surface、风险扫描均为 OK。
- `scripts/build-objc-package.sh rootless`：成功出包 `packages/com.be-huge.insulation_0.1.36.2_iphoneos-arm64.deb`。
- `scripts/build-objc-package.sh roothide`：成功出包 `packages/com.be-huge.insulation_0.1.36.2_iphoneos-arm64e.deb`。

### Notes
- roothide 构建过程中存在既有 `incompatible arm64e ABI compiler` 链接警告，但最终构建命令退出码为 0，deb 产物已生成；该警告为工具链/ABI 兼容性既有噪音，本轮清理未新增编译错误。
- 本轮验证证明删除旧 `Sources/insulationC/Tweak.m` 及清理 workflow / 文档 / 辅助脚本后，当前主线功能代码仍可正常通过 rootless 与 roothide 出包链路。

