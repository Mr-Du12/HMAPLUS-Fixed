#!/system/bin/sh
# HMAPLUS 常驻守护进程
# 职责：等待存储挂载 → 初始化 WebUI 数据 → 启动冷启动监听 → 排队 → 调起一次性清理进程
# 不直接删除目录；所有删除统一交给 clean.sh（一次性进程，完成即退出）。
export PATH=/system/bin:/system/xbin:/data/adb/magisk:/data/adb/ksu/bin:$PATH

MOD_DIR="/data/adb/modules/HMAPLUS"
WEB_DIR="$MOD_DIR/webroot"
M_BASE="/data/media/0/Android"
LOCAL_WHITE="$WEB_DIR/WhiteList_web.json"
AUTO_FILE="$WEB_DIR/auto_clean.json"
PID_FILE="$WEB_DIR/pid.txt"
MODULE_INFO_FILE="$WEB_DIR/module_info.json"
LOG_FILE="$WEB_DIR/hmaplusa_log.txt"
QUEUE="$MOD_DIR/.clean_queue"

# --- 单实例保护：杀掉旧的 HMAPLUS/service.sh 进程，精确匹配不误伤 ---
SERVICE_LOCK="$MOD_DIR/.service.lock"

# --- 原子单实例锁：目录创建成功才获得运行权，旧实例直接强杀 ---
acquire_single_instance() {
    local old
    if mkdir "$SERVICE_LOCK" 2>/dev/null; then
        printf '%s' "$$" > "$SERVICE_LOCK/pid" 2>/dev/null
        return 0
    fi
    old=$(cat "$SERVICE_LOCK/pid" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$old" ] && [ "$old" != "$$" ] && kill -0 "$old" 2>/dev/null; then
        kill -9 "$old" 2>/dev/null
        sleep 1
    fi
    rm -rf "$SERVICE_LOCK" 2>/dev/null
    mkdir "$SERVICE_LOCK" 2>/dev/null || exit 0
    printf '%s' "$$" > "$SERVICE_LOCK/pid" 2>/dev/null
}

kill_old_instances() {
    local cur=$$ par=$PPID p cmdline
    for p in /proc/[0-9]*; do
        p=${p##*/}
        [ "$p" = "$cur" ] && continue
        [ "$p" = "$par" ] && continue
        [ -f "/proc/$p/cmdline" ] || continue
        cmdline=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
        case "$cmdline" in
            *HMAPLUS/service.sh*)
                [ -d "/proc/$p" ] && kill -9 "$p" 2>/dev/null
                ;;
        esac
    done
}

# --- 统一日志格式：[时间] [级别] [来源] 消息，按大小轮转 ---
COMPONENT="SVC"
LOG_MAX_BYTES=131072

log_line() {
    local lvl=$1; shift
    local ts size
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    printf '[%s] [%s] [%s] %s\n' "$ts" "$lvl" "$COMPONENT" "$*" >> "$LOG_FILE" 2>/dev/null || return 0
    size=$(wc -c < "$LOG_FILE" 2>/dev/null | tr -d ' ')
    if [ -n "$size" ] && [ "$size" -gt "$LOG_MAX_BYTES" ]; then
        tail -n 600 "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null \
            && mv -f "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
    chmod 666 "$LOG_FILE" 2>/dev/null
}

# --- 导出模块信息（供 WebUI 关于页读取） ---
export_module_info() {
    local mod_prop="$MOD_DIR/module.prop"
    [ -f "$mod_prop" ] || return 0
    local name version author description
    name=$(grep '^name=' "$mod_prop" | cut -d= -f2-)
    version=$(grep '^version=' "$mod_prop" | cut -d= -f2-)
    author=$(grep '^author=' "$mod_prop" | cut -d= -f2-)
    description=$(grep '^description=' "$mod_prop" | cut -d= -f2-)
    name=$(printf '%s' "$name" | sed 's/\\/\\\\/g; s/"/\\"/g')
    version=$(printf '%s' "$version" | sed 's/\\/\\\\/g; s/"/\\"/g')
    author=$(printf '%s' "$author" | sed 's/\\/\\\\/g; s/"/\\"/g')
    description=$(printf '%s' "$description" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '{"name":"%s","version":"%s","author":"%s","description":"%s"}\n' \
        "$name" "$version" "$author" "$description" > "$MODULE_INFO_FILE" 2>/dev/null
    chmod 666 "$MODULE_INFO_FILE" 2>/dev/null
}

# --- 白名单默认保护 MT 管理器 ---
ensure_default_whitelist() {
    if [ ! -f "$LOCAL_WHITE" ] || [ ! -s "$LOCAL_WHITE" ]; then
        printf '["bin.mt.plus"]\n' > "$LOCAL_WHITE"
    elif ! grep -Fq '"bin.mt.plus"' "$LOCAL_WHITE" 2>/dev/null; then
        local ex
        ex=$(cat "$LOCAL_WHITE" 2>/dev/null | tr -d '\n\r ')
        if [ "$ex" = "[]" ]; then
            printf '["bin.mt.plus"]\n' > "$LOCAL_WHITE"
        else
            printf '%s\n' "${ex%\]},\"bin.mt.plus\"]" > "$LOCAL_WHITE"
        fi
    fi
    chmod 666 "$LOCAL_WHITE" 2>/dev/null
}

# --- 自动清理默认勾选 4 个应用 ---
ensure_default_auto() {
    if [ ! -f "$AUTO_FILE" ] || [ ! -s "$AUTO_FILE" ]; then
        printf '["com.maple.detect","luna.safe.luna","com.chunqiunativecheck","com.eltavine.duckdetector"]\n' > "$AUTO_FILE"
    fi
    chmod 666 "$AUTO_FILE" 2>/dev/null
}

# --- 开机第 10 秒：初始化 WebUI 数据（不清理） ---
init_web_data() {
    mkdir -p "$WEB_DIR" 2>/dev/null
    [ -f "$LOG_FILE" ] || : > "$LOG_FILE"
    chmod 666 "$LOG_FILE" 2>/dev/null
    ensure_default_whitelist
    ensure_default_auto
    pm list packages -3 --user 0 2>/dev/null | cut -d: -f2 | sort -u > "$WEB_DIR/app_raw.txt"
    chmod 666 "$WEB_DIR/app_raw.txt" 2>/dev/null
    [ -f "$MOD_DIR/.cleaned_count" ] || echo "0" > "$MOD_DIR/.cleaned_count"
    chmod 666 "$MOD_DIR/.cleaned_count" 2>/dev/null
    rm -f "$QUEUE" 2>/dev/null
    # 生成 blacklist.json / stats.json 供 WebUI 读取（不删除）
    sh "$MOD_DIR/clean.sh" lists >/dev/null 2>&1
    # 后台生成应用名称与原生图标，不阻塞启动流程
    sh "$MOD_DIR/appinfo.sh" >/dev/null 2>&1 &
}

# --- 从 am_proc_start / am_proc_died 行解析进程名（保留 :子进程 后缀） ---
# 必须保留后缀：检测类应用运行中会不停起停 :xxx 子进程，
# 若剥掉后缀会被误判成"应用打开/退出"，导致清理被反复触发。
parse_proc() {
    printf '%s' "$1" \
        | grep -oE '[a-zA-Z][a-zA-Z0-9._]*(\.[a-zA-Z0-9._]+)+(:[a-zA-Z0-9._]+)?' \
        | head -n1
}

# 该包是否仍有进程存活（含 :子进程）
pkg_running() {
    local pkg=$1 all
    all=$(cat /proc/[0-9]*/cmdline 2>/dev/null | tr '\0' '\n')
    [ -z "$all" ] && return 1
    printf '%s\n' "$all" | grep -qx "$pkg" 2>/dev/null && return 0
    printf '%s\n' "$all" | grep -q "^${pkg}:" 2>/dev/null && return 0
    return 1
}

# --- 目标应用启动判定：每次生命周期只触发一次全量清理 ---
PREV_EVENTS="$MOD_DIR/.proc_events"
ALIVE_FILE="$MOD_DIR/.launch_alive"

# 应用启动：上次触发后仍存活则跳过；否则记录并请求一次全量清理
queue_pkg() {
    local pkg=$1
    [ -z "$pkg" ] && return 0
    [ -f "$AUTO_FILE" ] || return 0
    grep -Fq "\"$pkg\"" "$AUTO_FILE" 2>/dev/null || return 0
    [ -f "$ALIVE_FILE" ] && grep -Fxq "$pkg" "$ALIVE_FILE" 2>/dev/null && return 0
    printf '%s\n' "$pkg" >> "$ALIVE_FILE"
    printf '%s\n' "$pkg" >> "$QUEUE"
    log_line INFO "检测到目标应用启动: $pkg，触发全量清理"
}

# 应用进程退出（划掉后台/被系统回收）：解除标记，下次打开可再次触发
release_pkg() {
    local pkg=$1
    [ -z "$pkg" ] && return 0
    [ -f "$ALIVE_FILE" ] || return 0
    grep -Fxq "$pkg" "$ALIVE_FILE" 2>/dev/null || return 0
    # 注意：grep 无匹配时返回 1，不能用 && 串联，否则只剩一条时无法清空
    grep -Fxv "$pkg" "$ALIVE_FILE" > "${ALIVE_FILE}.tmp" 2>/dev/null
    mv -f "${ALIVE_FILE}.tmp" "$ALIVE_FILE" 2>/dev/null
    chmod 666 "$ALIVE_FILE" 2>/dev/null
    log_line INFO "目标应用已退出: $pkg（再次打开可再次清理）"
}

# 兜底校验：标记中的应用若已无对应进程，视为已退出
verify_alive() {
    [ -s "$ALIVE_FILE" ] || return 0
    local pkg
    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        pkg_running "$pkg" || release_pkg "$pkg"
    done < "$ALIVE_FILE"
}

# --- 事件轮询：每 2 秒读取一次 events 缓冲，与上一批比对只取新增行 ---
# 只认应用主进程；:子进程 的启停一律忽略，避免运行中被反复触发清理。
poll_proc_events() {
    local dump newp line proc
    dump=$(logcat -b events -d -t 400 2>/dev/null | grep -aE 'am_proc_start|am_proc_died')
    [ -z "$dump" ] && return 0

    if [ -f "$PREV_EVENTS" ]; then
        newp=$(printf '%s\n' "$dump" | grep -Fxv -f "$PREV_EVENTS" 2>/dev/null)
    else
        newp="$dump"
    fi
    printf '%s\n' "$dump" > "${PREV_EVENTS}.tmp" 2>/dev/null \
        && mv -f "${PREV_EVENTS}.tmp" "$PREV_EVENTS" 2>/dev/null
    chmod 666 "$PREV_EVENTS" 2>/dev/null

    [ -z "$newp" ] && return 0

    printf '%s\n' "$newp" | while IFS= read -r line; do
        proc=$(parse_proc "$line")
        [ -z "$proc" ] && continue
        case "$proc" in
            *:*) continue ;;
        esac
        case "$line" in
            *am_proc_start*) queue_pkg "$proc" ;;
            *am_proc_died*)  pkg_running "$proc" || release_pkg "$proc" ;;
        esac
    done
}

# --- 启动事件监听：清空旧事件，避免开机历史事件被误触发 ---
init_proc_watch() {
    logcat -b events -c 2>/dev/null
    rm -f "$PREV_EVENTS" "$ALIVE_FILE" 2>/dev/null
    log_line INFO "自动清理监听已启动（事件轮询，每 2 秒）"
}

# --- 队列有任务即执行一次全量清理（覆盖所有黑名单应用） ---
drain_queue() {
    [ -s "$QUEUE" ] || return 0
    local trigger
    trigger=$(head -n1 "$QUEUE" 2>/dev/null)
    : > "$QUEUE"
    log_line INFO "由 $trigger 触发全量清理"
    sh "$MOD_DIR/clean.sh" full >/dev/null 2>&1
}

# ========== 启动流程 ==========
acquire_single_instance
trap 'rm -rf "$SERVICE_LOCK"' EXIT
kill_old_instances

# UID 内核隐藏：按已保存开关状态加载（与清理解耦，UID 功能不碰）
sh "$MOD_DIR/uid.sh" init >/dev/null 2>&1

# 等待存储挂载完成
until [ -d "/sdcard/Android" ]; do sleep 5; done

# 第 10 秒：初始化 WebUI 数据并启动监听
sleep 10
init_web_data
export_module_info
echo $$ > "$PID_FILE" 2>/dev/null
chmod 666 "$PID_FILE" 2>/dev/null
VER=$(grep '^version=' "$MOD_DIR/module.prop" 2>/dev/null | head -n1 | cut -d= -f2-)
AUTO_N=$(grep -o '"' "$AUTO_FILE" 2>/dev/null | wc -l | tr -d ' '); AUTO_N=$((AUTO_N / 2))
BL_N=$(grep -o '"' "$WEB_DIR/blacklist.json" 2>/dev/null | wc -l | tr -d ' '); BL_N=$((BL_N / 2))
WL_N=$(grep -o '"' "$WEB_DIR/WhiteList_web.json" 2>/dev/null | wc -l | tr -d ' '); WL_N=$((WL_N / 2))
log_line INFO "===== 服务启动 · v${VER:-?} · pid=$$ ====="
log_line INFO "配置 · 自动清理 ${AUTO_N} 个 · 黑名单 ${BL_N} 个 · 白名单 ${WL_N} 个"
if logcat -b events -d -t 1 >/dev/null 2>&1; then
    log_line INFO "logcat 事件读取正常"
else
    log_line ERROR "logcat 事件读取失败，自动清理将无法触发"
fi
init_proc_watch
WATCH_START=$(date +%s)
FIRST_FULL_DONE=0

# ========== 主循环：轮询启动事件 + 排空队列 + 周期刷新统计 ==========
TICK=0
while :; do
    poll_proc_events
    drain_queue

    # 启动约 50 秒后执行一次全量清理（后台执行，不阻塞事件监听）
    NOW=$(date +%s)
    if [ "$FIRST_FULL_DONE" -eq 0 ] && [ $((NOW - WATCH_START)) -ge 50 ]; then
        FIRST_FULL_DONE=1
        log_line INFO "首次全量清理开始"
        sh "$MOD_DIR/clean.sh" full >/dev/null 2>&1 &
    fi

    TICK=$((TICK + 1))
    # 每 30 秒兜底校验一次：应用已被回收则解除标记
    if [ $((TICK % 15)) -eq 0 ]; then
        verify_alive
    fi
    # 每 300 次（约 10 分钟）刷新一次列表与统计，不做清理
    if [ "$TICK" -ge 300 ]; then
        sh "$MOD_DIR/clean.sh" lists >/dev/null 2>&1
        TICK=0
    fi
    sleep 2
done
