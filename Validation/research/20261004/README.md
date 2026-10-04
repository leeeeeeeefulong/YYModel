# 2026-10-04 独立复审证据

这是观察与复现产物。当前库的错误结果被如实保留，不把“探针运行成功”标成“原版契约全通过”。先行失败模式见 `FAILURE-MODES.md` 和 `OBJC-FAILURE-MODES.md`。生产源码没有在这次研究中修改。

在组件根目录使用 macOS 的 Apple 工具链复跑：

```sh
python3 Validation/research/20261004/run_research.py --output /tmp/yy-review-repeat
```

输出目录必须为空。驱动从本仓库固定 Git 提交导出原版和已发布 2.1.9，对当前工作树只读；Swift 编译采用 `-O -swift-version 6 -warnings-as-errors`，OC 采用 `-O2`。输出模型观察、源文件/探针哈希和日志。它不写框架，也不访问业务工程。

保存的 `swift-probe-receipt.json`、`objc-probe-receipts.json` 是第一次探针观察的原始数据；`objc-contract-assessment.json` 列出原版契约偏差；`objc-performance-receipt.json` 保留相邻 ABBA 全部样本和二进制/source/fixture 哈希。

性能重测需要先用 `Validation/run_delivery.py` 在独立目录构建原版/当前版，运行完整正确性门禁。原版归档可由固定提交 `git archive c7df27538c043e5f54f5b6605958544bb529892f YYModel` 解压获得。指定当前已启动 iOS 模拟器 UUID：

```sh
python3 Validation/run_delivery.py --original-root /tmp/yy-original --simulator <UUID> --output /tmp/yy-interop-review --no-benchmark
python3 Validation/research/20261004/remeasure_objc.py --existing /tmp/yy-interop-review --original-root /tmp/yy-original --output /tmp/yy-perf-repeat
```

此便携驱动从原始研究运行器改为相对仓库路径，额外接受 original-root；原始回执的 runnerSHA256 对应当次原始运行器，不会被改成便携驱动的 hash。其他核心源码/harness/fixture 哈希仍逐项检查。正式计时独占执行，禁止与编译并行。

GitHub 定点下载身份和源码哈希见 `github-source-manifest.json`。它记录实际成功捕获的四个项目，不表示完整审计了所有第三方库；其他项目在研究报告中标明文档调研。第三方 README 的速度宣传未作为本组件性能结论。

报告：`docs/SWIFT-ARCHITECTURE-REVIEW-20261004.md`、`docs/OBJC-INDEPENDENT-REVIEW-20261004.md`。
