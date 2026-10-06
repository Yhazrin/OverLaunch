# 参与开发

先阅读 README、PRODUCT、THIRD_PARTY 与 docs/DEVELOPMENT.md。使用 Swift 6 和 macOS 14+，执行 `./scripts/test.sh`；界面修改还需真实窗口验证。

- 原创源码遵循 MIT，新增第三方资源应注明来源和许可证，保留可复现版本及散列。
- 不提交游戏、账号、token、Cookie、私人日志、Wine 前缀、缓存、商业 CrossOver 或 Apple 专有组件；提交前检查 `git diff --cached`。
- 不修改用户原有游戏容器；运行时、Wine 前缀和 Documents 必须隔离，APFS 写时复制不能用硬链接替代。
- 不关闭系统安全保护，不修改反作弊，不注入游戏，不把配置目标当成实际帧率。
- 只用自己的测试账号；不要代用户自动进入公共对局。
- UI 文案使用简短功能名称；保留键盘/无障碍和减少动态效果支持。

PR 说明具体行为、验证方法与仍未验证的范围。缺陷报告可附芯片、macOS、源码版本与脱敏复现步骤，不附完整账号配置或私人运行目录。
