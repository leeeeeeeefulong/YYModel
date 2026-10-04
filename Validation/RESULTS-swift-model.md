# Swift YYModel 交付复审与性能回执

## 交付目标与版本边界

此次交付补齐此前一直缺失的 Swift 模型层：普通 struct 自动合成 Codable，同时提供 YYModel 风格 JSON/字典/数组入口、Mapper、多 key、KeyPath、过滤、默认值/必填、转换钩子、多态载荷及导出。无需常规模型逐个手写 init(from:)。

源码为 master 的 **Unreleased** 改动。发布 tag 2.1.9 保持不动，新接口不能冒称已在 2.1.9 发版。OC 与 Swift 共享仓库和版本管理，但 SPM 产品、CocoaPods subspec 已可分别选择。CocoaPods 默认组合保持兼容；Swift-only 不依赖组件 OC 源码。

Swift 模型合同与完整示例见 `../docs/SWIFT-MODEL.md`。OC 日期改动独立提交，详见 `RESULTS-objc-date.md`。既有 2.1.9 四类语言调用交付报告仍是历史版本证据；本回执补充新 Swift 模型路径及最新 OC 对照。

## 已确认与未验证

- 已确认：原来纯 Swift 发布模块仅有 YYJSONDecoder 容错，Bridge 未进入发布产品。此次新增完整声明式模型接口，旧解码入口逻辑仅作内部访问范围调整。
- 已确认：新的快捷入口会执行根和嵌套模型配置，脏字段局部转换，模型不进行完整初始化重试；传统 YYJSONDecoder 的原生优先/失败后整体容错机制保留。
- 已确认：iOS 基准为 26.5 Simulator；macOS 和模拟器运行在 Apple M1 Max，Swift -O / OC -O2。
- 未验证：iOS 27、新的其他工具链、物理 iPhone 时延。模拟器的 iPhone 13 mini 名称不等于 A15 实机。
- 合理推断：普通自动合成模型只会增加适配开销，原生 Codable 仍可能更快；脏数据路径避免整体重试可以获益。具体范围以本次样本为准。

## 验收方法

先写失败清单和公开 API E2E，再写实现。没有新增后补单元测试，也没有使用或改动任何业务 App。所有数据、模型和脚本位于组件仓库。

模型合同检查覆盖字符串/Data/已解析对象、别名顺序/null、字面点号键、多层路径、过滤、required/default、整数/Decimal、嵌套模型及拒绝传播、初始化/钩子次数、日期表与单位、Foundation 线格式、enum、冲突导出、错误路径、失败容器的索引及并发缓存。

天气输入为已有 Open-Meteo 固定快照。3 城市、96 小时、4 天；派生 clean/dirty/nullable/sparse/large。large 为 96 城市、9,216 小时。网络、文件读取、已解析对象的初始 JSON 解析和导出阶段的初始模型解析不计时。

正确性门禁核对完整业务模型及导出内容，不用 checksum 替代字段验证。原生拒绝 dirty/sparse 是合法结果，不把失败操作当作吞吐成绩。每条成功性能路径两次执行，各 7 样本，共 14 样本；小输入每样本 100 次，large 每样本 3 次。表格为每次操作中位数。

## 验收结果

| 检查 | macOS | iOS 26.5 Simulator |
|---|---:|---:|
| 新 Swift 合同 | 56/56 | 56/56 |
| OC 日期合同 | 16/16 | 16/16 |
| 既有边界 | 62/62 | 62/62 |
| 既有跨语言完整模型门禁 | 183/183 | 183/183 |
| 新数值 + 天气门禁 | 1,837/1,837 | 1,837/1,837 |

另有：混合链接新数值/天气门禁 1,837/1,837；独立 SPM 公开模块消费与混合调用 59/59；原有 Swift 回归 16/16、Demo 84/84、Framework 原版 XCTest 27/27。Pod 的 Swift-only、OC-only、默认组合均独立构建验证通过。构建 warning 如后文说明，并未宣称所有构建零 warning。

## Swift 模型效率

### macOS：毫秒/次

| 数据 | 原生解码 | 旧 YY | 新模型 | Mapper | 字典钩子 | 已解析对象 | 新导出 | 原生导出 | 导出钩子 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| clean | 0.960 | 0.874 | 1.095 | 1.063 | 5.351 | 5.032 | 1.631 | 1.423 | 6.148 |
| dirty | 拒绝 | 5.540 | 1.220 | 1.306 | 5.372 | 4.888 | 1.725 | 1.498 | 5.584 |
| nullable | 0.832 | 0.937 | 1.051 | 1.011 | 6.129 | 5.133 | 1.568 | 1.601 | 5.945 |
| sparse | 拒绝 | 3.657 | 0.904 | 0.949 | 3.852 | 3.222 | 1.064 | 0.991 | 4.121 |
| large | 29.674 | 31.088 | 32.930 | 35.654 | 180.937 | 154.447 | 50.580 | 47.436 | 186.094 |

### iOS：毫秒/次

| 数据 | 原生解码 | 旧 YY | 新模型 | Mapper | 字典钩子 | 已解析对象 | 新导出 | 原生导出 | 导出钩子 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| clean | 0.914 | 0.852 | 1.091 | 1.089 | 4.688 | 4.219 | 1.418 | 1.294 | 5.660 |
| dirty | 拒绝 | 4.376 | 1.054 | 1.245 | 4.743 | 4.430 | 1.414 | 1.217 | 5.808 |
| nullable | 0.810 | 0.851 | 0.980 | 1.055 | 4.462 | 3.927 | 1.384 | 1.357 | 5.504 |
| sparse | 拒绝 | 3.275 | 0.790 | 0.887 | 3.207 | 2.777 | 0.967 | 0.912 | 3.900 |
| large | 25.049 | 25.804 | 31.830 | 32.876 | 135.715 | 126.448 | 45.219 | 44.940 | 173.284 |

### mixed-iOS：毫秒/次

| 数据 | 原生解码 | 旧 YY | 新模型 | Mapper | 字典钩子 | 已解析对象 | 新导出 | 原生导出 | 导出钩子 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| clean | 0.825 | 0.810 | 1.022 | 0.928 | 4.740 | 4.151 | 1.363 | 1.363 | 5.571 |
| dirty | 拒绝 | 4.186 | 1.238 | 1.203 | 4.706 | 3.989 | 1.413 | 1.295 | 5.625 |
| nullable | 0.904 | 0.886 | 0.999 | 1.028 | 4.954 | 4.241 | 1.385 | 1.339 | 5.171 |
| sparse | 拒绝 | 3.213 | 0.878 | 0.806 | 3.432 | 2.786 | 0.999 | 0.943 | 3.783 |
| large | 27.094 | 25.948 | 35.659 | 35.821 | 146.803 | 127.277 | 47.531 | 42.998 | 165.419 |

`model` 是普通 YYModelCodable；`mapped` 使用 KeyPath 把 payload.locations 映射为顶层 locations；`hooked` 使用字典预处理和解析后校验；`object` 接收已解析对象；`encode` 为 YYModel JSONData 导出，`nativeEncode` 为同 DTO 的 JSONEncoder；`hookEncode` 在自动导出后修改字典。Mapper 型与标准 DTO 的内存形状有区别，只做能力/成本展示；native/model/legacy 使用同一 Envelope DTO，才是同模型对照。

字典钩子会按需解析一个本次 Data 的 Foundation 快照，嵌套路径共享它。willTransform 返回字典后需要从字典构造字段，因而成本高于无钩子路径。transformTo 需要物化自动字典并验证导出值。已解析对象路径避免重复 JSON 编码，但 Swift 对 Any/NSNumber 的转换成本可能高于原生 Data 解码；不能声称它必然更快。

## 混合编译与 OC 原版对照

### 新 Swift 相邻配对（iOS，ABBA）

| 对照 | 左中位数 ms | 右中位数 ms | 右/左 |
|---|---:|---:|---:|
| native/model:clean | 0.846 | 1.090 | 1.288 |
| legacy/model:dirty | 4.683 | 1.215 | 0.259 |
| legacy/model:sparse | 3.177 | 0.772 | 0.243 |
| mixed:model:clean | 1.169 | 1.161 | 0.993 |
| mixed:model:dirty | 1.364 | 1.207 | 0.885 |
| mixed:model:large | 32.014 | 34.612 | 1.081 |
| mixed:object:clean | 3.851 | 3.856 | 1.001 |
| mixed:encode:clean | 1.503 | 1.380 | 0.918 |

### 最新 OC 对 ibireme（同模型 ABBA）

| 入口/数据 | macOS 新版/原版 | iOS 新版/原版 |
|---|---:|---:|
| data:clean | 0.937 | 1.027 |
| data:dirty | 0.973 | 1.184 |
| data:nullable | 0.924 | 0.996 |
| data:sparse | 1.107 | 0.948 |
| data:large | 1.057 | 0.979 |
| object:clean | 0.929 | 1.008 |
| object:dirty | 0.973 | 1.026 |
| object:large | 0.977 | 1.061 |
| encode:clean | 0.979 | 0.989 |
| encode:large | 0.936 | 0.998 |

比值小于 1 表示右侧更快。OC 各入口并非全面比原版更快；是否可接受应依据此表及样本范围，而不是单次时延。Swift 配对中 native/model 是标准数据的能力开销，legacy/model 是脏/缺失数据的收益；混合链接配对只改变链接的组件。

纯 Swift 和混合链接二进制解析同一 Swift DTO；混合链接不额外解析一份 OC 模型。它衡量同时链接 OC 组件的影响。实际同时调用两套公开 API 由独立消费 E2E 验证；旧接口的 OC/Swift 调用对照由固定 ibireme 基线的 ABBA 组复测，属于另一类工作量，不能将两次独立解析包装成单次解析。

OC 与 Swift 天气模型虽然导出同一业务结果，但 OC 保留 Foundation 容器，Swift 使用强类型可选数值数组；不能据此直接宣布其中一个语言的核心反射更快。OC 比原版的判断使用同一 OC 模型、同一入口和同一输入。

## 保留的边界与维护成本

- 配置缓存不可变。带业务捕获状态的钩子由调用方保证并发安全；模型没有被自动声明为 Sendable。
- Mapper 使用 CodingKeys 的键名，无法猜测写错的配置。关键字段应声明 required，避免允许缺失的零值被当成正确业务值。
- Swift 属性声明默认值不等于解码默认值，使用 defaultValues；Data 使用 Codable Base64 线格式，不等同 OC NSData 的 UTF-8 转换。
- Date automatic 是单位启发式；小毫秒及极大秒值应明确策略。嵌套 YYModelCodable 模型使用自己的策略；enum 的日期与字段配置声明在载荷模型上，不接受无效根配置。
- 直接使用原生 JSONDecoder/JSONEncoder 或旧 YYJSONDecoder 处理普通 struct，不会自动应用 YYModel 配置。新模型应使用快捷接口或 YYModelJSON。
- struct 无 OC 继承和对象身份；分派通过 enum，值复制通过 Swift。没有假装提供任意 KVC 写入、OC secure archive 或对象原地 setter 的同等能力。
- Swift 适配层复用已有标量转换，独立 Decoder/Encoder/JSON 值/配置/多态文件分工。两条公开路线保留兼容，但文档须持续明确入口差别。
- 当前 SDK 对最低 iOS 11 的工程配置仍给出范围 warning；CocoaPods 验证允许这些 SDK/工具链 warning。严格 Swift 源码编译没有 warning。没有以 0 warning 宣称全部环境。

## 复跑

在仓库根目录执行；模拟器使用已启动的 iOS 26.5 UUID。性能脚本顺序运行，禁止和构建并行：

```sh
python3 Validation/run_swift_model.py --output /tmp/yy-model-contract
python3 Validation/run_swift_model_import.py --output /tmp/yy-model-import
python3 Validation/run_swift_model_data.py --output /tmp/yy-model-data --iterations 100
python3 Validation/run_swift_model.py --simulator <UUID> --output /tmp/yy-model-contract-ios
python3 Validation/run_swift_model_data.py --simulator <UUID> --output /tmp/yy-model-data-ios --iterations 100
python3 Validation/run_swift_model_data.py --mixed --simulator <UUID> --output /tmp/yy-model-data-mixed --iterations 100
python3 Validation/run_swift_model_paired.py --swift-output /tmp/yy-model-data-ios --mixed-output /tmp/yy-model-data-mixed --output /tmp/yy-model-paired
swift test -c release
pod lib lint YYModel2.podspec --subspec=Swift --platforms=ios --swift-version=6.0 --allow-warnings --skip-tests
pod lib lint YYModel2.podspec --subspec=ObjC --platforms=ios --allow-warnings --skip-tests
```

OC 原版对照将 ibireme 固定提交 c7df27538c043e5f54f5b6605958544bb529892f 的 YYModel 归档解压到独立目录后：

```sh
python3 Validation/run_delivery.py --original-root <归档根目录> --output /tmp/yy-interop --no-benchmark
python3 Validation/run_paired.py --delivery-output /tmp/yy-interop
# iOS 26.5 在第一条命令增加 --simulator <UUID>，使用另一个输出目录。
```

机器可读回执和全部样本：`receipts/swift-model-20261004.json`、`receipts/swift-model-measurements.csv`。逐条 numeric 实际值保存在 `receipts/swift-model-numeric-20261004.json`；完整运行时输出可用上述命令生成。性能结论限定于这些数据和环境，不作所有未来输入无缺陷或全面更快的保证。
