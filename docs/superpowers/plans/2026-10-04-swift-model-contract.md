# Swift YYModel Implementation Plan

> 执行方式：当前会话顺序执行并在各阶段审查；不启动子代理。按用户要求使用先行失败清单与公开 API E2E，不后补单元测试。

**Goal:** 普通 Swift struct 自动合成 Codable，同时提供 YYModel 式快捷入口、映射、钩子、多态与对称导出。

**Architecture:** 原生 Codable 容器适配器 + 已有精确叶子转换；声明式配置元数据缓存；enum 注册表解决 struct 载荷分派。保持旧 YYJSONDecoder 和 OC API，按字段处理容错，避免根对象两次初始化。

**Tech Stack:** Swift 5.9+ / Swift 6、Foundation、Objective-C、Python 3；macOS arm64、iOS 26.5 Simulator。

**Spec:** `docs/superpowers/specs/2026-10-04-swift-model-contract.md`

## Global Constraints

- 普通 struct；不继承 NSObject；常规模型不手写 init(from:) / encode(to:)。
- iOS 26.5，组件内固定公开数据；不使用正式业务 App。
- 先 E2E 和失败场景，再库代码；不增加后补单元测试。
- 旧 API 与发布 tag 2.1.9 保持；新增功能 unreleased。
- 构建/正确性与顺序性能测量分开，保留所有样本。

## Tasks

执行回执：`Validation/RESULTS-swift-model.md`。OC 性能对原版仍存在较慢样本，文档明确列出，不能把已完成本计划理解为全场景性能优于原版。

### 1. 固定失败验收与 OC 日期边界

- [x] 写 `Validation/SwiftModelE2E.swift` 和 `Validation/run_swift_model.py`，实现 spec 1–11 的公开模型/路径判定，不复制生产转换逻辑。
- [x] 写 `Validation/DateContractE2E.m`：有符号秒/毫秒 Number/String、非有限数与正常日期字面期望。
- [x] 对 2.1.9 运行，保存缺失 Swift API 与 OC 已知边界的失败回执。
- [x] 修复 `NSObject+YYModel.m` 日期输入符号/有限值；复跑新日期 E2E + 既有 OC 62 项边界及 27 XCTest；单独提交。

### 2. 完整 Swift 公共合同

- [x] 创建 spec 列出的五个 Swift 文件；配置/路径/缓存和便捷/throwing API。
- [x] 原生 Decoder 容器按字段执行别名、KeyPath、过滤、必填、缺失值、数值日期转换；嵌套模型与 hook 自动递归。
- [x] 原生 Encoder 容器镜像映射，显式 Date 线格式，检测路径冲突，自动字典后执行 hook。
- [x] 注册式关联值 enum 自动 Codable，未知 discriminator 拒绝。
- [x] 新 E2E 全部通过；既有 Swift 16、数值 1792、边界 62、Swift 6 严格编译通过。

### 3. 数据性能与独立分发

- [x] 复用天气快照及 Python oracle，普通 Codable / YYModelCodable / 配置 YYModelCodable 分开验证、计时。
- [x] macOS 与模拟器顺序测完整样本；Data/object/encode 不混比；脏数据 native 拒绝不算吞吐。
- [x] 增加 CocoaPods ObjC/Swift subspec，默认仍组合；确认 Swift-only 不依赖 OC 源码，SPM 分别构建。
- [x] 更新公开文档和机器可读回执；审查逻辑、Swift 6、公共 API 与源码身份。
- [x] 完成后提交、推送，并确认 2.1.9 tag 未移动；未完成项不写成完成。
