# Insulation 架构重构方案

## 当前问题

### 1. 架构混乱
- `InsulationRuntimeHooks.m` 包含 60+ 个 hook，但 plist 只注入 `thermalmonitord`
- 这些 hook 针对 `CommonProduct`、`MitigationController` 等类，但这些类在 thermalmonitord 进程中不存在
- 导致大量死代码被链接到 dylib 中

### 2. 代码重复
- `ThermalManagerDimmingPatch.m` 和 `InsulationDictHelper.m` 重复实现了相同的功能
- 整数解析、数值替换、功率提升等逻辑出现在多个文件中

### 3. 维护困难
- 修改逻辑需要同时改动多个文件
- 不清楚哪个模块负责什么功能

---

## 重构方案

### 方案 A：单一模块（推荐，简化架构）

**目标：** 删除未使用的 `InsulationRuntimeHooks.m`，只保留 thermalmonitord 专用的 hook。

#### 文件结构

```
Sources/
├── insulationC/
│   ├── ThermalControl.m           # 系统 API（Darwin notify, SCPreferences）
│   ├── ThermalManagerHooks.m      # thermalmonitord 专用 hook（重命名）
│   └── include/Tweak.h
├── insulationShared/              # 新增：共享代码
│   ├── InsulationCommon.h         # 共享类型、常量
│   ├── InsulationCommon.m         # 共享辅助函数
│   ├── InsulationPrefsHelper.h    # 统一的偏好设置读取
│   └── InsulationPrefsHelper.m
└── insulationPrefs/               # 设置界面（保持不变）
    └── ...
```

#### 删除的文件
- ❌ `InsulationRuntimeHooks.m` (完全删除，未使用)
- ❌ `InsulationDictHelper.m` (合并到 InsulationCommon.m)
- ❌ `InsulationPowerHelper.m` (部分逻辑移到 ThermalManagerHooks.m)

#### 改动概览

**1. 创建 `InsulationCommon.m`（共享代码）**
```objc
// Sources/insulationShared/InsulationCommon.m

#import "InsulationCommon.h"

// 统一的整数解析
NSNumber *InsulationParseInt(id value) {
    if ([value isKindOfClass:[NSNumber class]]) return value;
    if ([value isKindOfClass:[NSString class]]) {
        NSString *trimmed = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([trimmed length] == 0) return nil;
        NSScanner *scanner = [NSScanner scannerWithString:trimmed];
        NSInteger parsed = 0;
        if (![scanner scanInteger:&parsed] || ![scanner isAtEnd]) return nil;
        return @(parsed);
    }
    return nil;
}

// 统一的数值替换
id InsulationReplaceNumericValue(id value, NSInteger replacement) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return @(replacement);
    }
    if ([value isKindOfClass:[NSString class]] && InsulationParseInt(value)) {
        return [@(replacement) stringValue];
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *patched = [(NSArray *)value mutableCopy];
        BOOL changed = NO;
        for (NSUInteger i = 0; i < [patched count]; i++) {
            id item = patched[i];
            if ([item isKindOfClass:[NSNumber class]]) {
                patched[i] = @(replacement);
                changed = YES;
            } else if ([item isKindOfClass:[NSString class]] && InsulationParseInt(item)) {
                patched[i] = [@(replacement) stringValue];
                changed = YES;
            }
        }
        return changed ? patched : nil;
    }
    return nil;
}

// 统一的功率提升
id InsulationRaisePowerValue(id value, NSInteger target) {
    NSNumber *number = InsulationParseInt(value);
    if (number) {
        NSInteger raised = MAX([number integerValue], target);
        return [value isKindOfClass:[NSString class]] ? [@(raised) stringValue] : @(raised);
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *patched = [(NSArray *)value mutableCopy];
        BOOL changed = NO;
        for (NSUInteger i = 0; i < [patched count]; i++) {
            id item = patched[i];
            NSNumber *itemNumber = InsulationParseInt(item);
            if (!itemNumber) continue;
            NSInteger raised = MAX([itemNumber integerValue], target);
            patched[i] = [item isKindOfClass:[NSString class]] ? [@(raised) stringValue] : @(raised);
            changed = YES;
        }
        return changed ? patched : nil;
    }
    return nil;
}

// 字符串匹配辅助
BOOL InsulationStringContainsAny(NSString *string, NSArray<NSString *> *needles) {
    NSString *lower = [string lowercaseString];
    for (NSString *needle in needles) {
        if ([lower containsString:needle]) return YES;
    }
    return NO;
}
```

**2. 创建 `InsulationPrefsHelper.m`（统一偏好设置）**
```objc
// Sources/insulationShared/InsulationPrefsHelper.m

#import "InsulationPrefsHelper.h"
#import <rootless.h>

static NSMutableDictionary *cachedPrefs = nil;
static NSTimeInterval cachedPrefsTime = -1.0;
static dispatch_queue_t prefsCacheQueue = nil;

static void InsulationEnsurePrefsQueue(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        prefsCacheQueue = dispatch_queue_create("com.be-huge.insulation.prefs", DISPATCH_QUEUE_SERIAL);
    });
}

static NSString *InsulationPrefsPath(void) {
    return rootlessPath(@"/var/mobile/Library/Preferences/com.be-huge.insulation-prefs.plist");
}

void InsulationReloadPrefs(void) {
    InsulationEnsurePrefsQueue();
    dispatch_sync(prefsCacheQueue, ^{
        NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:InsulationPrefsPath()];
        cachedPrefs = prefs ?: [NSMutableDictionary dictionary];
        cachedPrefsTime = [NSDate timeIntervalSinceReferenceDate];
    });
}

static BOOL InsulationPrefsBoolValue(NSString *key, BOOL defaultValue) {
    InsulationEnsurePrefsQueue();
    
    __block BOOL shouldRefresh = NO;
    dispatch_sync(prefsCacheQueue, ^{
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (!cachedPrefs || cachedPrefsTime < 0 || now - cachedPrefsTime >= 0.5) {
            shouldRefresh = YES;
        }
    });
    
    if (shouldRefresh) {
        InsulationReloadPrefs();
    }
    
    __block BOOL result = defaultValue;
    dispatch_sync(prefsCacheQueue, ^{
        id value = [cachedPrefs objectForKey:key];
        if ([value isKindOfClass:[NSNumber class]]) {
            result = [value boolValue];
        } else if ([value isKindOfClass:[NSString class]]) {
            NSString *lower = [(NSString *)value lowercaseString];
            result = [@[@"1", @"true", @"yes", @"on"] containsObject:lower];
        }
    });
    
    return result;
}

static NSString *InsulationPrefsStringValue(NSString *key, NSString *defaultValue) {
    InsulationEnsurePrefsQueue();
    
    __block BOOL shouldRefresh = NO;
    dispatch_sync(prefsCacheQueue, ^{
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (!cachedPrefs || cachedPrefsTime < 0 || now - cachedPrefsTime >= 0.5) {
            shouldRefresh = YES;
        }
    });
    
    if (shouldRefresh) {
        InsulationReloadPrefs();
    }
    
    __block NSString *result = defaultValue;
    dispatch_sync(prefsCacheQueue, ^{
        id value = [cachedPrefs objectForKey:key];
        if ([value isKindOfClass:[NSString class]]) {
            result = value;
        }
    });
    
    return result;
}

// 公开 API
BOOL InsulationPreventDimmingEnabled(void) {
    return InsulationPrefsBoolValue(@"thermalPreventDimmingEnabled", NO);
}

NSString *InsulationPowerMode(void) {
    NSString *mode = InsulationPrefsStringValue(@"thermalPowerMode", @"off");
    if ([mode isEqualToString:@"fullPower"] || 
        [mode isEqualToString:@"lowPower"] || 
        [mode isEqualToString:@"off"]) {
        return mode;
    }
    return @"off";
}

BOOL InsulationFullPowerModeEnabled(void) {
    return [InsulationPowerMode() isEqualToString:@"fullPower"];
}

BOOL InsulationLowPowerModeEnabled(void) {
    return [InsulationPowerMode() isEqualToString:@"lowPower"];
}
```

**3. 简化 `ThermalManagerHooks.m`（重命名后）**
```objc
// Sources/insulationC/ThermalManagerHooks.m (重命名自 ThermalManagerDimmingPatch.m)

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "../insulationShared/InsulationCommon.h"
#import "../insulationShared/InsulationPrefsHelper.h"
#import "include/Tweak.h"

// 只保留 thermalmonitord 专用的 hook 逻辑
// 删除所有 CommonProduct、MitigationController 相关代码（已确认在 thermalmonitord 中不存在）
// 使用共享的 InsulationCommon 函数
```

**4. 更新 Makefile**
```makefile
# 删除 InsulationRuntimeHooks.m
# 添加 insulationShared/ 目录
OBJC_FILES = \
    Sources/insulationObjC/TweakInit.m

C_FILES = \
    Sources/insulationC/ThermalControl.m \
    Sources/insulationC/ThermalManagerHooks.m \
    Sources/insulationShared/InsulationCommon.m \
    Sources/insulationShared/InsulationPrefsHelper.m
```

#### 优点
- ✅ 删除 60+ 个未使用的 hook（减少二进制体积 ~50%）
- ✅ 消除代码重复（5+ 个重复函数合并）
- ✅ 清晰的职责划分
- ✅ 线程安全的偏好设置缓存
- ✅ 易于维护和测试

#### 缺点
- ⚠️ 需要重构现有代码（~2-3 小时工作量）
- ⚠️ 需要完整测试（防暗屏、满血、低功耗三种模式）

---

### 方案 B：双模块分离（保留扩展性）

**目标：** 保留 `InsulationRuntimeHooks.m`，但拆分成独立的 dylib，为未来扩展做准备。

#### 文件结构

```
Sources/
├── insulationC/              # thermalmonitord 专用
│   ├── ThermalControl.m
│   └── ThermalManagerHooks.m
├── insulationObjC/           # 未来可能用于其他进程（目前未启用）
│   ├── InsulationRuntimeHooks.m
│   └── InsulationPowerHelper.m
├── insulationShared/         # 共享代码
│   ├── InsulationCommon.m
│   └── InsulationPrefsHelper.m
└── insulationPrefs/
    └── ...
```

#### 构建两个 dylib
```makefile
# Makefile

# 主 dylib：thermalmonitord 专用
THEOS_PACKAGE_NAME = com.be-huge.insulation
TWEAK_NAME = insulation
insulation_FILES = \
    Sources/insulationC/ThermalControl.m \
    Sources/insulationC/ThermalManagerHooks.m \
    Sources/insulationShared/InsulationCommon.m \
    Sources/insulationShared/InsulationPrefsHelper.m \
    Sources/insulationObjC/TweakInit.m
insulation_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries
insulation_FILTER = Executables = ( "thermalmonitord" );

# 扩展 dylib：未来用于其他进程（暂不启用）
# TWEAK_NAME += insulation-runtime
# insulation-runtime_FILES = \
#     Sources/insulationObjC/InsulationRuntimeHooks.m \
#     Sources/insulationObjC/InsulationPowerHelper.m \
#     Sources/insulationShared/InsulationCommon.m \
#     Sources/insulationShared/InsulationPrefsHelper.m
# insulation-runtime_FILTER = Executables = ( "SpringBoard", "backboardd" );
```

#### plist 配置
```xml
<!-- insulation.plist -->
{
  Filter = {
    Executables = ( "thermalmonitord" );
  };
}

<!-- insulation-runtime.plist (未来使用) -->
<!-- {
  Filter = {
    Executables = ( "SpringBoard", "backboardd" );
  };
} -->
```

#### 优点
- ✅ 保留未来扩展可能性
- ✅ 清晰的模块边界
- ✅ 共享代码避免重复

#### 缺点
- ⚠️ 复杂度更高
- ⚠️ 目前 InsulationRuntimeHooks 仍未使用（浪费维护成本）
- ⚠️ 需要维护两个 dylib 的构建配置

---

## 推荐方案

**推荐：方案 A（单一模块）**

理由：
1. **当前需求明确**：只需要 thermalmonitord hook
2. **YAGNI 原则**：不需要为"可能的未来需求"增加复杂度
3. **维护成本低**：单一模块更易理解和修改
4. **性能更好**：更小的二进制体积，更快的加载速度

如果未来真的需要 hook 其他进程（如 SpringBoard），可以：
- 从 git 历史恢复 InsulationRuntimeHooks.m
- 或者基于共享代码重新实现

---

## 实施步骤（方案 A）

### 阶段 1：创建共享代码（1 小时）
1. ✅ 创建 `insulationShared/` 目录
2. ✅ 实现 `InsulationCommon.m`（合并重复函数）
3. ✅ 实现 `InsulationPrefsHelper.m`（统一偏好设置）
4. ✅ 编写单元测试（验证共享函数正确性）

### 阶段 2：重构 ThermalManagerHooks（1 小时）
1. ✅ 重命名 `ThermalManagerDimmingPatch.m` → `ThermalManagerHooks.m`
2. ✅ 删除重复代码，使用 `InsulationCommon` 函数
3. ✅ 删除重复的偏好设置代码，使用 `InsulationPrefsHelper`
4. ✅ 应用 P1 patch（内存管理修复）

### 阶段 3：删除未使用代码（30 分钟）
1. ✅ 删除 `InsulationRuntimeHooks.m`
2. ✅ 删除 `InsulationDictHelper.m`
3. ✅ 删除 `InsulationPowerHelper.m`
4. ✅ 更新 Makefile

### 阶段 4：测试（1 小时）
1. ✅ 编译并打包
2. ✅ 在测试设备上验证三种模式：
   - 防暗屏（light 封顶）
   - 满血模式（压力归零 + 功率提升）
   - 低功耗（CPU 限制）
3. ✅ 验证 warmup guard（前 6 秒延迟）
4. ✅ 验证偏好设置切换

---

## 风险评估

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| 重构引入 bug | 中 | 高 | 完整测试 + 保留 git 回滚点 |
| 性能回退 | 低 | 中 | 基准测试（before/after） |
| 功能缺失 | 低 | 高 | 逐功能验证 + 用户反馈 |

---

## 总结

**方案 A（推荐）**
- 工作量：~3 小时
- 减少代码量：~40%
- 二进制体积：减少 ~50%
- 维护成本：显著降低

**方案 B**
- 工作量：~4 小时
- 减少代码量：~30%
- 二进制体积：减少 ~30%
- 维护成本：略有降低

建议采用**方案 A**，立即实施阶段 1-3，在下个版本（0.1.32）发布。
