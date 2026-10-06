# OverLaunch

Apple Silicon Mac 的国服守望先锋启动器。使用独立免费 Wine 引擎和 DXMT，导入已有游戏，管理启动设置、运行组件与性能记录。

当前为 0.4.4 社区测试版。120 FPS 是目标，实战低帧仍待验收。

## 启动

打开 `~/Applications/OverLaunch.app`，点“启动国服战网”，再从战网进入游戏。

首次使用点“导入游戏”，选择包含 `drive_c` 的已有国服战网和守望先锋容器。下载约367MB运行组件，使用APFS写时复制导入。账号登录、验证码和游戏更新在官方战网完成。

OW120 更新为 OverLaunch 时继续使用原来的游戏与配置；本机只保留一个安装入口。数据目录仍为 `~/Library/Application Support/OW120`，无需迁移或重新下载游戏。

## 启动设置

| 模式 | 行为 |
| --- | --- |
| 自动匹配 | 根据芯片、内存、桌面尺寸与刷新率生成设置；启动时重新匹配当前设备 |
| 流畅优先 | 降低3D渲染负载 |
| 均衡 | 在设备推荐基础上兼顾渲染负载和清晰度 |
| 清晰优先 | 使用100%渲染，过大的桌面改用合适尺寸的高清窗口 |
| 手动 | 保留用户选择，启动时不由设备推荐覆盖 |

这些模式是配置规则，不是性能预测或帧率保证。修改任意参数会切换到手动模式；已有旧版配置默认手动，原有设置保持不变。选择模式只填入草稿，保存后下次启动生效，当前游戏不受影响。

- 输出：跟随桌面的无边框模式、17档常用16:9/16:10/超宽屏尺寸、自定义尺寸。自定义宽640–8192，高480–8192。
- 3D渲染：50–100%，支持预设与逐百分比滑杆；降低比例不改变输出尺寸。
- 帧率：120/144/165/240 FPS；设备匹配按屏幕刷新率选档，60Hz屏幕仍保留120FPS目标。
- 高级：MSync、Metal限帧、着色器内存策略、性能叠层与显存上报。鼠标悬停可查看参数说明。

固定输出采用Retina高清窗口，避免与无边框桌面坐标混用。自动匹配使用桌面逻辑尺寸，超大桌面在50%渲染仍超过配置预算时选择高清窗口；这些规则还需不同Mac上的游戏验证。

## 外观与交互

开始、启动设置、性能、外观、工具箱五页支持⌘1–⌘5。移除宣传标语；选项框、开关、滑杆、按钮与英雄选中状态统一使用守望先锋风格。下拉列表与当前选项右侧取值区域直接连接，绘制在同一窗口内；空间不足向上打开，长列表滚动，支持方向键、回车、Escape和点击外部关闭；渲染滑杆支持方向键与无障碍增减。

首屏使用斜切启动区、英雄展示、橙色主按钮和已保存配置摘要；英雄横栏按需加载，支持左右箭头浏览，快捷启动设置保留。全部滚动区域隐藏滚动条，保留触控板/滚轮与键盘滚动，下拉列表仍按窗口边界定位。

按钮悬停/按下、英雄选中和页面切换使用短反馈动画，尊重系统“减少动态效果”；没有持续装饰动画。窗口初始尺寸适配屏幕，最小660×500；窄窗口使用纵向布局，内容可滚动。后台暂停帧曲线读取并降低轮询频率。

默认O/W标志与53个英雄2D图标离线提供；在“外观”搜索、选择或恢复默认。选择改变Dock及启动器内图标，应用台/Finder保留默认OW标志，不修改签名资源或游戏头像。来源见THIRD_PARTY.md。

## 检查与报告

“工具箱”提供检查、修复、诊断与文件夹入口。关闭游戏与战网后修复运行组件，保留游戏安装。“性能”在游戏输出连续帧后显示数据，可采样与导出报告。菜单和加载停顿需要与战斗样本区分。

战网浏览器硬件加速与游戏DXMT分别管理：新导入默认关闭浏览器硬件加速，随后保留用户选择。本机登录白屏修复已由用户确认；HUD头像白块与实战低帧仍待解决。

## 安装包与构建

源码构建需要 Apple Silicon Mac、macOS 14+、Swift 6 工具链（Xcode 或 Command Line Tools）、Python 3，以及网络连接。核心测试不需要游戏、账号或 Wine。构建脚本从固定来源下载并校验 DXMT 与英雄头像；字体及许可证随源码提供。英雄图像不适用源码的 MIT 许可证，详见 [第三方说明](THIRD_PARTY.md)。

本次公开的是源码，尚无正式签名、公证的二进制发行版。

给朋友分享 `dist.noindex/OverLaunch-0.4.4-arm64.dmg`，每位用户导入自己的游戏。包内不含游戏、账号或商业CrossOver。支持Apple Silicon/macOS14+；目前为本机签名候选，正式对外发行还需Developer ID、公证与跨设备验收。

```sh
git clone https://github.com/Yhazrin/OverLaunch.git
cd OverLaunch
./scripts/test.sh
./scripts/package.sh
open dist/OverLaunch.app
```

源码模块、可执行文件与环境变量暂保留OW120内部标识，应用名称与安装包为OverLaunch。构建留在dist.noindex，dist是兼容软链接，旧安装版先校验zip备份后移正常废纸篓。

```sh
./dist/OverLaunch.app/Contents/MacOS/OW120 --doctor
./dist/OverLaunch.app/Contents/MacOS/OW120 --config-mode automatic
./dist/OverLaunch.app/Contents/MacOS/OW120 --config-mode manual
./dist/OverLaunch.app/Contents/MacOS/OW120 --render-scale 80
./dist/OverLaunch.app/Contents/MacOS/OW120 --list-icons
./dist/OverLaunch.app/Contents/MacOS/OW120 --set-icon mei
./dist/OverLaunch.app/Contents/MacOS/OW120 --health
./dist/OverLaunch.app/Contents/MacOS/OW120 --launch
./dist/OverLaunch.app/Contents/MacOS/OW120 --stop
```

`OW120_ROOT`可指定隔离测试目录。不得公开游戏、账号、私人日志或运行环境。开发与协作见 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [开发状态](docs/DEVELOPMENT.md)。

## 窗口与字体

系统标题栏隐藏，顶部品牌区可拖动窗口；关闭、最小化、全屏按钮保留。英文标题与英雄名使用DIN Condensed近似守望先锋窄长斜体，中文标题和导航使用得意黑，设置正文使用苹方。设置行整行高亮，控件可用键盘操作。内置约2MB原版得意黑及OFL许可证，字体仅在应用内注册；不额外安装系统字体或打包游戏专用字体。

## 软件信息与项目仓库

启动设置页末尾的“软件信息”显示应用名称、真实版本、支持平台、运行组件、项目仓库和第三方许可；主窗口没有固定版本底栏。公共源码仓库：[Yhazrin/OverLaunch](https://github.com/Yhazrin/OverLaunch)。构建默认写入该地址；可通过 `OVERLAUNCH_REPOSITORY_URL` 覆盖，软件信息将显示“查看项目”。

## 许可

原创启动器源码采用 [MIT](LICENSE) 许可证。字体、运行组件、英雄图像和商标各自遵循原有权利及许可证，见 [THIRD_PARTY.md](THIRD_PARTY.md)。本项目与暴雪、网易、CodeWeavers 或 Apple 无隶属关系。
