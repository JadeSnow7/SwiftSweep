#!/bin/bash
# =============================================================================
# SwiftSweep Demo Recording Script
# =============================================================================
# 自动录制 SwiftSweep 应用的演示视频
# 需要：macOS 13+, SwiftSweep App 已构建
# 
# 用法：
#   ./scripts/record_demo.sh [output_name]
#
# 输出：
#   ~/Desktop/<output_name>.mov (默认: SwiftSweep_Demo_<timestamp>.mov)
# =============================================================================

set -euo pipefail

# 配置
APP_NAME="SwiftSweepApp"
APP_PROCESS_NAME="${APP_PROCESS_NAME:-$APP_NAME}"
APP_BUNDLE_ID="com.swiftsweep.app"
BUILD_DIR=".build/debug"
OUTPUT_DIR="$HOME/Desktop"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_NAME="${1:-SwiftSweep_Demo_$TIMESTAMP}"
OUTPUT_FILE="$OUTPUT_DIR/$OUTPUT_NAME.mov"
RECORD_PID=""
MANUAL_RECORDING=false
WINDOW_ONLY_MODE=false  # 是否仅录制窗口区域

# 录制参数（可通过环境变量覆盖）
CAPTURE_DEVICE="${CAPTURE_DEVICE:-}"
CAPTURE_FRAMERATE="${CAPTURE_FRAMERATE:-30}"
CAPTURE_SIZE="${CAPTURE_SIZE:-}"
FFMPEG_LOGLEVEL="${FFMPEG_LOGLEVEL:-warning}"
FFMPEG_PRESET="${FFMPEG_PRESET:-ultrafast}"

# 窗口与节奏（可通过环境变量覆盖）
WINDOW_POS_X="${WINDOW_POS_X:-100}"
WINDOW_POS_Y="${WINDOW_POS_Y:-50}"
WINDOW_WIDTH="${WINDOW_WIDTH:-1280}"
WINDOW_HEIGHT="${WINDOW_HEIGHT:-800}"
DEMO_SPEED="${DEMO_SPEED:-1.0}" # 1.0 正常, <1 更快, >1 更慢
NAV_DELAY="${NAV_DELAY:-1.8}"
SECTION_LINGER="${SECTION_LINGER:-1.4}"
SCROLL_STEPS_DEFAULT="${SCROLL_STEPS_DEFAULT:-6}"
SCROLL_STEP_DELAY="${SCROLL_STEP_DELAY:-0.15}"
PRE_ROLL="${PRE_ROLL:-1.5}"

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# 计算缩放后的延迟
calc_delay() {
    awk -v s="$1" -v f="$DEMO_SPEED" 'BEGIN { printf "%.2f", s * f }'
}

sleep_scaled() {
    local delay
    delay=$(calc_delay "$1")
    sleep "$delay"
}

# 辅助：检查辅助功能权限
ensure_accessibility() {
    local enabled
    if ! enabled=$(osascript -e 'tell application "System Events" to get UI elements enabled' 2>/dev/null); then
        log_warn "无法获取辅助功能权限状态，请检查系统设置"
        exit 1
    fi
    if [ "$enabled" != "true" ]; then
        log_warn "需要开启辅助功能权限才能自动化操作 UI"
        echo "请在 系统设置 -> 隐私与安全性 -> 辅助功能 中允许终端/脚本控制"
        exit 1
    fi
}

focus_app() {
    osascript <<EOF >/dev/null 2>&1 || return 1
tell application "System Events"
    if exists (process "$APP_PROCESS_NAME") then
        tell process "$APP_PROCESS_NAME"
            set frontmost to true
        end tell
    end if
end tell
EOF
}

wait_for_app() {
    local attempts="${1:-20}"
    local delay="${2:-1}"
    local i
    for ((i=1; i<=attempts; i++)); do
        local exists
        exists=$(osascript -e 'tell application "System Events" to (exists process "'"$APP_PROCESS_NAME"'")' 2>/dev/null || echo "false")
        if [ "$exists" = "true" ]; then
            return 0
        fi
        sleep_scaled "$delay"
    done
    return 1
}

wait_for_window() {
    local attempts="${1:-20}"
    local delay="${2:-1}"
    local i
    for ((i=1; i<=attempts; i++)); do
        local exists
        exists=$(osascript -e 'tell application "System Events" to tell process "'"$APP_PROCESS_NAME"'" to (exists window 1)' 2>/dev/null || echo "false")
        if [ "$exists" = "true" ]; then
            return 0
        fi
        sleep_scaled "$delay"
    done
    return 1
}

detect_capture_device() {
    local output
    local device
    output=$(ffmpeg -f avfoundation -list_devices true -i "" 2>&1 || true)
    device=$(printf '%s\n' "$output" | awk '/Capture screen/ {gsub(/[\[\]]/, "", $5); print $5; exit}')
    if [ -n "$device" ]; then
        echo "$device"
    else
        echo "1"
    fi
}

manual_record_prompt() {
    MANUAL_RECORDING=true
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  请手动开始屏幕录制：                                         ║"
    echo "║  1. 按 Shift+Cmd+5 打开录制工具                               ║"
    echo "║  2. 选择录制区域或整个屏幕                                     ║"
    echo "║  3. 点击\"录制\"                                               ║"
    echo "║  4. 按 Enter 键继续脚本...                                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    read -r
}

get_window_id() {
    # 获取 SwiftSweep 窗口的 Window ID
    local window_id
    window_id=$(osascript <<EOF 2>/dev/null
tell application "System Events"
    tell process "$APP_PROCESS_NAME"
        if exists window 1 then
            return id of window 1
        end if
    end tell
end tell
return ""
EOF
    )
    echo "$window_id"
}

get_window_bounds() {
    # 获取窗口的位置和大小 {x, y, width, height}
    osascript <<EOF 2>/dev/null
tell application "System Events"
    tell process "$APP_PROCESS_NAME"
        if exists window 1 then
            set winPos to position of window 1
            set winSize to size of window 1
            return (item 1 of winPos as text) & ":" & (item 2 of winPos as text) & ":" & (item 1 of winSize as text) & ":" & (item 2 of winSize as text)
        end if
    end tell
end tell
return ""
EOF
}

start_recording() {
    log_info "开始窗口录制..."
    log_info "输出文件: $OUTPUT_FILE"

    # 方案1: 使用 screencapture 录制指定窗口 (macOS 原生，质量最佳)
    local window_id
    window_id=$(get_window_id)
    
    if [ -n "$window_id" ] && [ "$window_id" != "" ]; then
        log_info "检测到窗口 ID: $window_id"
        # screencapture -l 可以录制指定窗口，但只支持截图
        # 对于视频录制，使用 ffmpeg 裁剪方案
    fi

    # 方案2: 使用 ffmpeg 录制并裁剪到窗口区域
    if command -v ffmpeg &> /dev/null; then
        local device
        device="${CAPTURE_DEVICE:-}"
        if [ -z "$device" ]; then
            device=$(detect_capture_device)
        fi

        # 获取窗口位置和大小用于裁剪
        local bounds
        bounds=$(get_window_bounds)
        
        local crop_filter=""
        if [ -n "$bounds" ] && [ "$bounds" != "" ]; then
            IFS=':' read -r wx wy ww wh <<< "$bounds"
            # 确保尺寸是偶数（H.264 要求）
            ww=$((ww / 2 * 2))
            wh=$((wh / 2 * 2))
            crop_filter="-vf crop=${ww}:${wh}:${wx}:${wy}"
            log_info "窗口区域: ${ww}x${wh}+${wx}+${wy}"
            WINDOW_ONLY_MODE=true
        else
            log_warn "无法获取窗口边界，将录制全屏"
            WINDOW_ONLY_MODE=false
        fi

        local input_opts=(
            -f avfoundation
            -framerate "$CAPTURE_FRAMERATE"
            -capture_cursor 1
            -capture_mouse_clicks 1
        )

        # 构建 ffmpeg 命令
        if [ -n "$crop_filter" ]; then
            ffmpeg -loglevel "$FFMPEG_LOGLEVEL" -y \
                "${input_opts[@]}" -i "${device}:none" \
                $crop_filter \
                -c:v libx264 -preset "$FFMPEG_PRESET" -crf 18 -pix_fmt yuv420p \
                -movflags +faststart "$OUTPUT_FILE" &
        else
            ffmpeg -loglevel "$FFMPEG_LOGLEVEL" -y \
                "${input_opts[@]}" -i "${device}:none" \
                -c:v libx264 -preset "$FFMPEG_PRESET" -crf 18 -pix_fmt yuv420p \
                -movflags +faststart "$OUTPUT_FILE" &
        fi
        RECORD_PID=$!

        sleep_scaled 1
        if ! kill -0 "$RECORD_PID" 2>/dev/null; then
            RECORD_PID=""
            log_warn "ffmpeg 启动失败，切换为手动录制"
            manual_record_prompt
        else
            if [ "$WINDOW_ONLY_MODE" = true ]; then
                log_success "使用 ffmpeg 窗口录制中 (PID: $RECORD_PID, 仅录制 SwiftSweep 窗口)"
            else
                log_success "使用 ffmpeg 全屏录制中 (PID: $RECORD_PID)"
            fi
        fi
    else
        log_warn "未安装 ffmpeg，将使用 macOS 内置录制"
        manual_record_prompt
    fi
}

stop_recording() {
    if [ -n "$RECORD_PID" ] && kill -0 "$RECORD_PID" 2>/dev/null; then
        log_info "停止录制..."
        kill -INT "$RECORD_PID" 2>/dev/null || true
        wait "$RECORD_PID" 2>/dev/null || true
        RECORD_PID=""
        sleep_scaled 1
    fi
}

# 清理函数
cleanup() {
    stop_recording
    # 关闭 App（可选）
    # osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
}
trap cleanup EXIT

# =============================================================================
# 辅助函数：使用 AppleScript 导航
# =============================================================================
navigate_to() {
    local view_name="$1"
    local delay="${2:-$NAV_DELAY}"
    log_info "导航到: $view_name"
    focus_app || true
    local result
    if ! result=$(osascript <<EOF 2>/dev/null
tell application "System Events"
    tell process "$APP_PROCESS_NAME"
        set frontmost to true
        delay 0.3
        set clicked to false
        try
            click static text "$view_name" of window 1
            set clicked to true
        on error
            try
                click (first row of outline 1 of scroll area 1 of splitter group 1 of window 1 whose value of static text 1 contains "$view_name")
                set clicked to true
            on error
                try
                    click (first button of window 1 whose title contains "$view_name")
                    set clicked to true
                end try
            end try
        end try
        if clicked then return "ok"
        return "fail"
    end tell
end tell
EOF
    ); then
        log_warn "未能定位侧边栏项: $view_name"
    elif [ "$result" != "ok" ]; then
        log_warn "未能定位侧边栏项: $view_name"
    fi
    sleep_scaled "$delay"
}

scroll_content() {
    local direction="${1:-down}"
    local amount="${2:-$SCROLL_STEPS_DEFAULT}"
    local step_delay="${3:-$SCROLL_STEP_DELAY}"
    local scaled_delay
    scaled_delay=$(calc_delay "$step_delay")
    focus_app || true
    if ! osascript <<EOF >/dev/null 2>&1
tell application "System Events"
    tell process "$APP_PROCESS_NAME"
        set frontmost to true
        repeat $amount times
            if "$direction" = "down" then
                key code 125 -- Down arrow
            else
                key code 126 -- Up arrow
            end if
            delay $scaled_delay
        end repeat
    end tell
end tell
EOF
    then
        log_warn "滚动失败"
    fi
}

show_section() {
    local name="$1"
    local linger="${2:-$SECTION_LINGER}"
    local scroll_down="${3:-$SCROLL_STEPS_DEFAULT}"
    local scroll_up="${4:-2}"
    navigate_to "$name"
    sleep_scaled "$linger"
    if [ "$scroll_down" -gt 0 ]; then
        scroll_content down "$scroll_down"
        sleep_scaled 0.4
    fi
    if [ "$scroll_up" -gt 0 ]; then
        scroll_content up "$scroll_up"
        sleep_scaled 0.4
    fi
}

# =============================================================================
# 交互辅助函数：展示动效
# =============================================================================

# 点击指定按钮
click_button() {
    local button_name="$1"
    local delay="${2:-0.8}"
    log_info "点击按钮: $button_name"
    focus_app || true
    osascript <<EOF >/dev/null 2>&1 || true
tell application "System Events"
    tell process "$APP_PROCESS_NAME"
        set frontmost to true
        delay 0.2
        try
            click (first button of window 1 whose title contains "$button_name" or description contains "$button_name")
        on error
            try
                click (first button of group 1 of window 1 whose title contains "$button_name")
            end try
        end try
    end tell
end tell
EOF
    sleep_scaled "$delay"
}

# 点击工具栏按钮
click_toolbar_button() {
    local button_index="$1"
    local delay="${2:-0.8}"
    log_info "点击工具栏按钮 #$button_index"
    focus_app || true
    osascript <<EOF >/dev/null 2>&1 || true
tell application "System Events"
    tell process "$APP_PROCESS_NAME"
        set frontmost to true
        delay 0.2
        try
            click button $button_index of toolbar 1 of window 1
        end try
    end tell
end tell
EOF
    sleep_scaled "$delay"
}

# 模拟鼠标移动（展示悬停效果）
hover_over_area() {
    local x="$1"
    local y="$2"
    local delay="${3:-0.5}"
    log_info "鼠标移动到: ($x, $y)"
    # 使用 cliclick 如果可用，否则跳过
    if command -v cliclick &> /dev/null; then
        cliclick m:"$x,$y"
    fi
    sleep_scaled "$delay"
}

# 触发扫描操作
trigger_scan() {
    local delay="${1:-3.0}"
    log_info "触发扫描..."
    focus_app || true
    # 尝试点击 Scan/扫描 按钮
    osascript <<EOF >/dev/null 2>&1 || true
tell application "System Events"
    tell process "$APP_PROCESS_NAME"
        set frontmost to true
        delay 0.2
        try
            click (first button of window 1 whose title contains "Scan" or title contains "扫描" or description contains "scan")
        on error
            try
                -- 尝试快捷键 Cmd+R
                keystroke "r" using command down
            end try
        end try
    end tell
end tell
EOF
    sleep_scaled "$delay"
}

# 选中/取消选中列表项
toggle_item() {
    local item_index="${1:-1}"
    local delay="${2:-0.6}"
    log_info "切换列表项 #$item_index"
    focus_app || true
    osascript <<EOF >/dev/null 2>&1 || true
tell application "System Events"
    tell process "$APP_PROCESS_NAME"
        set frontmost to true
        delay 0.2
        try
            click checkbox $item_index of scroll area 1 of group 1 of window 1
        on error
            try
                -- 使用方向键+空格选择
                repeat $item_index times
                    key code 125 -- Down
                    delay 0.15
                end repeat
                key code 49 -- Space
            end try
        end try
    end tell
end tell
EOF
    sleep_scaled "$delay"
}

# 展示刷新动画
show_refresh_animation() {
    local delay="${1:-2.0}"
    log_info "展示刷新动画..."
    focus_app || true
    # 使用 Cmd+R 刷新
    osascript <<EOF >/dev/null 2>&1 || true
tell application "System Events"
    tell process "$APP_PROCESS_NAME"
        set frontmost to true
        keystroke "r" using command down
    end tell
end tell
EOF
    sleep_scaled "$delay"
}

# 展示搜索功能
show_search() {
    local search_text="${1:-test}"
    local delay="${2:-1.5}"
    log_info "展示搜索: $search_text"
    focus_app || true
    osascript <<EOF >/dev/null 2>&1 || true
tell application "System Events"
    tell process "$APP_PROCESS_NAME"
        set frontmost to true
        -- 触发搜索 Cmd+F
        keystroke "f" using command down
        delay 0.3
        keystroke "$search_text"
    end tell
end tell
EOF
    sleep_scaled "$delay"
    # 清除搜索
    osascript <<EOF >/dev/null 2>&1 || true
tell application "System Events"
    tell process "$APP_PROCESS_NAME"
        key code 53 -- Escape
    end tell
end tell
EOF
    sleep_scaled 0.5
}

# 展示排序切换
toggle_sort() {
    local delay="${1:-0.8}"
    log_info "切换排序..."
    focus_app || true
    osascript <<EOF >/dev/null 2>&1 || true
tell application "System Events"
    tell process "$APP_PROCESS_NAME"
        set frontmost to true
        try
            click (first pop up button of window 1)
            delay 0.3
            key code 125 -- Down
            delay 0.2
            key code 36 -- Return
        end try
    end tell
end tell
EOF
    sleep_scaled "$delay"
}

# 平滑滚动展示内容
smooth_scroll() {
    local direction="${1:-down}"
    local duration="${2:-2.0}"
    local steps="${3:-10}"
    log_info "平滑滚动 ($direction)..."
    local step_delay
    step_delay=$(awk -v d="$duration" -v s="$steps" 'BEGIN { printf "%.2f", d / s }')
    focus_app || true
    for ((i=1; i<=steps; i++)); do
        osascript <<EOF >/dev/null 2>&1 || true
tell application "System Events"
    tell process "$APP_PROCESS_NAME"
        if "$direction" = "down" then
            key code 125
        else
            key code 126
        end if
    end tell
end tell
EOF
        sleep "$step_delay"
    done
}

# 展开/折叠分组
toggle_disclosure() {
    local group_name="$1"
    local delay="${2:-0.6}"
    log_info "切换分组: $group_name"
    focus_app || true
    osascript <<EOF >/dev/null 2>&1 || true
tell application "System Events"
    tell process "$APP_PROCESS_NAME"
        set frontmost to true
        try
            click (first disclosure triangle of outline 1 of scroll area 1 of splitter group 1 of window 1 whose value of static text 1 of parent contains "$group_name")
        end try
    end tell
end tell
EOF
    sleep_scaled "$delay"
}

# =============================================================================
# 主流程
# =============================================================================

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           SwiftSweep 演示视频录制脚本                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 1. 检查 App 是否存在
log_info "检查 SwiftSweep App..."
APP_EXECUTABLE=""
USE_EXECUTABLE=false

if [ -d "$BUILD_DIR/$APP_NAME.app" ]; then
    APP_PATH="$BUILD_DIR/$APP_NAME.app"
elif [ -d "/Applications/$APP_NAME.app" ]; then
    APP_PATH="/Applications/$APP_NAME.app"
elif [ -x "$BUILD_DIR/$APP_NAME" ]; then
    # swift build 只生成可执行文件，不生成 .app bundle
    APP_EXECUTABLE="$BUILD_DIR/$APP_NAME"
    USE_EXECUTABLE=true
    log_info "找到 SwiftPM 构建的可执行文件"
else
    log_warn "未找到已构建的 App，尝试构建..."
    swift build
    if [ -x "$BUILD_DIR/$APP_NAME" ]; then
        APP_EXECUTABLE="$BUILD_DIR/$APP_NAME"
        USE_EXECUTABLE=true
    else
        log_warn "构建完成但未找到可执行文件"
        exit 1
    fi
fi

if [ "$USE_EXECUTABLE" = true ]; then
    log_success "可执行文件路径: $APP_EXECUTABLE"
else
    log_success "App 路径: $APP_PATH"
fi

# 2. 检查辅助功能权限
ensure_accessibility

# 3. 启动 App
log_info "启动 SwiftSweep..."
if [ "$USE_EXECUTABLE" = true ]; then
    # 直接启动可执行文件（后台运行）
    "$APP_EXECUTABLE" &
    sleep_scaled 1
else
    open "$APP_PATH"
fi
sleep_scaled 2

# 4. 等待 App 完全加载
log_info "等待 App 加载完成..."
if ! wait_for_app 20 1; then
    log_warn "未检测到应用进程，请检查是否启动成功"
    exit 1
fi
if ! wait_for_window 20 1; then
    log_warn "未检测到应用窗口，请检查是否启动成功"
    exit 1
fi
sleep_scaled 1.5

# 5. 调整窗口大小和位置
log_info "调整窗口大小..."
if ! osascript <<EOF >/dev/null 2>&1
tell application "System Events"
    tell process "$APP_PROCESS_NAME"
        set frontmost to true
        try
            set position of window 1 to {$WINDOW_POS_X, $WINDOW_POS_Y}
            set size of window 1 to {$WINDOW_WIDTH, $WINDOW_HEIGHT}
        end try
    end tell
end tell
EOF
then
    log_warn "调整窗口大小失败"
fi
sleep_scaled 1

# 6. 开始录制
start_recording
sleep_scaled "$PRE_ROLL"

# =============================================================================
# 7. 演示流程（完整展示功能和动效）
# =============================================================================

log_info "开始演示流程..."

# -----------------------------------------------------------------------------
# 7.1 Status 页面 (首页概览)
# -----------------------------------------------------------------------------
log_info "【第1部分】Status 状态概览"
navigate_to "Status" 1.5
sleep_scaled 1.0

# 展示状态卡片和环形图动画
smooth_scroll down 1.5 6
sleep_scaled 1.0
smooth_scroll up 1.0 3

# 触发刷新展示加载动画
show_refresh_animation 2.5

sleep_scaled 1.5

# -----------------------------------------------------------------------------
# 7.2 Insights 智能洞察页面
# -----------------------------------------------------------------------------
log_info "【第2部分】Insights 智能洞察"
navigate_to "Insights" 1.5
sleep_scaled 1.2

# 展示推荐卡片
smooth_scroll down 2.0 8
sleep_scaled 0.8
smooth_scroll up 1.5 4

# 点击展开某个推荐项（如果有的话）
toggle_disclosure "Recommendation" 0.8
sleep_scaled 1.0

# -----------------------------------------------------------------------------
# 7.3 Clean 清理页面
# -----------------------------------------------------------------------------
log_info "【第3部分】Clean 智能清理"
navigate_to "Clean" 1.5
sleep_scaled 1.0

# 触发扫描展示扫描动画
trigger_scan 3.5

# 展示扫描结果列表
smooth_scroll down 2.0 6
sleep_scaled 0.8

# 选中一些清理项
toggle_item 1 0.5
toggle_item 2 0.5
toggle_item 3 0.5
sleep_scaled 0.8

# 滚动回顶部
smooth_scroll up 1.0 4
sleep_scaled 1.0

# -----------------------------------------------------------------------------
# 7.4 Optimize 优化页面
# -----------------------------------------------------------------------------
log_info "【第4部分】Optimize 系统优化"
navigate_to "Optimize" 1.5
sleep_scaled 1.2

# 展示优化选项
scroll_content down 4
sleep_scaled 1.0
scroll_content up 2
sleep_scaled 0.8

# -----------------------------------------------------------------------------
# 7.5 Applications 应用管理页面
# -----------------------------------------------------------------------------
log_info "【第5部分】Applications 应用管理"
navigate_to "Applications" 1.5
sleep_scaled 1.0

# 触发应用列表加载
trigger_scan 2.5

# 展示应用列表
smooth_scroll down 2.5 10
sleep_scaled 0.8

# 展示排序功能
toggle_sort 1.0

smooth_scroll up 1.5 5
sleep_scaled 0.8

# -----------------------------------------------------------------------------
# 7.6 Media Analyzer 媒体分析页面
# -----------------------------------------------------------------------------
log_info "【第6部分】Media Analyzer 媒体分析"
navigate_to "Media" 1.5
sleep_scaled 1.0

# 触发媒体扫描
trigger_scan 3.0

# 展示媒体文件列表
smooth_scroll down 2.0 8
sleep_scaled 1.0

# 选中一些大文件
toggle_item 1 0.4
toggle_item 2 0.4
sleep_scaled 0.8

smooth_scroll up 1.0 4
sleep_scaled 0.8

# -----------------------------------------------------------------------------
# 7.7 Time Machine Snapshots 页面
# -----------------------------------------------------------------------------
log_info "【第7部分】Snapshot 时间机器快照"
navigate_to "Snapshot" 1.5
sleep_scaled 1.2

# 展示快照列表
scroll_content down 4
sleep_scaled 1.0
scroll_content up 2
sleep_scaled 0.8

# -----------------------------------------------------------------------------
# 7.8 Packages 包管理页面
# -----------------------------------------------------------------------------
log_info "【第8部分】Packages 开发者包管理"
navigate_to "Packages" 1.5
sleep_scaled 1.0

# 触发包扫描
trigger_scan 2.5

# 展示包列表
smooth_scroll down 2.0 8
sleep_scaled 0.8

# 展开某个包类别
toggle_disclosure "npm" 0.6
toggle_disclosure "pip" 0.6
sleep_scaled 0.8

smooth_scroll up 1.0 4
sleep_scaled 0.8

# -----------------------------------------------------------------------------
# 7.9 Ghost Buster 残留清理页面
# -----------------------------------------------------------------------------
log_info "【第9部分】Ghost Buster 残留清理"
navigate_to "Ghost" 1.5
sleep_scaled 1.2

# 触发扫描
trigger_scan 2.5

scroll_content down 4
sleep_scaled 0.8
scroll_content up 2
sleep_scaled 0.8

# -----------------------------------------------------------------------------
# 7.10 Settings 设置页面
# -----------------------------------------------------------------------------
log_info "【第10部分】Settings 设置"
navigate_to "Settings" 1.5
sleep_scaled 1.0

# 展示设置选项
smooth_scroll down 2.0 8
sleep_scaled 1.0

# 演示切换开关（不实际改变设置）
# toggle_item 1 0.4

smooth_scroll up 1.5 6
sleep_scaled 0.8

# -----------------------------------------------------------------------------
# 7.11 回到首页，完美收尾
# -----------------------------------------------------------------------------
log_info "【收尾】返回 Status 首页"
navigate_to "Status" 1.5
sleep_scaled 1.0

# 最后刷新一次展示完整状态
show_refresh_animation 2.0
sleep_scaled 1.5

# =============================================================================
# 8. 停止录制
# =============================================================================

log_info "演示完成，停止录制..."
sleep_scaled 1.5
stop_recording

# =============================================================================
# 9. 完成
# =============================================================================

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                      录制完成！                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
    log_success "视频文件: $OUTPUT_FILE"
    log_success "文件大小: $FILE_SIZE"
    echo ""
    log_info "后续处理建议："
    echo "  1. 使用 iMovie 或 Final Cut Pro 添加标题和配乐"
    echo "  2. 使用 ffmpeg 压缩: ffmpeg -i '$OUTPUT_FILE' -c:v libx264 -crf 23 output_compressed.mp4"
    echo "  3. 上传到 YouTube 或 Bilibili"
else
    log_warn "未检测到输出文件，请检查录制是否成功"
    if [ "$MANUAL_RECORDING" = true ]; then
        log_info "如果使用了手动录制，请在录制工具中停止并确认保存位置"
    elif ! command -v ffmpeg &> /dev/null; then
        log_info "如果使用了手动录制，视频将保存在默认位置"
    fi
fi

echo ""
