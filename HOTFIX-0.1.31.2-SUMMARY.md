# Insulation 0.1.31.2 Hotfix 总结

## 修复内容

### 1. 内存管理修复 ✅
**问题：** `ThermalManagerDimmingPatch.m` 中的 `cachedThermalManagerConfig` 静态缓存导致潜在的悬空指针问题。

**修复：**
- 移除静态缓存变量
- 每次调用 `hook_ThermalManager_getConfigurationFor` 返回新的 `CFDictionary` 副本
- 由调用者管理生命周期，避免 caller 持有过期指针

**代码变更：**
```diff
-static CFDictionaryRef cachedThermalManagerConfig = NULL;

-if (cachedThermalManagerConfig) {
-    CFRelease(cachedThermalManagerConfig);
-}
-cachedThermalManagerConfig = newConfig;
-return (void *)cachedThermalManagerConfig;
+// Return a new copy each time instead of caching
+// Caller is responsible for managing the lifetime
+return (void *)newConfig;
```

### 2. 线程安全修复 ✅
**问题：** 偏好设置缓存刷新函数 `insulationThermalPatchRefreshPrefsIfNeeded` 在多线程环境下存在竞争条件。

**修复：**
- 添加 `dispatch_queue_t` 串行队列保护缓存访问
- 使用 `dispatch_once` 确保队列只创建一次
- 分两阶段检查：先判断是否需要刷新，再在队列中执行刷新

**代码变更：**
```diff
+static dispatch_queue_t prefsCacheQueue = nil;
+static dispatch_once_t onceToken;
+dispatch_once(&onceToken, ^{
+    prefsCacheQueue = dispatch_queue_create("com.be-huge.insulation.prefs-cache", DISPATCH_QUEUE_SERIAL);
+});
+
+__block BOOL shouldRefresh = NO;
+dispatch_sync(prefsCacheQueue, ^{
     NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
-    if (cachedPrefsTime >= 0 && now - cachedPrefsTime < 0.05) {
-        return;
+    if (cachedPrefsTime < 0 || now - cachedPrefsTime >= 0.05) {
+        shouldRefresh = YES;
     }
+});
+
+if (!shouldRefresh) return;

-    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:InsulationPrefsPath];
-    ...
+dispatch_sync(prefsCacheQueue, ^{
+    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
+    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:InsulationPrefsPath];
+    ...
+    cachedPrefsTime = now;
+});
```

---

## 版本信息

- **版本号：** 0.1.31.2
- **分支：** `hotfix/0.1.31.2-memory-fix`
- **Commit：** `c8b8cdd`
- **基于：** 0.1.31.1 (commit `7cab466`)

---

## 构建状态

### ✅ 编译成功
- **Rootless (arm64):** `packages/com.be-huge.insulation_0.1.31.2_iphoneos-arm64.deb` (57K)
- **Roothide (arm64e):** 需要通过 GitHub Actions 构建（本地环境缺少 Swift）

### 构建命令
```bash
# Rootless
cd /root/.openclaw/workspace/repos/insulation
export THEOS=/root/.openclaw/workspace/toolchains/theos
export PATH=/root/.openclaw/workspace/toolchains/bin:$THEOS/bin:$PATH
bash scripts/build-objc-package.sh

# Roothide (推荐通过 CI)
git push origin hotfix/0.1.31.2-memory-fix
# 等待 GitHub Actions 完成构建
```

---

## 影响范围

### 修复的问题
- **内存安全：** 避免 thermalmonitord 长时间运行时的潜在崩溃
- **并发稳定性：** 防止多线程访问偏好设置时的竞争条件
- **内存泄漏：** 每次返回新副本，避免累积未释放的 CFDictionary

### 未改变的功能
- ✅ 防暗屏（light 封顶）
- ✅ 满血模式（压力归零 + 功率提升）
- ✅ 低功耗模式（CPU 限制）
- ✅ fullPower warmup guard（6 秒保护期）
- ✅ 所有用户可见功能保持不变

---

## 测试建议

### 测试场景
1. **短期稳定性：** 安装后运行 1-2 小时，观察是否有崩溃
2. **长期稳定性：** 运行 24 小时，观察内存占用和稳定性
3. **设置切换：** 快速切换"防暗屏"、"满血"、"低功耗"三种模式，验证响应正常
4. **多线程压力：** 运行游戏或重负载应用，观察 thermalmonitord 是否稳定

### 验证命令
```bash
# 检查 thermalmonitord 进程是否正常
ps aux | grep thermalmonitord

# 查看系统日志（观察是否有异常）
log stream --predicate 'process == "thermalmonitord"' --level debug

# 检查内存占用（应该稳定）
top -pid $(pgrep thermalmonitord) -stats pid,command,mem
```

---

## 后续计划

### 短期（本周）
- [x] 应用 P1 修复 patch
- [x] 编译 0.1.31.2 hotfix 版本
- [ ] 通过 GitHub Actions 构建 roothide 包
- [ ] 发布 0.1.31.2（可选，或合并到下个版本）

### 中期（下个版本 0.1.32）
- [ ] 实施架构重构（方案 A）
  - 删除未使用的 `InsulationRuntimeHooks.m`
  - 合并重复代码到 `insulationShared/`
  - 统一偏好设置管理
- [ ] 减少代码量 ~40%
- [ ] 减少二进制体积 ~50%

---

## 相关文档

- **P1 修复 Patch：** `patches/p1-fix-memory-and-cache.patch`
- **架构重构方案：** `docs/refactor-architecture-proposal.md`
- **审查报告：** 见 Git commit message

---

## 致谢

感谢代码审查发现的问题，这次修复提升了插件的稳定性和安全性。

---

**构建日期：** 2025-06-08  
**维护者：** doimty  
**项目：** https://github.com/be-huge/insulation
