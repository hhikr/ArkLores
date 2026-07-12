#!/usr/bin/env bash
#
# ArkLores — Android 一键配置与安装脚本
#
# 用法:
#   ./tools/setup.sh            # 构建 debug APK 并安装
#   ./tools/setup.sh debug      # 同上
#   ./tools/setup.sh release    # 构建 release APK 并安装
#
# 环境变量:
#   ANDROID_HOME    — Android SDK 路径（默认 ~/Android/Sdk）
#   FLUTTER_HOME    — Flutter SDK 路径（默认 ~/flutter）
#
set -euo pipefail

# ─── 常量 ────────────────────────────────────────────────────────

readonly PROG="$(basename "$0")"
readonly PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly FLUTTER_DEFAULT="$HOME/flutter"
readonly ANDROID_DEFAULT="$HOME/Android/Sdk"
readonly CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"

# ─── 颜色输出 ────────────────────────────────────────────────────

RED='\033[0;31m';     GREEN='\033[0;32m'
YELLOW='\033[1;33m';  CYAN='\033[0;36m';  BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${CYAN}•${NC} $1"; }
log_ok()   { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_err()  { echo -e "${RED}✗${NC} $1"; }
log_step() { echo -e "\n${CYAN}==>${NC} ${BOLD}$1${NC}"; }

# ─── 帮助 ────────────────────────────────────────────────────────

usage() {
  cat <<EOF
用法: $PROG [debug|release]

参数:
  debug    构建 debug APK（默认，≈80MB，无需签名）
  release  构建 release APK（更小更快，需配置签名密钥）

环境变量:
  ANDROID_HOME  Android SDK 路径（默认 $ANDROID_DEFAULT）
  FLUTTER_HOME  Flutter SDK 路径（默认 $FLUTTER_DEFAULT）

示例:
  $PROG              # debug 构建 + 安装
  $PROG release      # release 构建 + 安装
EOF
  exit 0
}

# ─── Android SDK 安装 ───────────────────────────────────────────

install_android_sdk() {
  mkdir -p "$ANDROID_HOME"
  pushd "$ANDROID_HOME" > /dev/null

  # 下载命令行工具
  log_info "下载命令行工具..."
  wget -q --show-progress "$CMDLINE_TOOLS_URL" -O cmdline-tools.zip
  unzip -q cmdline-tools.zip
  rm cmdline-tools.zip

  # 整理目录结构（sdkmanager 要求工具位于 cmdline-tools/latest/）
  mkdir -p cmdline-tools/latest
  if [ -d cmdline-tools/bin ]; then
    mv cmdline-tools/bin cmdline-tools/latest/
    mv cmdline-tools/lib cmdline-tools/latest/
    # 移动剩余文件（NOTICE.txt 等）
    for f in cmdline-tools/*; do
      [ -f "$f" ] && mv "$f" cmdline-tools/latest/
    done 2>/dev/null || true
  fi

  SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"

  # 接受许可证
  log_info "接受 Android SDK 许可证..."
  yes | "$SDKMANAGER" --sdk_root="$ANDROID_HOME" --licenses

  # 安装必要组件
  log_info "安装 platform-tools、platforms;android-34、build-tools..."
  "$SDKMANAGER" --sdk_root="$ANDROID_HOME" \
    "platform-tools" \
    "platforms;android-34" \
    "build-tools;34.0.0"

  # Flutter Android 许可证
  log_info "接受 Flutter Android 许可证..."
  "$FLUTTER" doctor --android-licenses

  popd > /dev/null
  log_ok "Android SDK 安装完成: $ANDROID_HOME"
}

# ═══════════════════════════════════════════════════════════════════
#  主流程
# ═══════════════════════════════════════════════════════════════════

# ─── 参数解析 ────────────────────────────────────────────────────

BUILD_TYPE="${1:-debug}"
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then usage; fi

case "$BUILD_TYPE" in
  debug|release) ;;
  *) log_err "未知构建类型: $BUILD_TYPE"; echo "用法: $PROG [debug|release]"; exit 1 ;;
esac

# ─── 路径 ────────────────────────────────────────────────────────

FLUTTER_HOME="${FLUTTER_HOME:-$FLUTTER_DEFAULT}"
FLUTTER="$FLUTTER_HOME/bin/flutter"
ANDROID_HOME="${ANDROID_HOME:-$ANDROID_DEFAULT}"

# ─── 第一步：检查前置条件 ──────────────────────────────────────

log_step "检查前置条件"

# Flutter SDK
if [ ! -f "$FLUTTER" ]; then
  log_err "未找到 Flutter SDK（期望路径: $FLUTTER）"
  log_info "请安装 Flutter 后重试，或设置 FLUTTER_HOME 环境变量"
  exit 1
fi
log_ok "Flutter SDK: $FLUTTER_HOME"

# Java
if command -v java &>/dev/null; then
  JAVA_VER="$(java -version 2>&1 | head -1)"
  log_ok "Java: $JAVA_VER"
else
  log_warn "未安装 Java，正在安装 jdk21-openjdk..."
  sudo pacman -S --noconfirm jdk21-openjdk
  log_ok "Java 安装完成"
fi

# Android SDK
if [ -d "$ANDROID_HOME/platform-tools" ]; then
  log_ok "Android SDK: $ANDROID_HOME"
else
  log_warn "未找到 Android SDK，开始安装（从零配置）..."
  install_android_sdk
fi

# ─── 第二步：构建 APK ─────────────────────────────────────────

log_step "构建 ${BUILD_TYPE} APK"

cd "$PROJECT_ROOT"
export ANDROID_HOME

if [ ! -d "$PROJECT_ROOT/android" ]; then
  log_err "项目中没有 android/ 目录，请在 ArkLores 项目根目录运行 $PROG"
  exit 1
fi

"$FLUTTER" build apk --"$BUILD_TYPE"

APK="build/app/outputs/flutter-apk/app-${BUILD_TYPE}.apk"
if [ ! -f "$APK" ]; then
  log_err "构建失败：未找到 APK 文件 $APK"
  exit 1
fi
APK_SIZE="$(du -h "$APK" | cut -f1)"
log_ok "APK 构建成功: $APK （${APK_SIZE}）"

# ─── 第三步：安装到设备 ───────────────────────────────────────

log_step "安装到 Android 设备"

ADB="$ANDROID_HOME/platform-tools/adb"

if [ ! -f "$ADB" ]; then
  log_warn "未找到 adb（$ADB），跳过安装"
  echo "  APK 已就绪，请手动安装: $APK"
  exit 0
fi

DEVICES=$("$ADB" devices | awk 'NR>1 && /device$/ {print $1}')

if [ -z "$DEVICES" ]; then
  log_warn "未检测到已连接的 Android 设备"
  echo "  1. 手机开启「开发者选项」→「USB 调试」"
  echo "  2. 连接数据线并同意调试授权"
  echo "  3. 重新运行本脚本"
  echo ""
  echo "  APK 已就绪，也可手动安装: $APK"
  exit 0
fi

for DEVICE in $DEVICES; do
  echo "    正在安装到 $DEVICE ..."
  "$ADB" -s "$DEVICE" install -r "$APK" 2>&1 | sed 's/^/    /'
  log_ok "安装完成: $DEVICE"
done

# ─── 完成 ──────────────────────────────────────────────────────

echo ""
log_ok "全部完成！"
