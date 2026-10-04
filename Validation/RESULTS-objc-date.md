# OC 日期与工程配置复审

对应未发布源码，不移动 2.1.9 tag。先写公开 API E2E，16 个日期场景在旧实现中 8 个失败，再修复，16/16 通过。负数毫秒 Number 按绝对值阈值处理；字符串保留原版日期长度分派后支持有符号/空白的 10/13 位时间戳，接受零值；NaN/Infinity 不生成 NSDate。

原版格式、RFC/asctime 和正常数字对照仍通过。已有边界 62/62；组件 Framework 原版 XCTest 27/27，iOS 26.5 Simulator。工程部署目标由 8.0 改为与 Pod 一致的 11.0，默认命令可构建，不再找已移除的 libarclite。当前 SDK 对最低目标 11.0 仍提示支持范围 warning；保持最低系统兼容声明，没有以零警告掩盖它。

回执：`receipts/objc-date-20261004.json`。直接复跑（在仓库根目录）：

```sh
clang -O2 -fobjc-arc -framework Foundation -I YYModel YYModel/*.m Validation/DateContractE2E.m -o /tmp/yy-date-e2e
/tmp/yy-date-e2e /tmp/yy-date-results.json
xcodebuild test -project Framework/YYModel.xcodeproj -scheme YYModel -configuration Release -destination 'platform=iOS Simulator,id=<booted-UUID>'
```

这是确认上述边界与契约的回执，不表示已证明所有未来数据都没有缺陷。Swift 的完整模型能力在后续独立改动交付。
