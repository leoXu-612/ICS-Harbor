# 逐游戏参数 · 0.3

这些是保存给每款游戏的启动方案，不是对运行中的游戏注入设置。保持“继承”不会添加覆盖；改用不同运行时方案前需要正常退出 Steam 和该 Wine 环境内的其他程序。

## 参数与作用范围

| 参数 | 实际映射 | 范围与限制 |
| --- | --- | --- |
| 图形后端 | D3DMETAL / DXVK | 继承、DXMT、DXVK；不增加未经验证的 DX12 后端 |
| DXMT 帧率上限 | d3d11.preferredMaxFrameRate | 继承、不限、30/60/90/120/144/165/240；刷新率可能使实际值不同 |
| 强制 SDR | dxgi.forceSDR | 只改变 DXGI 的报告；关闭不意味着启用 HDR |
| 全屏切换处理 | dxgi.handleAltTab | DXMT 处理独占全屏 Alt/Cmd+Tab；不是窗口/全屏模式开关 |
| 同步方式 | WINEESYNC / WINEMSYNC | 独立 M-Sync、E-Sync、关闭、原双开配置、继承；不是垂直同步 |
| Metal HUD | METAL_HUD / MTL_HUD_ENABLED | 继承、开、关；显示细节由系统与后端决定 |
| Wine 日志 | WINEDEBUG | 继承、-all,err+all、-all,err+all,warn+all；无全量 relay 开关 |
| 自动进度 | Harbor 的任务展示策略 | 关闭后仍记录任务，用户可以主动查看 |
| 请求窗口置前 | macOS 激活请求 | 不保证 Wine 或系统一定把窗口带到前台 |
| 等待提醒 | Harbor 的无变化阈值 | 30/45/90/180 秒；不增加进度、不强制退出 |

分辨率、画质、抗锯齿、VSync、窗口模式等没有跨所有 Windows 游戏的可靠统一接口，本版不伪造这些开关。MetalFX 超分也未纳入此轮；不因上游存在某参数就假定所有本地版本都能使用。

## 授权与回退

关联环境须明确允许“备份后管理图形参数”。原始备份和授权记录位于 Harbor 数据目录的 `ConfigurationBackups/RuntimeControls/<容器 UUID>/`，权限为仅当前用户读写。授权不改变原容器、不初始化 prefix、不复制账号或存档。

授权后仍然按游戏保存预设，但同一 Steam 会话启动的程序会继承该会话环境。Harbor 在应用/恢复参数前检查运行状态；每次写入前另存原文件，只更改白名单字段。保留原始脚本、程序路径、键位和插件。“恢复默认”与“载入上次保存”只改变编辑草稿；运行环境更多菜单提供实际的原始参数恢复。

备份既有状态后再升级本版。新字段支持读取旧预设；旧客户端不一定认识新增同步模式，回退应用时应同时使用对应的状态备份。

## 来源与本机证据

- [DXMT 配置项](https://github.com/3Shain/dxmt/blob/186a2327f1ec76376f6bc1ef64636f08b0728567/dxmt.conf)
- [DXMT 环境配置读取](https://github.com/3Shain/dxmt/blob/186a2327f1ec76376f6bc1ef64636f08b0728567/src/util/config/config.cpp)：读取 DXMT_CONFIG，按分号解析配置。
- 本机现有 DXMT 的 32 位与 64 位 d3d11.dll 均包含所开放的三个参数名；UI 同样先检查本地能力，不自动替换组件。
- 2026-10-14，用真实 Sikarugir 启动器运行只回显环境变量的 cmd 探针，收到 `d3d11.preferredMaxFrameRate=60;dxgi.forceSDR=True`。探针没有启动游戏，未修改其显示设置；这只验证参数传递，不构成帧率或画质效果评测。
