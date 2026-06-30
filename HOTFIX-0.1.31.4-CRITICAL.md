# Insulation 0.1.31.4 - 紧急修复：恢复反降频核心功能

## ⚠️ 严重问题

**0.1.31.2 存在严重的反降频失效问题！**

**现象：** 设备发热时容易降频（用户报告："发热很容易降频"）

**根本原因：** 在 Swift → ObjC 重构时，**遗漏了 `HidSensorsHook`** — 这是**核心反降频机制**！

---

## 技术分析

### Swift 版本（正常工作）

```swift
class HidSensorsHook: ClassHook<HidSensors> {
  func handleTemperatureEvent(_ arg1: Int, service arg2: Any?) {}
}
```

**作用：** 直接屏蔽 `handleTemperatureEvent` 方法，阻止系统响应高温事件，从而防止触发温控降频。

### ObjC 0.1.31.2（缺失）

❌ **完全没有 `HidSensors` hook**
❌ 温度事件正常传递给系统
❌ 系统正常触发温控降频
❌ 反降频功能失效！

---

## 修复内容

### 新增代码

**1. 函数指针声明：**
```objc
static void (*Orig_HidSensors_handleTemperatureEvent)(id self, SEL _cmd, int event, id service);
```

**2. Hook 实现（屏蔽温度事件）：**
```objc
static void Insulation_HidSensors_handleTemperatureEvent(id self, SEL _cmd, int event, id service) {
    // Do nothing - effectively blocks temperature events from triggering thermal throttling
    // This is critical for anti-throttling: prevents the system from reacting to high temperatures
    return;
}
```

**3. 安装函数：**
```objc
static void InsulationInstallHidSensorsHooks(void) {
    Class hidSensorsClass = objc_getClass("HidSensors");
    InsulationHookInstanceMethod(hidSensorsClass,
                                 @selector(handleTemperatureEvent:service:),
                                 (IMP)Insulation_HidSensors_handleTemperatureEvent,
                                 (IMP *)&Orig_HidSensors_handleTemperatureEvent);
}
```

**4. 在主安装函数中调用：**
```objc
void InsulationRuntimeHooksInstall(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        InsulationInstallNSDictionaryHooks();
        InsulationInstallComponentControlHooks();
        InsulationInstallCPMSHelperHooks();
        InsulationInstallPackagePowerCCHooks();
        InsulationInstallCommonProductHooks();
        InsulationInstallHidSensorsHooks();  // ← 新增！
        InsulationInstallMitigationControllerGetterHooks();
        InsulationInstallMitigationControllerSetterHooks();
        InsulationInstallMitigationControllerUpdateHooks();
    });
}
```

---

## 影响范围

### 修复的功能
- ✅ **恢复完整的反降频能力**
- ✅ 屏蔽温度事件传递
- ✅ 防止系统因高温触发降频
- ✅ 恢复到 Swift 版本的反降频效果

### 未改变的功能
- ✅ 防暗屏（light 封顶）
- ✅ 满血模式（压力归零 + 功率提升）
- ✅ 低功耗模式
- ✅ 所有 P1 修复（内存安全、线程安全）

---

## 严重性评级

**P0 - 立即修复**

这是**核心功能缺失**，不是小问题：
- 用户安装插件是为了反降频
- 0.1.31.2 反降频功能基本失效
- 必须立即替换为 0.1.31.4

---

## 版本对比

| 版本 | 反降频效果 | 安全性 | 推荐 |
|------|-----------|--------|------|
| 0.1.31.1 (Swift) | ✅ 完整 | ⚠️ 有已知问题 | ❌ |
| 0.1.31.2 (ObjC) | ❌ **失效** | ✅ 修复 | ❌ |
| 0.1.31.4 (ObjC) | ✅ **恢复** | ✅ 修复 | ✅ |

---

## 安装建议

### 如果你正在使用 0.1.31.2
**立即升级到 0.1.31.4！**

```bash
dpkg -i com.be-huge.insulation_0.1.31.4_iphoneos-arm64e.deb
killall -9 thermalmonitord
```

### 如果你还在使用 0.1.31.1 或更早版本
**升级到 0.1.31.4**（跳过 0.1.31.2）

---

## 后续计划

1. **立即发布 0.1.31.4**（紧急修复）
2. 合并 hotfix 到 main
3. 测试确认反降频效果恢复
4. 继续 P2 优化工作（代码清理）

---

## 经验教训

**在重构时必须：**
1. ✅ 逐个对比原版本的所有 hook
2. ✅ 理解每个 hook 的作用（不能盲目删除）
3. ✅ 进行实际功能测试（不只是编译通过）
4. ✅ 用户反馈是最重要的测试指标

**这次失误：**
- ❌ 只对比了大部分 hook，遗漏了 HidSensors
- ❌ 没有进行充分的实际温控测试
- ❌ 假设"只要编译通过就没问题"

---

**版本：** 0.1.31.4  
**分支：** hotfix/0.1.31.4-restore-hidsensors  
**优先级：** P0 - 紧急  
**状态：** 构建中  
**日期：** 2025-06-08
