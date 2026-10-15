# 第三方来源与发行边界

Harbor 的 Swift、脚本适配层和帆船图标为本仓库实现。MIT 许可只覆盖本仓库自有代码，不重新许可第三方软件、品牌或游戏资产。

## 架构参考

[Playdock](https://github.com/Jasonilization/Playdock) 的 Steam 库发现、启动协调和游戏设置组织方式提供了设计参考。研究参考提交：`f5c56a2922da82c8b584d5c67c650a58b8234435`。Harbor 没有完整 fork Playdock，VDF 解析、状态模型、策略层和 UI 在本仓库独立实现。

## 按需下载的运行组件

| 组件 | 固定版本或文件 | 官方来源 | SHA-256 |
| --- | --- | --- | --- |
| Sikarugir 模板 | Template 1.0.21 | [Template releases](https://github.com/Sikarugir-App/Template/releases/tag/v1.0) | `bbe996e4e4375318485953d0c7818b7b4b0a4dc1f13303bcc584f99f7602f78d` |
| Sikarugir Wine 引擎 | WS12WineSikarugir11.0_1 | [Engines releases](https://github.com/Sikarugir-App/Engines/releases/tag/v1.0) | `67e29fb3d74f363af39c69ba11f9b13a79812c5db07cf4748672658e4a200a0e` |
| Valve Steam 安装器 | SteamSetup.exe，本次固定内容 | [Valve 官方下载](https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe) | `7d3654531c32d941b8cae81c4137fc542172bfa9635f169cb392f245a0a12bcb` |

这些二进制不包含在 Harbor 安装包中。脚本只从上述项目的官方发布端下载，校验固定哈希后组装到用户自己的应用数据目录。校验通过只能确认内容与固定文件一致，不等同于安全审计或再分发授权。

[Sikarugir](https://github.com/Sikarugir-App) 各子组件许可不同，不能把 Configure 的许可推定到 Launcher、Creator 或完整模板；公开产品上线前仍需逐项核对适配、下载方式及相关许可义务。Wine、DXMT 和其他引擎依赖也适用各自的许可。此本地预览没有声称已获得所有组件的公共再分发授权。

参考：[Wine](https://www.winehq.org/)、[DXMT](https://github.com/3Shain/dxmt)。Harbor 不自行实现或销售这些图形转换引擎。

## 独立应用功能的复用

0.4 直接复用现有运行时的 `WSS-installer` 入口，以及 Wine 的 `cmd`、`start /wait`、`msiexec`；没有实现自己的 MSI 安装引擎，也没有引入额外的后台服务或下载未知 DLL。接口依据：[Wine msiexec 手册源码](https://github.com/wine-mirror/wine/blob/master/programs/msiexec/msiexec.man.in)。本仓库新增的是入口记录、参数编码与原生管理界面，未复制 Sikarugir 非公开 Launcher 源码。

本机安装验收使用 [7-Zip 官方下载](https://www.7-zip.org/download.html) 的 Windows x64 EXE/MSI，安装包不随 Harbor 分发。7-Zip 与 Wine 的许可不意味着 Sikarugir 的所有包装组件均为相同开源许可，公开发行边界仍适用上文。

新通用环境按需下载 [Noto Sans CJK SC Regular](https://github.com/notofonts/noto-cjk/tree/f8d157532fbfaeda587e826d4cd5b21a49186f7c/Sans)，采用 SIL Open Font License 1.1；字体未修改，完整许可与字体一起保存到该环境 Fonts 目录，不随 Harbor zip 捆绑。固定字体 SHA-256 为 `2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b`，许可文件为 `6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2`。下载字体还与上游 Git blob `dc15562470b4f842321894787a0d066879ccff8b` 对照核实。

## 品牌与内容

Harbor 不是 Valve、Apple、Sikarugir 或游戏发行商的官方产品。Steam 名称仅说明兼容目标。应用使用独立帆船图标，不将 Steam 商标作为应用身份。

游戏封面只显示本机 Steam 缓存，不随本应用分发。验收截图保存在本地 `docs/evidence`，不打入用户下载包。用户必须自行拥有游戏及账号；Harbor 不提供游戏文件、DRM 绕过或反作弊规避。
