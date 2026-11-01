# ICS-Harbor 0.5.2 Preview · build 16

Apple Silicon 开发预览，要求 macOS 14.6 或更新版本；运行 Windows 软件需要 Rosetta。

## 安装

下载 `ICS-Harbor-0.5.2-preview.16-arm64.dmg`，打开后将 `Harbor.app` 拖入 `Applications`。

此版本使用 ad-hoc 签名，未经 Apple 公证。首次打开可能被 macOS 拦截；确认下载来源后，在“系统设置 → 隐私与安全性”中选择“仍要打开”。升级前请正常退出游戏和 Wine 环境，并备份 Harbor 状态文件。

## 本次内容

- 统一陶土橙界面、侧栏、游戏与应用详情和启动记录。
- 新增运行进程流量视图和 Windows EXE 图标读取。
- NieR:Automata 启动前核对主屏配置，修改前备份，配置健康时不写文件。
- 保留逐游戏 D3DMetal 参数和外置盘重连能力。
- 新增可重复运行的 DMG 打包脚本，安装包包含 Applications 拖拽入口、说明和许可文件。

## 验证与限制

- Release 构建成功；98 项测试，0 失败，3 项真实环境测试默认跳过。
- DMG 校验通过；挂载后应用深层严格签名验证通过，确认 arm64 与资源完整。
- 从只读挂载的 DMG 启动，使用隔离状态目录，确认游戏库与 Windows 应用页面可用。
- 本轮没有重新进行真实游戏、安装器或显示器拔插验收；不保证所有 Windows 软件兼容。
- 不包含 Wine、Windows、Steam、游戏、账号或存档；运行组件按需下载。

SHA-256: `6dd4d614c0b4f4074bc5c62570a4c49020f8830ad84adbe84ca5e1901626225c`
