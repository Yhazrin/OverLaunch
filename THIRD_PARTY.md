OverLaunch 的原创启动器源码采用 MIT（见 LICENSE）；第三方运行库、字体、图像与商标分别授权，MIT 不授予这些资源的权利。

## 界面图像

- Hero portraits: https://github.com/drippinghere/overwatch-hero-icons, pinned commit `f4ddc06cf07d0741c40beda77eeeb1a81a99a279`.
- The public source repository contains the manifest and attribution, not portrait PNGs. The build fetches 53 files from the pinned source with `scripts/fetch-hero-assets.py`; per-file SHA-256 is recorded in `Assets/HeroIcons/catalog.json` and verified before bundling. Source README is included with the assets.
- These images and hero names belong to Blizzard Entertainment. The source describes them for personal/fan projects under Blizzard's community terms; this is not an MIT or other blanket artwork license. Source disclaimer: `Assets/HeroIcons/SOURCE-README.md`.
- The default icon is a programmatically drawn Overwatch-style O/W emblem. OW120 is a community launcher and is not affiliated with or endorsed by Blizzard/NetEase. No game screenshots or 3D models are bundled.

- DXMT OW2 fork: https://github.com/NerRobDog/dxmt
- Included release: v0.80-ow2-0.2, commit c5dc3a0dfe9108e667da43de871324bd298c9c02
- Source archive: https://github.com/NerRobDog/dxmt/archive/refs/tags/v0.80-ow2-0.2.tar.gz
- Binary origin: https://github.com/NerRobDog/dxmt/releases/download/v0.80-ow2-0.2/dxmt-ow2-pack-v0.2.tar.gz
- Downloaded binary SHA-256: 8d4e778ff9868883a064d7b9bfb372ed6e286e4233f60c053075ca983b2bc256
- License: LGPL-2.1-or-later. The full license is included as DXMT-COPYING.LIB, along with DXMT-LICENSE.
- Upstream: https://github.com/3Shain/dxmt

This checksum pins the exact bytes fetched from the author's GitHub release. It is not an independent security audit or an upstream signed attestation. OW120 installs the selected libraries into a private, local clone of the user's runtime; the release's install/uninstall scripts are never executed.

CrossOver, Apple's D3DMetal/GPTK components, Battle.net and the Overwatch game executable/data are NOT included in the distributed OW120.app. Version 0.2 imports the user's existing game bottle and settings using APFS copy-on-write, and installs the free community engine directly. It does not clone or require a commercial CrossOver application or license for execution. Private game copies, login state and logs live in the user's Application Support directory and must not be included in a public release. No Apple/CodeWeavers/Blizzard/NetEase affiliation or endorsement is claimed.

The launcher is locally ad-hoc signed. Public distribution requires a separate release process, Developer ID signing/notarization and a review of applicable third-party distribution obligations. This build is prepared for the current user's local Mac.

## 可选社区运行时（2026-09-25）

- Sikarugir WineCX 24：WS12WineCX24.0.7_7.tar.xz，https://github.com/Sikarugir-App/Engines/releases/tag/v1.0 ，SHA-256 `203f9e9fd6c2cc77e6525d798a434ced326145db34a356355e05659d3445fd1c`。
- Sikarugir Template 1.0.19：只使用本机解压的依赖库，https://github.com/Sikarugir-App/Template/releases/tag/v1.0 ，SHA-256 `ce9e4150fd2f0f3e8694814d82133eaaae1b1aabe5b8f2479155b88271cf5f9f`。模板包含多种许可证组件，OW120 不打包分发该模板或其中专有组件。
- Wine / WineCX 源码和授权以 Sikarugir 引擎发布页及 CodeWeavers 公开源为准。不能把 LGPL Wine 和商业 CrossOver 产品授权混为一谈。项目仅下载独立社区构建，没有修改商业试用检查。
- 战网 Agent 的相对路径签名验证兼容办法参考 https://github.com/BCD1210/soju ：把未修改的已签名 Battle.net.exe 复制到缺少它的版本目录，保留签名验证。
- Wine 11 的 WS12 / WS11 构建本机初始化失败；缓存不作为默认发行组件。

## 默认社区运行时（2026-09-26）

Soju `engine-v1.5`，Wine 11 / CodeWeavers 公开源构建：
https://github.com/BCD1210/soju/releases/tag/engine-v1.5 。
归档 `wine-engine-x86_64.tar.xz`（本机缓存名 soju-engine-v1.5.tar.xz），SHA-256 `7b96a4407308493ae92bebe96039bbc8d0bf3b86c22cb99c782f73cf7be3738e`。
来源及构建脚本：https://github.com/BCD1210/soju/blob/main/scripts/build-engine.sh 。仅下载官方引擎归档，未执行 Soju 的全局安装脚本；该归档不含苹果 GPTK。OW120 使用已有固定 DXMT 组件，不复制 CrossOver 商业授权模块。

## Smiley Sans / 得意黑 2.0.1

中文标题与导航使用atelierAnchor的得意黑原版OTF（2003884 bytes），SIL Open Font License 1.1；版权 © 2022–2024 atelierAnchor。

- 来源：https://github.com/atelier-anchor/smiley-sans/releases/tag/v2.0.1
- OTF SHA256：139b5dcbe70d6d52de85a62d148784c6af4bd161e38fdb62ba0c1e7e5065fca6
- 原始许可证：应用Resources/Fonts/OFL.txt（源码Assets/Fonts/OFL.txt）
- 字体未经修改，只在启动器进程注册，不安装到系统，不是暴雪字体。英文显示标题采用macOS DIN Condensed外观近似，中文小字号正文采用macOS苹方，系统字体不随安装包分发。
