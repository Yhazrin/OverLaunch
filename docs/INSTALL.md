# 下载与安装

从 [Releases](https://github.com/Yhazrin/OverLaunch/releases) 下载与版本对应的 arm64 DMG。预发布版本会标为 Pre-release；未公证的测试版不能当作稳定正式版。

要求 Apple Silicon、macOS 14+、Rosetta 2、网络连接，以及已安装完整国服战网和守望先锋的 Wine/CrossOver 容器。当前没有从零安装战网的流程。源容器和用户目录需要位于同一支持写时复制的 APFS 卷。第一次安装会额外下载约 367 MB 运行组件，游戏更新可能另需空间。

1. 打开 DMG，将 OverLaunch 拖到 Applications，推出磁盘镜像，再打开 Applications 中的应用。
2. 按应用内引导检查设备。缺少 Rosetta 时查看 [Apple 安装说明](https://support.apple.com/zh-cn/102527)，安装后重新检查。
3. 选择已有完整游戏容器，通常在 `~/Library/Application Support/CrossOver/Bottles/`，可选择容器本身或其中的 drive_c。只选 Overwatch 游戏目录不够。
4. 退出源容器的游戏及战网，选择启动设置：自动匹配或手动分辨率、渲染比例、帧率目标。
5. 点击“开始安装”。下载校验、隔离导入、图形组件安装及运行检查完成后，打开国服战网，登录并进入游戏。

引导可稍后设置，从“工具箱 → 安装引导”重新打开。自动匹配是配置规则，不保证帧率；高分辨率会提高 GPU 负载。

## 测试版首次打开

0.5.0-beta.1 使用 ad-hoc 签名，没有 Developer ID 和 Apple 公证。macOS 可能提示开发者无法验证或阻止打开。先确认下载来自本项目、SHA-256 与该版本 SHA256SUMS 一致，再按 [Apple 的打开说明](https://support.apple.com/zh-cn/102445) 处理。不要全局关闭 Gatekeeper，也不要修改应用签名资源。

可在终端校验下载的包：

```sh
cd ~/Downloads
shasum -a 256 OverLaunch-0.5.0-beta.1-arm64.dmg
```

若仍显示“已损坏”，重新下载并检查校验值，提交 issue 描述 macOS 版本及提示文字；不要上传含登录信息的容器或完整私人日志。

## 更新与卸载

更新时先退出启动器，再替换 Applications 中的旧应用；只保留一个应用入口。用户数据仍存放在 `~/Library/Application Support/OW120`，升级无需重新下载或导入游戏。仅移除应用不会删除数据；不要随意删除该目录。

## 验证范围

源码核心测试和本机导入/运行已有记录；首次引导的完整下载、跨 Mac 导入和游戏性能尚未全面验收。HUD 头像白块和实战低帧仍为已知问题。目标 120 FPS 不代表最低帧已达到 120。
