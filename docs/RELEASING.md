# 发行流程

版本号与 build 统一由 release.json 提供。artifactVersion 用于文件名和软件信息；tag 用于 GitHub。不要在发布后重新打包同名文件，改变内容应发布新版本。

## 公开测试版

执行 `./scripts/test.sh` 与 `./scripts/package.sh`，确认 app 深度签名校验、DMG 校验、版本与许可正确。默认 ad-hoc 签名，未经 Apple 公证，必须标为 beta/pre-release，说明首次打开可能被拦截。全新的 Mac、Rosetta 缺失、首次导入、下载失败重试、退出和升级需要实际验收，测试通过不等于游戏性能达标。

Release 包含 arm64 DMG、SHA256SUMS 和 bundled DXMT 固定提交的对应源码归档。Soju 引擎由应用按固定 SHA 下载；源码和许可证链接见 THIRD_PARTY.md。不要上传任何本机 Wine 前缀、游戏、账号、日志或私人交接。

## 正式公证版

需要本机钥匙串中可用的 Developer ID Application 证书，以及通过 `xcrun notarytool store-credentials` 配置的凭据 profile。Apple Development 不能替代。不要将证书、密钥或账号密码提交到仓库或 Release。

```sh
export OW120_SIGN_IDENTITY='Developer ID Application: Your Developer Name (TEAMID)'
export OW120_NOTARY_PROFILE='overlaunch-notary'
./scripts/notarize.sh
```

脚本启用 hardened runtime 与时间戳，提交 app，附加及验证公证票据，再从该 app 打包 DMG，签名、公证及验证 DMG。缺少凭据、被拒绝或 Gatekeeper 验证失败时停止，不能把文件称为已公证。

签名完整流程尚未在本项目执行成功。稳定版发布前完成跨 Mac 的实际导入和游戏验证，修改 release.json 为稳定版本与 channel，并检查本版本 release notes。

[Apple 公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) · [Apple 对 App 安全性的说明](https://support.apple.com/zh-cn/102445)
