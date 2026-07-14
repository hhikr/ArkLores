#!/usr/bin/env bash
#
# ArkLores — 移动端一键配置、构建与安装脚本
#
# 用法:
#   ./tools/setup.sh                    # 进入交互模式（默认）
#   ./tools/setup.sh --interactive      # 强制进入交互模式
#   ./tools/setup.sh --help             # 查看命令行帮助
#   ./tools/setup.sh --with-gamedata --gamedata-source=/path/to/ArknightsGameData
#
set -euo pipefail

# ─── 常量 ────────────────────────────────────────────────────────

readonly PROG="$(basename "$0")"
readonly PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly FLUTTER_DEFAULT="$HOME/flutter"
readonly ANDROID_DEFAULT="$HOME/Android/Sdk"
readonly CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
readonly APP_ID="com.arklores.arklores"
readonly DEFAULT_GAMEDATA_SOURCE="/tmp/ArkLores-ArknightsGameData"
readonly DEFAULT_GAMEDATA_PORT="8765"
readonly DEFAULT_GAMEDATA_OUTPUT="build/gamedata_mobile"

# ─── 颜色输出 ────────────────────────────────────────────────────

RED='\033[0;31m';     GREEN='\033[0;32m'
YELLOW='\033[1;33m';  CYAN='\033[0;36m';  BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${CYAN}•${NC} $1"; }
log_ok()   { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_err()  { echo -e "${RED}✗${NC} $1"; }
log_step() { echo -e "\n${CYAN}==>${NC} ${BOLD}$1${NC}"; }

# ─── 帮助文档 ────────────────────────────────────────────────────

usage() {
  cat <<EOF
用法: $PROG [选项]

选项:
  -i, --interactive      强制进入交互式菜单模式（无参数运行时的默认行为）
  -a, --action <动作>    指定执行的行为，用逗号分隔多个值。
                         可选值: uninstall (卸载), build (构建), install (安装)
                         默认值: uninstall,build,install
  -p, --platform <平台>  指定目标平台。可选值: android, ios。默认值: android
  -m, --mode <模式>      指定构建模式。可选值: debug, release。默认值: debug
  -t, --target <目标>    指定部署目标（仅对 iOS 有效）。可选值: device (真机), simulator (模拟器)。默认值: device
      --with-gamedata    构建/配置 GameData 主知识库下载参数，并注入到 App
      --gamedata-source <路径>
                         ArknightsGameData 社区解包仓库路径。默认优先使用:
                         $DEFAULT_GAMEDATA_SOURCE
      --gamedata-url <URL>
                         直接使用已有 arklores_gamedata_zh.db.gz 下载地址，不本地构建
      --gamedata-sha <SHA256>
                         压缩 DB 的 SHA256；未提供且本地构建时自动计算
      --gamedata-port <端口>
                         本地临时 HTTP 服务端口。默认: $DEFAULT_GAMEDATA_PORT
      --gamedata-story-limit <N>
                         仅导入 N 个 story txt 进行快速 smoke DB。默认: 0，即全量导入
  -h, --help             显示帮助信息

示例:
  ./tools/setup.sh                                            # 交互式菜单运行
  ./tools/setup.sh -a build -p android                        # 仅构建 Android 包
  ./tools/setup.sh -a uninstall,install                       # 卸载并重新安装（使用已有包）
  ./tools/setup.sh --with-gamedata                            # 自动构建并提供 GameData 临时下载
  ./tools/setup.sh --gamedata-url https://.../db.gz --gamedata-sha <sha>
  ./tools/setup.sh -p ios -t simulator                        # iOS 模拟器构建与部署
EOF
  exit 0
}

# ─── Android SDK 自动安装 ────────────────────────────────────────

install_android_sdk() {
  mkdir -p "$ANDROID_HOME"
  pushd "$ANDROID_HOME" > /dev/null

  # 下载命令行工具
  log_info "正在从 Google 下载 Android 命令行工具..."
  wget -q --show-progress "$CMDLINE_TOOLS_URL" -O cmdline-tools.zip
  unzip -q cmdline-tools.zip
  rm cmdline-tools.zip

  # 整理目录结构（sdkmanager 要求工具位于 cmdline-tools/latest/）
  mkdir -p cmdline-tools/latest
  if [ -d cmdline-tools/bin ]; then
    mv cmdline-tools/bin cmdline-tools/latest/
    mv cmdline-tools/lib cmdline-tools/latest/
    for f in cmdline-tools/*; do
      [ -f "$f" ] && mv "$f" cmdline-tools/latest/
    done 2>/dev/null || true
  fi

  SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"

  # 接受许可证
  log_info "正在接受 Android SDK 许可证..."
  yes | "$SDKMANAGER" --sdk_root="$ANDROID_HOME" --licenses

  # 安装必要组件
  log_info "正在安装必要组件: platform-tools, platforms;android-34, build-tools;34.0.0..."
  "$SDKMANAGER" --sdk_root="$ANDROID_HOME" \
    "platform-tools" \
    "platforms;android-34" \
    "build-tools;34.0.0"

  # Flutter Android 许可证
  log_info "正在接受 Flutter 侧的 Android 许可证..."
  "$FLUTTER" doctor --android-licenses

  popd > /dev/null
  log_ok "Android SDK 配置完成: $ANDROID_HOME"
}

# ─── GameData 临时 release asset 准备 ────────────────────────────

sha256_file() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum &>/dev/null; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    log_err "未找到 sha256sum 或 shasum，无法计算 GameData DB 校验值。"
    exit 1
  fi
}

detect_host_ip() {
  if command -v ip &>/dev/null; then
    ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'
  elif command -v ipconfig &>/dev/null; then
    ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true
  elif command -v hostname &>/dev/null; then
    hostname -I 2>/dev/null | awk '{print $1}'
  fi
}

start_gamedata_http_server() {
  local serve_dir="$1"
  local port="$2"
  local pid_file="$PROJECT_ROOT/build/gamedata_http.pid"
  local log_file="$PROJECT_ROOT/build/gamedata_http.log"

  mkdir -p "$PROJECT_ROOT/build"
  if [ -f "$pid_file" ]; then
    local old_pid
    old_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      log_ok "复用已运行的 GameData HTTP 服务: pid=$old_pid"
      return
    fi
  fi

  if ! command -v python3 &>/dev/null; then
    log_err "未找到 python3，无法启动临时 HTTP 服务。"
    exit 1
  fi

  log_info "正在启动 GameData 临时 HTTP 服务: $serve_dir (port $port)"
  (
    cd "$serve_dir"
    nohup python3 -m http.server "$port" --bind 0.0.0.0 > "$log_file" 2>&1 &
    echo $! > "$pid_file"
  )
  sleep 1
  local pid
  pid="$(cat "$pid_file")"
  if ! kill -0 "$pid" 2>/dev/null; then
    log_err "GameData HTTP 服务启动失败，日志: $log_file"
    exit 1
  fi
  log_ok "GameData HTTP 服务已启动: pid=$pid, log=$log_file"
}

prepare_gamedata_defines() {
  if [ "$WITH_GAMEDATA" != true ] && [ -z "$GAMEDATA_URL" ]; then
    return
  fi
  WITH_GAMEDATA=true

  if [ -n "$GAMEDATA_URL" ]; then
    if [ -z "$GAMEDATA_SHA" ]; then
      log_warn "已提供 GameData URL 但未提供 SHA256；App 将跳过压缩包校验。"
    fi
    return
  fi

  if [ -z "$GAMEDATA_SOURCE" ]; then
    if [ -d "$DEFAULT_GAMEDATA_SOURCE" ]; then
      GAMEDATA_SOURCE="$DEFAULT_GAMEDATA_SOURCE"
    else
      log_err "未指定 --gamedata-source，且默认路径不存在: $DEFAULT_GAMEDATA_SOURCE"
      exit 1
    fi
  fi
  if [ ! -d "$GAMEDATA_SOURCE/zh_CN/gamedata" ]; then
    log_err "GameData source 无效，缺少 zh_CN/gamedata: $GAMEDATA_SOURCE"
    exit 1
  fi

  local output_dir="$PROJECT_ROOT/$GAMEDATA_OUTPUT"
  local db_path="$output_dir/arklores_gamedata_zh.db"
  local gz_path="$output_dir/arklores_gamedata_zh.db.gz"

  log_step "准备 GameData 主知识库临时下载资产"
  log_info "source: $GAMEDATA_SOURCE"
  log_info "output: $output_dir"
  "$FLUTTER_HOME/bin/dart" run tools/build_gamedata_database.dart \
    --arknights-source="$GAMEDATA_SOURCE" \
    --output="$output_dir" \
    --story-limit="$GAMEDATA_STORY_LIMIT" \
    --force

  log_info "正在压缩 GameData DB..."
  gzip -c "$db_path" > "$gz_path"
  GAMEDATA_SHA="$(sha256_file "$gz_path")"

  local host_ip
  host_ip="$(detect_host_ip)"
  if [ -z "$host_ip" ]; then
    log_err "无法自动检测本机局域网 IP。请改用 --gamedata-url 手动指定下载地址。"
    exit 1
  fi

  start_gamedata_http_server "$output_dir" "$GAMEDATA_PORT"
  GAMEDATA_URL="http://$host_ip:$GAMEDATA_PORT/arklores_gamedata_zh.db.gz"
  log_ok "GameData 下载 URL: $GAMEDATA_URL"
  log_ok "GameData SHA256: $GAMEDATA_SHA"
}

# ─── 命令行参数解析 ──────────────────────────────────────────────

ACTIONS=""
PLATFORM=""
BUILD_MODE=""
DEPLOY_TARGET=""
FORCE_INTERACTIVE=false
WITH_GAMEDATA=false
GAMEDATA_SOURCE="${GAMEDATA_SOURCE:-}"
GAMEDATA_URL="${GAMEDATA_URL:-}"
GAMEDATA_SHA="${GAMEDATA_SHA:-}"
GAMEDATA_PORT="${GAMEDATA_PORT:-$DEFAULT_GAMEDATA_PORT}"
GAMEDATA_OUTPUT="${GAMEDATA_OUTPUT:-$DEFAULT_GAMEDATA_OUTPUT}"
GAMEDATA_STORY_LIMIT="${GAMEDATA_STORY_LIMIT:-0}"

# 临时解析参数以检测帮助或交互式标记
for arg in "$@"; do
  if [ "$arg" = "--help" ] || [ "$arg" = "-h" ]; then usage; fi
  if [ "$arg" = "--interactive" ] || [ "$arg" = "-i" ]; then FORCE_INTERACTIVE=true; fi
done

# 解析标准选项
while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--action)
      ACTIONS="$2"
      shift 2
      ;;
    -p|--platform)
      PLATFORM="$2"
      shift 2
      ;;
    -m|--mode)
      BUILD_MODE="$2"
      shift 2
      ;;
    -t|--target)
      DEPLOY_TARGET="$2"
      shift 2
      ;;
    --with-gamedata)
      WITH_GAMEDATA=true
      shift
      ;;
    --gamedata-source)
      GAMEDATA_SOURCE="$2"
      WITH_GAMEDATA=true
      shift 2
      ;;
    --gamedata-source=*)
      GAMEDATA_SOURCE="${1#--gamedata-source=}"
      WITH_GAMEDATA=true
      shift
      ;;
    --gamedata-url)
      GAMEDATA_URL="$2"
      WITH_GAMEDATA=true
      shift 2
      ;;
    --gamedata-url=*)
      GAMEDATA_URL="${1#--gamedata-url=}"
      WITH_GAMEDATA=true
      shift
      ;;
    --gamedata-sha)
      GAMEDATA_SHA="$2"
      shift 2
      ;;
    --gamedata-sha=*)
      GAMEDATA_SHA="${1#--gamedata-sha=}"
      shift
      ;;
    --gamedata-port)
      GAMEDATA_PORT="$2"
      shift 2
      ;;
    --gamedata-port=*)
      GAMEDATA_PORT="${1#--gamedata-port=}"
      shift
      ;;
    --gamedata-story-limit)
      GAMEDATA_STORY_LIMIT="$2"
      shift 2
      ;;
    --gamedata-story-limit=*)
      GAMEDATA_STORY_LIMIT="${1#--gamedata-story-limit=}"
      shift
      ;;
    -i|--interactive)
      FORCE_INTERACTIVE=true
      shift
      ;;
    *)
      log_err "未知参数: $1"
      echo "可以使用 --help 查看详细用法。"
      exit 1
      ;;
  esac
done

# ─── 交互菜单模式 ────────────────────────────────────────────────

if [ -z "$ACTIONS" ] && [ -z "$PLATFORM" ] && [ -z "$BUILD_MODE" ] && [ -z "$DEPLOY_TARGET" ] || [ "$FORCE_INTERACTIVE" = true ]; then
  log_step "ArkLores 移动端部署配置助手"

  # 1. 选择行为
  echo -e "${BOLD}1. 请选择要执行的行为（多选，用空格分隔，直接回车默认执行全部 [1 2 3]）:${NC}"
  echo "   1) 卸载手机上的旧版本 (Uninstall)"
  echo "   2) 构建安装包 (Build)"
  echo "   3) 安装到设备 (Install)"
  read -r -p "   请输入选择: " action_input
  action_input="${action_input:-1 2 3}"
  
  ACTIONS=""
  for opt in $action_input; do
    case "$opt" in
      1) ACTIONS="${ACTIONS:+$ACTIONS,}uninstall" ;;
      2) ACTIONS="${ACTIONS:+$ACTIONS,}build" ;;
      3) ACTIONS="${ACTIONS:+$ACTIONS,}install" ;;
      *) log_warn "忽略未知选项: $opt" ;;
    esac
  done
  if [ -z "$ACTIONS" ]; then
    log_err "未选择任何有效行为，脚本退出。"
    exit 1
  fi

  # 2. 选择平台
  echo -e "\n${BOLD}2. 请选择目标平台:${NC}"
  echo "   1) Android (默认)"
  echo "   2) iOS"
  read -r -p "   请输入选择 [1]: " plat_input
  plat_input="${plat_input:-1}"
  case "$plat_input" in
    1) PLATFORM="android" ;;
    2) PLATFORM="ios" ;;
    *) log_warn "未知选择，默认设为 Android"; PLATFORM="android" ;;
  esac

  # 3. 选择构建模式
  echo -e "\n${BOLD}3. 请选择构建模式:${NC}"
  echo "   1) Debug (默认，体积大，支持联调，免签名)"
  echo "   2) Release (体积小速度快，已做 Tree-shake，需要签名)"
  read -r -p "   请输入选择 [1]: " mode_input
  mode_input="${mode_input:-1}"
  case "$mode_input" in
    1) BUILD_MODE="debug" ;;
    2) BUILD_MODE="release" ;;
    *) log_warn "未知选择，默认设为 Debug"; BUILD_MODE="debug" ;;
  esac

  # 4. 选择是否配置 GameData 主知识库临时下载
  echo -e "\n${BOLD}4. 是否自动准备 GameData 主知识库下载参数?${NC}"
  echo "   1) 是，使用本地 ArknightsGameData 构建 .db.gz 并启动临时 HTTP 服务"
  echo "   2) 否，仅构建/安装 App (默认)"
  read -r -p "   请输入选择 [2]: " gamedata_input
  gamedata_input="${gamedata_input:-2}"
  case "$gamedata_input" in
    1)
      WITH_GAMEDATA=true
      read -r -p "   ArknightsGameData 路径 [$DEFAULT_GAMEDATA_SOURCE]: " gamedata_source_input
      GAMEDATA_SOURCE="${gamedata_source_input:-$DEFAULT_GAMEDATA_SOURCE}"
      read -r -p "   临时 HTTP 端口 [$DEFAULT_GAMEDATA_PORT]: " gamedata_port_input
      GAMEDATA_PORT="${gamedata_port_input:-$DEFAULT_GAMEDATA_PORT}"
      ;;
    2) WITH_GAMEDATA=false ;;
    *) log_warn "未知选择，默认不配置 GameData"; WITH_GAMEDATA=false ;;
  esac

  # 5. 若为 iOS，选择部署目标
  DEPLOY_TARGET="device"
  if [ "$PLATFORM" = "ios" ]; then
    echo -e "\n${BOLD}5. 请选择 iOS 部署目标:${NC}"
    echo "   1) 真机设备 (Device) (默认)"
    echo "   2) 模拟器 (Simulator)"
    read -r -p "   请输入选择 [1]: " target_input
    target_input="${target_input:-1}"
    case "$target_input" in
      1) DEPLOY_TARGET="device" ;;
      2) DEPLOY_TARGET="simulator" ;;
      *) log_warn "未知选择，默认设为真机"; DEPLOY_TARGET="device" ;;
    esac
  fi
else
  # 填充未指定的默认值
  ACTIONS="${ACTIONS:-uninstall,build,install}"
  PLATFORM="${PLATFORM:-android}"
  BUILD_MODE="${BUILD_MODE:-debug}"
  DEPLOY_TARGET="${DEPLOY_TARGET:-device}"
fi

# 参数规范化与校验
PLATFORM="$(echo "$PLATFORM" | tr '[:upper:]' '[:lower:]')"
BUILD_MODE="$(echo "$BUILD_MODE" | tr '[:upper:]' '[:lower:]')"
DEPLOY_TARGET="$(echo "$DEPLOY_TARGET" | tr '[:upper:]' '[:lower:]')"

if [[ ! "$PLATFORM" =~ ^(android|ios)$ ]]; then
  log_err "不支持的平台: $PLATFORM (仅限 android 或 ios)"
  exit 1
fi
if [[ ! "$BUILD_MODE" =~ ^(debug|release)$ ]]; then
  log_err "不支持的构建模式: $BUILD_MODE (仅限 debug 或 release)"
  exit 1
fi
if [[ ! "$DEPLOY_TARGET" =~ ^(device|simulator)$ ]]; then
  log_err "不支持的部署目标: $DEPLOY_TARGET (仅限 device 或 simulator)"
  exit 1
fi
if [[ ! "$GAMEDATA_PORT" =~ ^[0-9]+$ ]]; then
  log_err "不支持的 GameData HTTP 端口: $GAMEDATA_PORT"
  exit 1
fi
if [[ ! "$GAMEDATA_STORY_LIMIT" =~ ^[0-9]+$ ]]; then
  log_err "不支持的 GameData story limit: $GAMEDATA_STORY_LIMIT"
  exit 1
fi

# 解析动作标记
DO_UNINSTALL=false
DO_BUILD=false
DO_INSTALL=false
IFS=',' read -ra ADDR <<< "$ACTIONS"
for act in "${ADDR[@]}"; do
  case "$act" in
    uninstall) DO_UNINSTALL=true ;;
    build) DO_BUILD=true ;;
    install) DO_INSTALL=true ;;
    *) log_err "未知动作: $act"; exit 1 ;;
  esac
done

# ─── 确认执行配置 ────────────────────────────────────────────────

log_step "执行配置总览"
echo -e "   目标平台  : ${BOLD}${PLATFORM}${NC}"
echo -e "   构建模式  : ${BOLD}${BUILD_MODE}${NC}"
[ "$PLATFORM" = "ios" ] && echo -e "   部署目标  : ${BOLD}${DEPLOY_TARGET}${NC}"
echo -n -e "   执行动作  : "
[ "$DO_UNINSTALL" = true ] && echo -n -e "[${YELLOW}卸载旧版本${NC}] "
[ "$DO_BUILD" = true ] && echo -n -e "[${GREEN}编译安装包${NC}] "
[ "$DO_INSTALL" = true ] && echo -n -e "[${CYAN}安装至设备${NC}]"
echo ""
if [ "$WITH_GAMEDATA" = true ] || [ -n "$GAMEDATA_URL" ]; then
  echo -e "   GameData : ${BOLD}启用${NC}"
  [ -n "$GAMEDATA_SOURCE" ] && echo -e "   数据源    : ${BOLD}${GAMEDATA_SOURCE}${NC}"
  [ -n "$GAMEDATA_URL" ] && echo -e "   下载 URL : ${BOLD}${GAMEDATA_URL}${NC}"
fi

# ─── 路径检查与环境准备 ──────────────────────────────────────────

FLUTTER_HOME="${FLUTTER_HOME:-$FLUTTER_DEFAULT}"
FLUTTER="$FLUTTER_HOME/bin/flutter"
ANDROID_HOME="${ANDROID_HOME:-$ANDROID_DEFAULT}"

# 系统类型检测
SYSTEM_OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
if [ "$PLATFORM" = "ios" ] && [ "$SYSTEM_OS" != "darwin" ]; then
  log_warn "警告: 构建/部署 iOS 需要 macOS 系统环境。"
  log_warn "检测到当前操作系统为 ${SYSTEM_OS}，后续 iOS 操作很可能会因缺少 Xcode 核心工具而失败！"
fi

log_step "检查环境依赖"

# 1. 检查 Flutter SDK
if [ ! -f "$FLUTTER" ]; then
  log_err "未找到 Flutter SDK（期望路径: $FLUTTER）"
  log_info "请修改 FLUTTER_HOME 环境变量，或者将 Flutter 安装在 $FLUTTER_DEFAULT"
  exit 1
fi
log_ok "Flutter SDK 路径: $FLUTTER_HOME"

prepare_gamedata_defines

DART_DEFINE_ARGS=()
if [ "$WITH_GAMEDATA" = true ]; then
  DART_DEFINE_ARGS+=("--dart-define=ARKLORES_GAMEDATA_DB_URL=$GAMEDATA_URL")
  if [ -n "$GAMEDATA_SHA" ]; then
    DART_DEFINE_ARGS+=("--dart-define=ARKLORES_GAMEDATA_DB_SHA256=$GAMEDATA_SHA")
  fi
  log_ok "Flutter 构建将注入 GameData 下载参数"
fi

# 2. 检查 Java (仅 Android 需要)
if [ "$PLATFORM" = "android" ]; then
  if command -v java &>/dev/null; then
    JAVA_VER="$(java -version 2>&1 | head -1)"
    log_ok "Java 运行环境: $JAVA_VER"
  else
    log_warn "未检测到 Java (JDK)，正在尝试通过包管理器安装 jdk21-openjdk..."
    if command -v pacman &>/dev/null; then
      sudo pacman -S --noconfirm jdk21-openjdk
    elif command -v apt-get &>/dev/null; then
      sudo apt-get update && sudo apt-get install -y openjdk-21-jdk
    elif command -v brew &>/dev/null; then
      brew install openjdk@21
    else
      log_err "无法自动安装 Java，请手动安装 JDK 并配置环境变量后再运行此脚本。"
      exit 1
    fi
    log_ok "Java 安装完成"
  fi

  # 3. 检查 Android SDK
  if [ -d "$ANDROID_HOME/platform-tools" ]; then
    log_ok "Android SDK 路径: $ANDROID_HOME"
  else
    log_warn "未找到 Android SDK，开始进行全自动下载与安装..."
    install_android_sdk
  fi
fi

# ─── 第三方工具链检查（卸载与安装时需要） ──────────────────────────

ADB="$ANDROID_HOME/platform-tools/adb"
IDEVICEINSTALLER=""
SIMCTL=""

if [ "$DO_UNINSTALL" = true ] || [ "$DO_INSTALL" = true ]; then
  if [ "$PLATFORM" = "android" ]; then
    if [ ! -f "$ADB" ]; then
      log_err "未找到 adb 工具，路径为: $ADB"
      exit 1
    fi
  elif [ "$PLATFORM" = "ios" ]; then
    if [ "$DEPLOY_TARGET" = "simulator" ]; then
      if command -v xcrun &>/dev/null; then
        SIMCTL="xcrun simctl"
        log_ok "iOS 模拟器管理工具: xcrun simctl"
      else
        log_err "未找到 xcrun 工具，请确保安装了 Xcode Command Line Tools"
        exit 1
      fi
    else
      if command -v ideviceinstaller &>/dev/null; then
        IDEVICEINSTALLER="ideviceinstaller"
        log_ok "iOS 设备部署工具: ideviceinstaller"
      elif command -v ios-deploy &>/dev/null; then
        IDEVICEINSTALLER="ios-deploy"
        log_ok "iOS 设备部署工具: ios-deploy"
      else
        log_warn "未检测到 ideviceinstaller 或 ios-deploy，如果需要部署到真机，建议运行:"
        log_warn "  brew install ideviceinstaller"
      fi
    fi
  fi
fi

# ─── 执行第一阶段：卸载旧版本 ────────────────────────────────────

if [ "$DO_UNINSTALL" = true ]; then
  log_step "执行动作：卸载旧版本"
  if [ "$PLATFORM" = "android" ]; then
    DEVICES=$("$ADB" devices | awk 'NR>1 && /device$/ {print $1}')
    if [ -z "$DEVICES" ]; then
      log_warn "未检测到已连接的 Android 设备，跳过卸载阶段。"
    else
      for DEVICE in $DEVICES; do
        log_info "正在从 Android 设备 $DEVICE 上卸载 $APP_ID ..."
        # 卸载失败可能因为本来就没装，因此允许报错
        "$ADB" -s "$DEVICE" uninstall "$APP_ID" || true
        log_ok "已向设备发送卸载指令: $DEVICE"
      done
    fi
  elif [ "$PLATFORM" = "ios" ]; then
    if [ "$DEPLOY_TARGET" = "simulator" ]; then
      log_info "正在从已启动的 iOS 模拟器中卸载 $APP_ID ..."
      $SIMCTL uninstall booted "$APP_ID" || true
      log_ok "已向模拟器发送卸载指令"
    else
      if [ -n "$IDEVICEINSTALLER" ]; then
        log_info "正在从 iOS 真机中卸载 $APP_ID ..."
        if [ "$IDEVICEINSTALLER" = "ideviceinstaller" ]; then
          $IDEVICEINSTALLER -U "$APP_ID" || true
        else
          $IDEVICEINSTALLER --uninstall_id "$APP_ID" || true
        fi
        log_ok "已向真机发送卸载指令"
      else
        log_warn "缺少 iOS 真机部署工具，跳过真机卸载。"
      fi
    fi
  fi
fi

# ─── 执行第二阶段：编译安装包 ────────────────────────────────────

APK_PATH="build/app/outputs/flutter-apk/app-${BUILD_MODE}.apk"
IOS_APP_DIR="build/ios/iphoneos/Runner.app"
IOS_SIM_DIR="build/ios/iphonesimulator/Runner.app"

if [ "$DO_BUILD" = true ]; then
  log_step "执行动作：编译安装包 (${BUILD_MODE})"
  cd "$PROJECT_ROOT"
  
  # 执行 Flutter 编译
  if [ "$PLATFORM" = "android" ]; then
    log_info "正在运行 flutter build apk --${BUILD_MODE} ..."
    "$FLUTTER" build apk --"${BUILD_MODE}" "${DART_DEFINE_ARGS[@]}"
    if [ ! -f "$APK_PATH" ]; then
      log_err "编译失败：未找到生成的 APK $APK_PATH"
      exit 1
    fi
    APK_SIZE="$(du -h "$APK_PATH" | cut -f1)"
    log_ok "Android 安装包编译成功: $APK_PATH (${APK_SIZE})"
  elif [ "$PLATFORM" = "ios" ]; then
    if [ "$DEPLOY_TARGET" = "simulator" ]; then
      log_info "正在运行 flutter build ios --simulator --debug ..."
      # 模拟器仅支持 debug 模式进行真机测试
      "$FLUTTER" build ios --simulator --debug "${DART_DEFINE_ARGS[@]}"
      if [ ! -d "$IOS_SIM_DIR" ]; then
        log_err "编译失败：未找到生成的模拟器 App 目录 $IOS_SIM_DIR"
        exit 1
      fi
      log_ok "iOS 模拟器安装包编译成功: $IOS_SIM_DIR"
    else
      log_info "正在运行 flutter build ios --${BUILD_MODE} ..."
      if [ "$BUILD_MODE" = "debug" ]; then
        # 调试模式下为防证书报错可使用 no-codesign 编译
        "$FLUTTER" build ios --debug --no-codesign "${DART_DEFINE_ARGS[@]}" || "$FLUTTER" build ios --debug "${DART_DEFINE_ARGS[@]}"
      else
        "$FLUTTER" build ios --release "${DART_DEFINE_ARGS[@]}"
      fi
      if [ ! -d "$IOS_APP_DIR" ]; then
        log_err "编译失败：未找到生成的真机 App 目录 $IOS_APP_DIR"
        exit 1
      fi
      log_ok "iOS 真机安装包编译成功: $IOS_APP_DIR"
    fi
  fi
fi

# ─── 执行第三阶段：安装到设备 ────────────────────────────────────

if [ "$DO_INSTALL" = true ]; then
  log_step "执行动作：安装到设备"
  if [ "$PLATFORM" = "android" ]; then
    if [ ! -f "$APK_PATH" ]; then
      log_err "未找到待安装的 Android 包: $APK_PATH，请先执行编译 (build)"
      exit 1
    fi
    DEVICES=$("$ADB" devices | awk 'NR>1 && /device$/ {print $1}')
    if [ -z "$DEVICES" ]; then
      log_warn "未检测到已连接的 Android 设备，跳过安装。"
      echo "  提示: 请开启手机的「USB 调试」并在连接后重试。安装包已生成于: $APK_PATH"
    else
      for DEVICE in $DEVICES; do
        log_info "正在安装到设备 $DEVICE ..."
        "$ADB" -s "$DEVICE" install -r "$APK_PATH"
        log_ok "安装成功: $DEVICE"
      done
    fi
  elif [ "$PLATFORM" = "ios" ]; then
    if [ "$DEPLOY_TARGET" = "simulator" ]; then
      if [ ! -d "$IOS_SIM_DIR" ]; then
        log_err "未找到待安装的 iOS 模拟器包: $IOS_SIM_DIR，请先执行编译 (build)"
        exit 1
      fi
      # 检测是否有启动的模拟器
      if $SIMCTL list devices | grep -q "Booted"; then
        log_info "正在安装到已启动的 iOS 模拟器..."
        $SIMCTL install booted "$IOS_SIM_DIR"
        log_ok "iOS 模拟器安装成功！"
      else
        log_warn "没有检测到已启动的 iOS 模拟器，无法执行安装。"
        log_info "请在 Mac 终端运行 'open -a Simulator' 启动模拟器后再重新运行此脚本。"
      fi
    else
      if [ ! -d "$IOS_APP_DIR" ]; then
        log_err "未找到待安装的 iOS 真机包: $IOS_APP_DIR，请先执行编译 (build)"
        exit 1
      fi
      if [ -n "$IDEVICEINSTALLER" ]; then
        log_info "正在安装到 iOS 真机设备..."
        if [ "$IDEVICEINSTALLER" = "ideviceinstaller" ]; then
          $IDEVICEINSTALLER -i "$IOS_APP_DIR"
        else
          # ios-deploy 安装
          $IDEVICEINSTALLER --bundle "$IOS_APP_DIR"
        fi
        log_ok "iOS 真机安装成功！"
      else
        log_warn "缺少 iOS 真机部署工具 (ideviceinstaller / ios-deploy)，跳过安装阶段。"
        echo "  真机 App 目录已就绪，请手动部署: $IOS_APP_DIR"
      fi
    fi
  fi
fi

echo -e "\n${GREEN}✓ 全部操作执行完成！${NC}"
if [ "$WITH_GAMEDATA" = true ]; then
  echo -e "${CYAN}•${NC} GameData 下载地址已注入 App: ${BOLD}${GAMEDATA_URL}${NC}"
  echo -e "${CYAN}•${NC} 真机测试：打开 ArkLores → Settings → Knowledge Base → GameData 主知识库 → 下载/更新。"
  if [ -f "$PROJECT_ROOT/build/gamedata_http.pid" ]; then
    echo -e "${CYAN}•${NC} 临时 HTTP 服务 pid: $(cat "$PROJECT_ROOT/build/gamedata_http.pid")"
  fi
fi
