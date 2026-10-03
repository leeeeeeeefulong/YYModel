# F1–F4 修复验收（2026-10-04）

基于 2.1.8 / 518c405a51ab46cb6e6a39e22a36ab9d9788f78c 的新修复提交。仅改动 YYJSONDecoder.swift 的数值转换；OC 实现未修改。修复提交推送 master，不移动 2.1.8 标签，不宣称旧标签已包含新代码。

## 行为与根因

- F1：UTF-8 ASCII 语法解析后规范化指数前导零。`123e-000001` → 12，`1e-000000` → 1；Int64 越界字符串 `9223372036854775808e-000000` 被拒绝。
- F2：十进制按有效数字、十六进制按有效位执行向零截断及整数范围检查，避免 Double 中介。`0x20000000000001p0` → 9007199254740993；`-0x8000000000000001p0` 的 Int64 越界被拒绝；UInt64 最大值及十六进制小数正常转换。Decimal 十六进制输入使用 Foundation 十进制运算，保留其有限精度与范围。
- F3：数字语法只接受 ASCII 数字/符号，拒绝数字后附 U+0301 或 U+FE0F 的 Unicode 组合字符。
- F4：零系数在指数范围判断前归一化，`0e+999999` → 0。极小非零数转整数仍向零截断。

## 新鲜验证结果

失败回执先于实现保存；没有新增实现后单元测试，没有改动已有断言期望。追加 50 个公开 API E2E 组合也先于库修改完成，覆盖超长系数与抵消指数、十六进制小数和二进制移位等场景。

| 检查 | macOS arm64 | iOS 26.5 arm64 模拟器 |
|---|---:|---:|
| 原有数值案例（修复前） | 1,412 / 1,742，330 失败 | 前一轮相同结果 |
| 扩展数值案例（修复前） | 1,450 / 1,792，342 失败 | — |
| 扩展数值案例（修复后） | 1,792 / 1,792 | 1,792 / 1,792 |
| 天气验收判定 | 20 / 20 | 20 / 20 |

两平台数值实际结果一致。天气使用归属清楚的 Open-Meteo 固定快照；逐字段、逐数组元素比较共同业务模型，并核对 OC keyPath 导出往返。20 个判定包括原生 JSONDecoder 对 dirty/sparse 的两项预期拒绝；并非所有引擎都成功解码脏数据。

已有独立回归：38/38 契约复现、Swift release 16/16、Demo 84/84（构建无警告）、Framework XCTest 27/27、Swift 6 模块编译通过。不依赖正式业务 App。

## 性能证据

预热 5 次，每次结果被消费，普通载荷每轮 100 次，大载荷每轮 8 次；7 轮计时。完整天气测试的两个平台顺序运行。为核对单轮波动，macOS 上另外对同一 Swift 天气载荷按 before/after/after/before 顺序运行两轮，每次仍采集 7 个样本：

| Swift YYJSONDecoder，ms/次中位数 | 2.1.8 | 修复后 |
|---|---:|---:|
| 干净天气数据 | 0.8074 | 0.8148 |
| 脏天气数据 | 4.6566 | 4.6174 |

这组样本未显示明显性能回退，也不足以证明普遍提速。完整天气/大载荷各轮数据和源文件 SHA 在 [JSON 回执](receipts/numeric-fix-20261004.json) 中；[逐项数值实际结果](receipts/numeric-fix-results.json) 保留全部 1,792 个输入、期望、实际和判定。

没有锁定 CPU 频率、温度和后台负载；OC/Swift 模型表示不同；未测实体 iPhone、iOS 27、峰值内存或长期泄漏。既有契约复现脚本的微基准与其他正确性任务并行，未用于本次性能结论。

## 复跑与版本身份

从包含修复提交的 checkout 按 README 运行，原版基准固定 c7df27538c043e5f54f5b6605958544bb529892f：

```sh
python3 Validation/run.py --original-source /path/to/original/YYModel --output /tmp/yymodel-fixed-mac
python3 Validation/run.py --original-source /path/to/original/YYModel --simulator SIMULATOR_UUID --output /tmp/yymodel-fixed-ios
swift test -c release
make -C Demo
xcodebuild test -project Framework/YYModel.xcodeproj -scheme YYModel -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' IPHONEOS_DEPLOYMENT_TARGET=13.0 CODE_SIGNING_ALLOWED=NO
```

命令依次运行；两个 Validation 命令应退出 0。release 2.1.8 本身仍是修复前基准，不能用同一标签重复发布来替代本次新提交。输入、源码 SHA 和计时环境必须随复跑保存。
