# 修复工程：公开 API 端到端验收

在 Apple Silicon 或 Intel macOS 的 Swift 6 工具链运行：

```sh
python3 Validation/remediation/run.py --output /tmp/yymodel-acceptance-new
```

输出目录必须不存在。执行器先保存当前生产源码、consumer、执行器和参考期望的
SHA-256 快照，再独立编译动态库与公开 API consumer。输出 `receipt.json`、各 consumer
观察值、完整编译/运行日志；任一断言失败即非零退出，观察程序的正常退出不表示验收通过。

完整快照可直接重放：

```sh
python3 /tmp/yymodel-acceptance-new/source/Validation/remediation/run.py \
  --output /tmp/yymodel-acceptance-replay
```

历史 consumer 已迁入本目录，不依赖被 Git 忽略的 `docs/review-*/`。GitHub workflow
`.github/workflows/remediation-e2e.yml` 在提交与 PR 上运行公开 consumer 与既有回归，
成功或失败均上传源码快照、回执和日志。workflow 尚需实际远端执行，不能把本地 YAML
文件存在视为 CI 通过。

## 已保存的基线

| 证据目录 | 实测范围与结果 |
|---|---|
| `evidence/current-baseline` | 当前初始工作区：九组组合对照 7 通过、2 失败 |
| `evidence/expanded-baseline` | 加游标、Float Set、字典模型路径：12 组中 4 失败 |
| `evidence/bridge-green` | 同样 12 组已转绿；后续改动须持续复跑 |
| `evidence/numeric-baseline` | 三个 hook Float token 失败；本机 Decimal 导出与策略桥控制通过 |
| `evidence/numeric-green2` | Float 控制与 hook 两态转绿，包括超过 Decimal 容量的长 token |
| `evidence/registry-baseline` | 登记册控制通过，17 个字段契约场景失败 |
| `evidence/extended-baseline` | 同名错误路径、super 物理节点、可变 hook 子树等扩展观察 |
| `evidence/tree-foundation-baseline` | R-2 首版新增16项 Foundation编码对照，12项失败；是实施回归，须修复 |

早期基线记录了源码哈希与观察值，没有完整源码副本；正式执行器新增了冻结源码重放。
这些历史证据用于说明修复前后变化，最终验收以同一份当前源码的完整回执为准。最终结果555/555、业务数值1,837/1,837，见 [STATUS](STATUS.md)。

仓库内完整归档可直接重放（输出路径须不存在）：

```sh
python3 Validation/remediation/evidence/final/source/Validation/remediation/run.py \
  --output /tmp/yymodel-final-replay-new
python3 Validation/remediation/evidence/final/source/Validation/remediation/verify_platforms.py \
  --acceptance-root /tmp/yymodel-final-replay-new --output /tmp/yymodel-platform-replay-new
python3 Validation/remediation/evidence/final/source/Validation/run_swift_model_data.py \
  --source-root Validation/remediation/evidence/final/source \
  --output /tmp/yymodel-business-replay-new --samples 1 --iterations 1
python3 Validation/remediation/evidence/final/source/Validation/remediation/run_performance.py \
  --acceptance-root /tmp/yymodel-final-replay-new --output /tmp/yymodel-perf-replay-new
```

源码和辅助重放文件的完整哈希见 `evidence/final/delivery.json`。

## 性能回执

在完整 E2E 已接受的冻结目录上运行：

```sh
python3 Validation/remediation/run_performance.py \
  --acceptance-root /tmp/yymodel-acceptance-new \
  --output /tmp/yymodel-performance-new
```

输出保留 benchmark 源码、库和模块哈希、接受回执的源码哈希、全部命令和计时日志。
消费者遇到任何解码错误会失败，不把错误吞掉后报告虚假的更快结果。`completed`
仅表示计时执行完整；性能门禁须比较同工具链基线、绝对耗时与官方比值，不能仅凭
该字段声称通过。`evidence/perf-after-r1.log` 已记录中间版本的实际回退。

本机未安装 iOS 14/15 runtime。现代系统上的大整数通过、部署下限 typecheck 或
强制走降级路径都不能替代旧 Foundation 的实际运行时验证。旧 OS 门禁与独立人员签署
仍按验收计划单独核验。
