#!/bin/bash
# Harbor's pinned Sikarugir runtime adapter. No account or save data is copied.
set -euo pipefail
umask 077

KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="${HARBOR_APP_DIR:?Harbor must provide a container path}"
CACHE="${HARBOR_CACHE_DIR:?Harbor must provide a cache path}"
PREFIX="$APP/Contents/SharedSupport/prefix"
LAUNCHER="$APP/Contents/MacOS/launcher"
MARKER="$APP/Contents/HarborRuntime-version"
TEMPLATE=Template-1.0.21.tar.xz
ENGINE=WS12WineSikarugir11.0_1.tar.xz
TEMPLATE_SHA=bbe996e4e4375318485953d0c7818b7b4b0a4dc1f13303bcc584f99f7602f78d
ENGINE_SHA=67e29fb3d74f363af39c69ba11f9b13a79812c5db07cf4748672658e4a200a0e
STEAM_SHA=7d3654531c32d941b8cae81c4137fc542172bfa9635f169cb392f245a0a12bcb
FONT_SHA=2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b
FONT_LICENSE_SHA=6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2

say() { printf '%s\n' "$*"; }
die() { say "错误：$*" >&2; exit 1; }
hash_ok() { [ -f "$1" ] && [ "$(/usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}')" = "$2" ]; }
platform_check() {
  [ "$(uname -s)" = Darwin ] || die '仅支持 macOS。'
  [ "$EUID" -ne 0 ] || die '请勿使用 sudo 运行本脚本。'
  [ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" = 1 ] || die '本包面向 Apple Silicon（M 系列），不适用于 Intel Mac。'
  local os major minor
  os="$(/usr/bin/sw_vers -productVersion)"
  major="${os%%.*}"
  minor="${os#*.}"; minor="${minor%%.*}"
  if [ "$major" -lt 14 ] || { [ "$major" -eq 14 ] && [ "$minor" -lt 6 ]; }; then
    die "需要 macOS 14.6 或更新版本；当前为 ${os}。"
  fi
  case "$APP" in /*.app) ;; *) die 'HARBOR_APP_DIR 必须是绝对路径并以 .app 结尾。' ;; esac
  case "$CACHE" in /*) ;; *) die 'HARBOR_CACHE_DIR 必须是绝对路径。' ;; esac
  say "环境：$(/usr/sbin/sysctl -n machdep.cpu.brand_string)，macOS $os"
}

need_rosetta() {
  /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null || die '未检测到可用 Rosetta。请本人在终端运行 softwareupdate --install-rosetta 并阅读、确认 Apple 许可，再返回 Harbor 重试。'
}

need_app() {
  [ -f "$MARKER" ] && [ "$(head -n 1 "$MARKER")" = harbor-runtime-v1 ] || die "托管标记不匹配：${APP}；不会覆盖已有目录。"
  [ -f "$APP/Contents/HarborManagedRuntime" ] && [ "$(head -n 1 "$APP/Contents/HarborManagedRuntime")" = "${HARBOR_CONTAINER_ID:?}" ] || die '容器 UUID 与托管标记不匹配，未修改。'
  [ -x "$LAUNCHER" ] || die '容器启动器缺失。请查看任务日志，不要覆盖旧容器。'
}

launch_background() {
  local log_name="$1"
  shift
  mkdir -p "$APP/Contents/SharedSupport/Logs"
  /usr/bin/nohup "$LAUNCHER" "$@" > "$APP/Contents/SharedSupport/Logs/$log_name" 2>&1 < /dev/null &
}

fetch() {
  local name="$1" expected="$2" url="$3" target part result
  target="$CACHE/$name"; part="$CACHE/$name.part"
  if hash_ok "$target" "$expected"; then say "使用已校验缓存：$name"; return; fi
  if [ -e "$target" ]; then
    die "缓存校验不符：${target}。请移走该文件后重试；不会覆盖或执行它。"
  fi
  say "下载官方文件：${name}（中断后可重跑，自动续传）"
  result=0
  /usr/bin/curl --fail --location --proto '=https' --proto-redir '=https' \
    --connect-timeout 20 --max-time 3600 --speed-time 60 --speed-limit 1024 \
    --retry 3 --retry-delay 2 --continue-at - --progress-bar --output "$part" "$url" || result=$?
  if [ "$result" = 33 ] || [ "$result" = 36 ]; then
    # Some CDN responses reject byte ranges. Preserve the partial file before restarting.
    mv "$part" "$part.range-rejected.$(date +%s)"
    /usr/bin/curl --fail --location --proto '=https' --proto-redir '=https' \
      --connect-timeout 20 --max-time 3600 --retry 3 --progress-bar --output "$part" "$url" || die "下载失败；可重跑 install。"
  elif [ "$result" -ne 0 ]; then
    die "下载中断（curl ${result}）；已保留断点。检查网络后重跑 install，不要关闭 TLS 校验。"
  fi
  hash_ok "$part" "$expected" || die "SHA-256 不匹配，未执行文件：${part}。官方文件可能更新，请先核对来源并更新命令包，不要跳过校验。"
  mv "$part" "$target"
}

prepare() {
  platform_check
  need_rosetta
  if [ -e "$APP" ]; then
    need_app
    say "已有本工具的容器，保持游戏、账号和存档不变：$APP"
    return
  fi
  local parent stage bundle info free_kb
  parent="$(dirname "$APP")"
  mkdir -p "$parent" "$CACHE"
  free_kb="$(df -Pk "$parent" | awk 'END {print $4}')"
  [ "$free_kb" -ge 10485760 ] || die '目标盘至少需要 10 GiB 可用空间；建议预留 15 GiB 以上。'
  fetch "$TEMPLATE" "$TEMPLATE_SHA" "https://github.com/Sikarugir-App/Template/releases/download/v1.0/$TEMPLATE"
  fetch "$ENGINE" "$ENGINE_SHA" "https://github.com/Sikarugir-App/Engines/releases/download/v1.0/$ENGINE"
  stage="$(mktemp -d "$parent/.harbor-build.XXXXXX")"
  say "组装临时目录：${stage}（失败时保留供检查，不删除旧文件）"
  mkdir "$stage/template" "$stage/engine"
  /usr/bin/tar -xf "$CACHE/$TEMPLATE" -C "$stage/template"
  /usr/bin/tar -xf "$CACHE/$ENGINE" -C "$stage/engine"
  bundle="$stage/template/Template-1.0.21.app"
  info="$bundle/Contents/Info.plist"
  [ -x "$bundle/Contents/MacOS/launcher" ] || die '模板目录结构与固定版本不符。'
  [ -x "$stage/engine/wswine.bundle/bin/wine" ] || die '引擎目录结构与固定版本不符。'
  mv "$stage/engine/wswine.bundle" "$bundle/Contents/SharedSupport/wine"
  /usr/bin/plutil -replace CFBundleName -string 'Harbor Runtime' "$info"
  /usr/bin/plutil -replace CFBundleIdentifier -string "local.harbor.runtime.${HARBOR_CONTAINER_ID:?}" "$info"
  # Preserve the legacy "launcher" entry-point name, which selects wrapper mode.
  # Replace only this freshly extracted symlink with a byte-identical regular file.
  cp -p "$bundle/Contents/MacOS/Sikarugir" "$stage/launcher-copy"
  mv -f "$stage/launcher-copy" "$bundle/Contents/MacOS/launcher"
  /usr/bin/plutil -replace CFBundleExecutable -string 'launcher' "$info"
  /usr/bin/plutil -replace 'Program Name and Path' -string '/windows/system32/cmd.exe' "$info"
  /usr/bin/plutil -replace 'Program Flags' -string '' "$info"
  /usr/bin/plutil -replace D3DMETAL -integer 0 "$info"
  /usr/bin/plutil -replace DXVK -integer 0 "$info"
  /usr/bin/plutil -replace METAL_HUD -integer 0 "$info"
  /usr/bin/plutil -replace 'Symlinks In User Folder' -integer 0 "$info"
  /usr/bin/plutil -replace WINEDEBUG -string '-all,err+all' "$info"
  /usr/bin/plutil -lint "$info"
  cp -p "$info" "$bundle/Contents/HarborBaseline.plist"
  printf 'harbor-runtime-v1\nTemplate=1.0.21\nEngine=WS12WineSikarugir11.0_1\n' > "$bundle/Contents/HarborRuntime-version"
  printf '%s\n' "$HARBOR_CONTAINER_ID" > "$bundle/Contents/HarborManagedRuntime"
  # Resolve the template's Contents/drive_c symlink before signature validation.
  mkdir -p "$bundle/Contents/SharedSupport/prefix/drive_c"
  # Local ad-hoc signing of the newly assembled app; never disables Gatekeeper or SIP.
  /usr/bin/codesign --force --deep --preserve-metadata=entitlements --sign - "$bundle"
  /usr/bin/codesign --verify --deep --strict "$bundle"
  mv "$bundle" "$APP"
  rmdir "$stage/template" "$stage/engine" "$stage"
  say "容器文件已组装（尚未代表 Steam 安装或游戏运行成功）：$APP"
}

init_prefix() {
  need_app; need_rosetta
  [ -f "$PREFIX/.harbor-profile-ready" ] && [ -f "$PREFIX/system.reg" ] && return
  local attempt profile folder link
  say '首次初始化独立 Windows 目录。若系统弹出权限/安全提示，请本人核对并处理。'
  # The launcher may remain alive after initialization, so do not wait for its exit.
  if [ ! -f "$PREFIX/system.reg" ]; then
    launch_background prefix-init.log WSS-wineprefixcreate
  fi
  for ((attempt=0; attempt<90; attempt++)); do
    if [ -f "$PREFIX/system.reg" ] && [ -f "$PREFIX/drive_c/windows/system32/cmd.exe" ]; then break; fi
    sleep 2
  done
  [ -f "$PREFIX/system.reg" ] && [ -f "$PREFIX/drive_c/windows/system32/cmd.exe" ] || die '初始化超时。请检查系统提示；文件保留，可重跑 install。'
  launch_background runtime-probe.log WSS-installer "$KIT_DIR/runtime-probe.cmd"
  for ((attempt=0; attempt<30; attempt++)); do
    if /usr/bin/grep -q 'HARBOR_WIN32_OK' "$PREFIX/drive_c/harbor-ready.txt" 2>/dev/null; then break; fi
    sleep 2
  done
  /usr/bin/grep -q 'HARBOR_WIN32_OK' "$PREFIX/drive_c/harbor-ready.txt" 2>/dev/null || die 'Windows 命令启动检查未通过；请查看任务日志，不继续安装程序。'
  # Wine itself can create host-folder links even when the wrapper option is off.
  # Move only those links in this NEW prefix; never touch their host targets.
  if ! steam_exists; then
    for profile in "$PREFIX"/drive_c/users/*; do
      [ -d "$profile" ] && [ ! -L "$profile" ] || continue
      for folder in Desktop Documents Downloads Music Pictures Videos; do
        link="$profile/$folder"
        if [ -L "$link" ]; then
          [ ! -e "$link.host-link.saved" ] && [ ! -L "$link.host-link.saved" ] || die "已存在映射备份：$link.host-link.saved"
          mv "$link" "$link.host-link.saved"
          mkdir "$link"
        fi
      done
    done
  fi
  printf 'profile-ready-v1\n' > "$PREFIX/.harbor-profile-ready"
  say '独立 Windows 目录及 Win32 命令启动检查通过；尚未验证游戏。'
}

steam_exists() { [ -f "$PREFIX/drive_c/Program Files (x86)/Steam/Steam.exe" ]; }

install_cjk_font() {
  need_app
  local target="$PREFIX/drive_c/windows/Fonts/NotoSansCJKsc-Regular.otf"
  local license="$PREFIX/drive_c/windows/Fonts/NotoSansCJK.LICENSE"
  if hash_ok "$target" "$FONT_SHA" && hash_ok "$license" "$FONT_LICENSE_SHA"; then return; fi
  if { [ -e "$target" ] || [ -L "$target" ]; } && ! hash_ok "$target" "$FONT_SHA"; then die '已有不同版本的 Noto 字体，未覆盖。'; fi
  fetch NotoSansCJKsc-Regular.otf "$FONT_SHA" 'https://raw.githubusercontent.com/notofonts/noto-cjk/f8d157532fbfaeda587e826d4cd5b21a49186f7c/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf'
  fetch NotoSansCJK.LICENSE "$FONT_LICENSE_SHA" 'https://raw.githubusercontent.com/notofonts/noto-cjk/f8d157532fbfaeda587e826d4cd5b21a49186f7c/Sans/LICENSE'
  mkdir -p "$PREFIX/drive_c/windows/Fonts"
  cp "$CACHE/NotoSansCJKsc-Regular.otf" "$target"
  cp "$CACHE/NotoSansCJK.LICENSE" "$license"
  say '已准备开源 Noto 中文字体及 OFL 许可；不修改宿主或其他容器字体。'
}

configure_cjk_font() {
  /usr/bin/grep -q '^harbor-cjk-v1' "$PREFIX/drive_c/harbor-cjk-ready.txt" 2>/dev/null && return
  local attempt
  say '配置这个新通用环境的中文字体替代，避免菜单显示方框。'
  launch_background cjk-fonts.log WSS-installer "$KIT_DIR/cjk-fonts.cmd"
  for ((attempt=0; attempt<30; attempt++)); do
    if /usr/bin/grep -q '^harbor-cjk-v1' "$PREFIX/drive_c/harbor-cjk-ready.txt" 2>/dev/null; then return; fi
    sleep 1
  done
  die '中文字体配置未确认完成。请查看日志后重试准备，不要删除容器。'
}

install_steam() {
  init_prefix
  mkdir -p "$CACHE"
  fetch SteamSetup.exe "$STEAM_SHA" 'https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe'
  say '即将打开 Valve 原版安装器。请保留默认安装路径，自行完成许可、安装和登录。'
  say '完成后在此 Wine Steam 中安装游戏，并回到 Harbor 刷新游戏库。'
  launch_background steam-install.log WSS-installer "$CACHE/SteamSetup.exe"
}

case "${1:-}" in
  install) prepare; if steam_exists; then say 'Steam.exe 已存在，保留现有安装。'; else install_steam; fi ;;
  prepare) prepare; install_cjk_font; init_prefix; configure_cjk_font; say '通用 Windows 环境已准备；未下载或安装 Steam。' ;;
  *) die '内部安装适配器仅支持 install / prepare，请通过 Harbor 界面使用。' ;;
esac
