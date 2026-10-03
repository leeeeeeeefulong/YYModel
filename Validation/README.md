# 独立公开 API 验证

本目录用于 YYModel/YYModelSwift 组件验收，不依赖任何业务 App、账号、私有数据或 CocoaPods 工程。只编译库源码和公开 API 可执行程序，不修改库实现。

先阅读 [失败场景清单](FAILURE-MODES.md)。数值期望使用独立的 Python 任意精度整数运算与 ASCII 语法定义；天气期望直接从 JSON 计算。发现失败时保留完整输入与结果，进程非零退出；不能用“成功运行程序”代替断言通过。

## 数据与模型

- 公开天气快照：[Open-Meteo Weather Forecast API](https://open-meteo.com/en/docs)。三城市（上海、纽约、东京），每个城市 96 小时预测，包含实时天气、小时/日数组、单位字典、小数、负数等。
- 数据归属：Weather data by [Open-Meteo](https://open-meteo.com/)，许可 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。原始响应及获取 URL、时间、SHA-256 分别保存在 `fixtures/weather-api.json` 和 `fixtures/weather-source.json`。
- 默认离线；网络传输不计入解析性能。快照更新应同时更新来源信息，再重新建立测试基准。
- 自构造五层请求/载荷/城市/预测/数组结构，覆盖 OC keyPath 映射、容器泛型及 JSON 往返。
- 五组固定载荷：clean、dirty（数字字符串等容错）、nullable、sparse（缺字段）、large（96 城市）。large 是明确标记的合成扩容，不宣称来自一次 API 请求。
- Swift 模型是普通 Decodable，OC 模型走 yy_model；两者保留各自接口契约，比较共同业务投影。

## 运行

需要 macOS、Xcode 命令行工具及 Python 3；没有额外 Python 依赖。默认检查当前仓库源码：

```sh
python3 Validation/run.py --output Validation/artifacts/macos
```

加入 ibireme 原版 OC 源码对照（本仓库完整 Git 历史中包含该提交）：

```sh
mkdir -p /tmp/YYModel-original
git archive c7df27538c043e5f54f5b6605958544bb529892f | tar -x -C /tmp/YYModel-original
python3 Validation/run.py --original-source /tmp/YYModel-original/YYModel --output Validation/artifacts/macos
```

也可单独提供原版源码目录。浅克隆/ZIP 没有历史对象时，先获取 ibireme 指定提交，不要把其他版本当作基准。`--source-root` 可指定待审源码快照，从而与本测试包解耦。

只运行指定部分：

```sh
python3 Validation/run.py --only numeric
python3 Validation/run.py --only weather --iterations 100
python3 Validation/run.py --only weather --no-benchmark
```

在已经启动的 arm64 iOS 模拟器上运行，无需正式 App 或测试宿主：

```sh
xcrun simctl list devices booted
python3 Validation/run.py --simulator SIMULATOR_UUID --original-source /tmp/YYModel-original/YYModel --output Validation/artifacts/ios
```

退出码：0 表示所选检查通过，1 表示断言失败。已发布的 2.1.8 数值边界检查包含已确认失败，预期整体返回 1；本次 F1–F4 修复后的源码应整体返回 0。天气检查会独立完成并输出结果。

## 测量方法与结果文件

先对所有载荷和引擎逐字段/逐数组元素验证共同业务模型（包含元素顺序、字典键和值、null），并验证解析数量、数值汇总、keyPath 导出及 OC 往返，再计时。OC 原始 NSArray 中的数字字符串按明确的业务数值类型规范化，不宣称库改变了其原始元素类型。原生 JSONDecoder 对 dirty/sparse 的拒绝是预期结果，不将失败解码速度纳入比较。

- OC `-O2`、Swift `-O`；输入 Data 在计时前读入，测量 Data → Model。
- 每种载荷/引擎预热 5 次，7 轮采样；普通载荷每轮默认 100 次，大载荷每轮 8 次。
- 每次消费解析结果，并通过 autoreleasepool 释放临时对象。
- 输出完整样本、中位数、最小值、最大值、输入字节数、源码哈希、编译器和运行环境。
- 引擎测量为顺序运行，未锁定 CPU 频率或温度；小幅差异应多次受控测量，不能据单轮宣称普遍更快。模型表示不同，也不能把 OC/Swift 比值当作纯引擎效率。
- 性能任务不要与其他编译或基准并行；可用 `--no-benchmark` 单独执行正确性检查。

`artifacts/` 默认 Git 忽略，可用于本地回执；审查时应保存具体运行目录：

- `acceptance.json`：总体结论。
- `numeric-cases.json`、`numeric-results.json`、`numeric-summary.json`：完整数值输入、期望、实际结果、失败分类。
- `weather-*.json`、`weather-expected.json`：合成载荷、固定字节和业务投影期望。
- `correctness-*.json`、`weather-results.json`：正确性与性能数据。
- `benchmark-*.json`：原始计时样本及消费结果。
- `environment.json`、编译/执行日志：源码身份与环境证据。

发布组件的回执应引用这里的输入、命令和结果。正式业务 App 的构建状态不作为本组件验收标准。

本次修复的运行回执见 [RESULTS-numeric-fix.md](RESULTS-numeric-fix.md)；[2.1.8 历史回执](RESULTS-2.1.8.md) 保留修复前结论。
