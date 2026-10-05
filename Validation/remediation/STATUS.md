# 修复工程最终核验（2026-10-05，未发布工作区）

> **2026-10-06 补充（`fix/swift-phase2-remediation` 分支）**：第二阶段缺陷全量修复
> （P0-1/P1-1~P1-6/P2-1~P2-5/P3-1~P3-6、C② 契约、D3 顶层 lossy、P2-3/P2-4 与文档收尾）
> 按 17 项逐项提交完成。各阶段验收一并更新：
> 公开 API E2E **555/555**、`swift test` **108/108**、Swift5/6 严格语言编译及四个
> 平台下限 typecheck 全部通过（`verify_platforms.py`）。新增：
> P2-4 `decodeWithReport` 抛错时把已吸收的报告挂在 `DecodingError` 的
> `underlyingError` 上（`YYModelLossReport.attached(from:)` 可取回）；
> D3 顶层 `decodeLossyArray`；C② 六份新契约 expectation（黑白名单、多态、transform、
> string→number、lossy、Presence）。性能门禁未重测；G5/G7/远端 CI 仍待完成。

## 结论与验收边界

本轮已复现的组合、字段、数值和编码协议缺陷均已修复。R-1字段解析、R-2直接树导出/
集中标量投影、R-3能力探测和整数路由均已实施。原22项登记逐项处置，五类组合新增K-01–05；
误报与未复现的旧平台推断保留明确区别。

不能宣称所有平台绝对无问题：G5真实旧OS运行及G7外部人员签署尚未完成，远端CI尚未执行。
本轮没有提交、推送、发布或代签。

## 同一份最终源码的可核验结果

| 检查 | 结果 | 仓库证据 |
|---|---|---|
| 公开API E2E | **475/475**；严格Swift6、完整并发检查、warnings-as-errors、release优化 | [完整冻结回执](evidence/final/receipt.json) |
| 五类组合 | **12组两态全部通过**，含Float Set、Optional嵌套数组、Int字典、物理游标与codingPath | [观察值](evidence/final/observations.json) |
| 完整业务与数值oracle | **1,837/1,837**；完整模型导出比较及数值位级判定 | [验收](evidence/weather-final/acceptance.json) / [源码与环境哈希](evidence/weather-final/environment.json) |
| 既有SPM release回归 | **93/93** | [日志](evidence/swift-test-final.log) |
| Swift5/6严格语言编译 | 两种均通过 | [回执](evidence/platforms-final/receipt.json) |
| 声明部署下限（库与公开consumer） | iOS11、watchOS4、tvOS11、macOS10.13均通过；使用当前SDK，仅编译 | [回执](evidence/platforms-final/receipt.json) |
| 公开接口比较 | 未诊断删除/改名/类型改变；µs日期enum新增case，诊断/路由新增API已公告 | [API diff](evidence/api-final/diff.log) / [迁移说明](../../docs/UPGRADE-COMPAT-GUIDE-20261004.md) |
| Objective-C契约 | **49/49**，此前记录；本轮Swift收敛没有再改ObjC | [回执](evidence/objc-contract/acceptance.json) |
| G4性能 | **通过本轮≤+10%回退门禁**；≤3×长期目标未达 | 同工具链修复前及最终计时证据 |

最终源码与公开consumer在 `evidence/final/source/`，SHA-256在回执中。业务与下限回执记录的
生产源码哈希与该冻结回执一致。原始命令包含当时的临时路径，归档源码不依赖那些路径即可重放。

## G4性能结果

同工具链修复前/最终计时（release -O、100次warmup、3000次迭代、9次取最佳，
计时期间无并行编译或大型消费者）：

| 模式与模型 | 修复前耗时ms | 最终耗时ms | 最终/官方比值 |
|---|---:|---:|---:|
| native Tiny | 0.00209 | 0.00169 | 0.98× |
| native Mid | 0.00753 | 0.00695 | 1.04× |
| native Payload | 0.03319 | 0.03209 | 1.01× |
| compatible Tiny | 0.00735 | 0.00720 | 5.08× |
| compatible Mid | 0.02532 | 0.02538 | 3.80× |
| compatible Payload | 0.12317 | 0.12815 | 4.06× |

Payload绝对耗时增加约4.04%，比值由3.81×到4.06×（约6.56%），均在原定+10%以内；
规则开销1.090×，小于1.10×。本轮回退门禁通过，**compatible≤3×长期目标仍未达到**。
R-1中间0.15099ms回退仍保留，不从历史中删除。

[判定与阈值](evidence/performance-final/gate.json) · [源码/二进制哈希及测量回执](evidence/performance-final/receipt.json) ·
[完整计时日志](evidence/performance-final/command-02.log) · [本轮初始基线](evidence/perf-baseline.log)。
本机微基准不替代业务负载或旧设备性能保证。

## 独立审查与新增回归

两名独立自动审查者先在冻结源码上复现，再迁入原消费者修复；不是正式外部人员签署。

- 逻辑祖先映射与物理游标不一致、整数路由丢失`-0`：已修并由原审查者独立重跑；
  [独立复核](evidence/independent-architecture-final/options-precision-observations.json)。
- Unicode/首字母缩写蛇形编码、重复嵌套容器、super键策略、自定义CodingKey的intValue、
  同一mapper字段重复访问误判冲突：已修，独立原consumer **45/45**；
  [独立复核](evidence/independent-tree-final/receipt.json)。
- R-2首版的12项Foundation编码回归全部修复；最终22项编码策略对照、35项协议用例及
  10项重复编码/真实冲突控制均通过。保留[失败基线](evidence/tree-foundation-baseline/)。
- 公开NSNumber跨调用精度由不可变规范节点边界保持，不增加public元数据修改API。

独立复核使用stage11冻结源码；最终版本只删除YYModelEncoder.swift末尾一行空白，
随后475项、93项、业务oracle及编译再次通过。功能代码一致。

## 初始事实与误报排除

历史“9组8组失败”来自冻结旧源码。当前初始源码实测**7/9通过、2/9失败**；
扩展12组后4组失败。原四文档涵盖F-06/A-01/A-02根因，却没有逐一描述五类组合，
本轮补上K-01–05、失败模式、公开consumer及最终处置。

P-02原负数.up/正数.down已向零截断，撤销无条件.down的错误处方；P-07幽灵代码不存在；
F-03A原生字典数据键不经key strategy转换。P-03/P-04本机原Decimal控制已通过，
R-2是架构收敛，不冒称旧OS缺陷已在本机复现。F-11a/c/e原推断未证实最终用户运行错误，
仅做维护性收敛；F-11d可变NSArray污染确实复现并修复。

## 契约与待证事项

- raw模型键：精确逻辑键优先，再UTF-8。Data入口保留Foundation冲突结果，hook读取同一子树。
- Int字典：规范拼写优先，再UTF-8；所有输入值严格解码，坏的冲突条目仍拒绝。
- 原生Data普通编码快路径保留；对象导出/export hook消费值树。普通对象键序不是API契约。
- `.integerTokens`可能含`-0`的载荷多一次Foundation符号遍历，包括字符串内匹配；普通现代默认路由不受影响。
- 旧OS浮点形式大整数超过2^53的精确性不保证；整数字面量/字符串是已公告建议。
- G5旧runtime、老SDK/工具链、真机、TSan、反射关闭构建配置仍没有完整验收证据。
- G7负责人和独立外部验收人签署保持空白。用户授权实施不等同于正式签署。

AGY完成部分审计、consumer与实现任务；后续配额不足由主代理完成收敛与修复。
