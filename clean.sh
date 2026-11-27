#!/system/bin/sh
# HMAPLUS 一次性清理入口（手动 / 自动共用，完成后立即退出）
# 用法:
#   sh clean.sh full        全量清理 HMA 黑名单（跳过白名单）
#   sh clean.sh pkg <包名>  仅清理指定包名（跳过白名单）
#   sh clean.sh lists       仅刷新 blacklist.json 与统计，不删除
# 常驻服务只负责监听 / 过滤 / 排队，不直接删除目录；真正删除都在这里。
export PATH=/system/bin:/system/xbin:/data/adb/magisk:/data/adb/ksu/bin:$PATH

MOD_DIR="/data/adb/modules/HMAPLUS"
WEB_DIR="$MOD_DIR/webroot"
M_BASE="/data/media/0/Android"
CONF_PATH=$(ls -d /data/misc/*hide_my_applist*/config.json 2>/dev/null | head -n1)
LOCAL_WHITE="$WEB_DIR/WhiteList_web.json"
CLEANED_FILE="$MOD_DIR/.cleaned_count"
STATS_FILE="$WEB_DIR/stats.json"
BLACKLIST_FILE="$WEB_DIR/blacklist.json"
LOG_FILE="$WEB_DIR/hmaplusa_log.txt"
LOG_MAX_BYTES=131072
LOCK="$MOD_DIR/.clean.lock"
COMPONENT="CLN"

mkdir -p "$WEB_DIR" 2>/dev/null

# --- 单实例保护：已有清理进程在跑则等待（最多 5 秒），避免队列事件被丢弃 ---
if [ -f "$LOCK" ]; then
    OLD_PID=$(cat "$LOCK" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$OLD_PID" ] && [ "$OLD_PID" != "$$" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        WAIT_N=0
        while [ "$WAIT_N" -lt 5 ] && kill -0 "$OLD_PID" 2>/dev/null; do
            sleep 1
            WAIT_N=$((WAIT_N + 1))
        done
        if [ -f "$LOCK" ] && kill -0 "$OLD_PID" 2>/dev/null; then
            exit 0
        fi
    fi
fi
echo $$ > "$LOCK" 2>/dev/null
trap 'rm -f "$LOCK"' EXIT

# --- 统一日志格式：[时间] [级别] [来源] 消息，按大小轮转 ---
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

# --- 读取白名单 ---
load_whitelist() {
    WHITE_LIST=""
    [ -f "$LOCAL_WHITE" ] || return 0
    local raw
    raw=$(cat "$LOCAL_WHITE" 2>/dev/null | tr -d '\n\r ')
    case "$raw" in
        \[*\])
            WHITE_LIST=$(printf '%s' "$raw" | tr -d '[]"' | tr ',' '\n' \
                | sed 's/[^a-zA-Z0-9._-]//g' | grep '\.' | tr '\n' ' ')
            ;;
    esac
    return 0
}

is_whitelisted() {
    case " $WHITE_LIST " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

# --- 读取 HMA 黑名单并写出 blacklist.json 供 WebUI ---
load_blacklist() {
    BLACK_LIST=""
    if [ -n "$CONF_PATH" ] && [ -f "$CONF_PATH" ]; then
        BLACK_LIST=$(cat "$CONF_PATH" 2>/dev/null | tr -d '\n\r ' \
            | grep -o '{"isWhitelist":false[^}]*}' \
            | grep -o '"appList":\[[^]]*\]' \
            | sed 's/"appList":\[//;s/\]//' | tr ',' '\n' \
            | sed 's/[^a-zA-Z0-9._-]//g' | grep '\.')
    fi
    local json="[" first=1 p
    for p in $BLACK_LIST; do
        [ -z "$p" ] && continue
        if [ $first -eq 1 ]; then first=0; else json="$json,"; fi
        json="$json\"$p\""
    done
    json="$json]"
    printf '%s\n' "$json" > "$BLACKLIST_FILE" 2>/dev/null
    chmod 666 "$BLACKLIST_FILE" 2>/dev/null
}

count_nonempty() {
    local n
    n=$(printf '%s' "$1" | wc -w | tr -d ' ')
    [ -z "$n" ] && n=0
    echo "$n"
}

load_cleaned() {
    if [ -f "$CLEANED_FILE" ]; then
        CLEANED_COUNT=$(cat "$CLEANED_FILE" 2>/dev/null | tr -d '[:space:]')
        [ -z "$CLEANED_COUNT" ] && CLEANED_COUNT=0
    else
        CLEANED_COUNT=0
    fi
}

write_stats() {
    load_cleaned
    local bl wl
    bl=$(count_nonempty "$BLACK_LIST")
    wl=$(count_nonempty "$WHITE_LIST")
    printf '{"pid":%s,"blacklist":%s,"whitelist":%s,"cleaned":%s}\n' \
        "$$" "$bl" "$wl" "$CLEANED_COUNT" > "$STATS_FILE" 2>/dev/null
    chmod 666 "$STATS_FILE" 2>/dev/null
}

# 清理单个包的 data / obb / media 目录，输出成功清理的目录数
clean_pkg_dirs() {
    local pkg=$1 n=0 sub
    for sub in data obb media; do
        if [ -d "$M_BASE/$sub/$pkg" ]; then
            if rm -rf "$M_BASE/$sub/$pkg" 2>/dev/null; then
                log_line INFO "已清理 $pkg ($sub)"
                n=$((n + 1))
            else
                log_line ERROR "清理失败 $pkg ($sub)"
            fi
        fi
    done
    echo "$n"
}

MODE=${1:-full}
load_whitelist
load_blacklist
load_cleaned

ROUND=0
case "$MODE" in
    full)
        FULL_T0=$(date +%s)
        FULL_TOTAL=$(count_nonempty "$BLACK_LIST")
        FULL_SKIP=0
        log_line INFO "全量清理开始 · 黑名单 ${FULL_TOTAL} 个（进程 PID $$）"
        for pkg in $BLACK_LIST; do
            [ -z "$pkg" ] && continue
            if is_whitelisted "$pkg"; then
                FULL_SKIP=$((FULL_SKIP + 1))
                continue
            fi
            n=$(clean_pkg_dirs "$pkg")
            ROUND=$((ROUND + n))
        done
        FULL_DUR=$(( $(date +%s) - FULL_T0 ))
        log_line INFO "全量清理结束 · 清理 ${ROUND} 项 · 白名单跳过 ${FULL_SKIP} 个 · 耗时 ${FULL_DUR}s"
        ;;
    pkg)
        TARGET=$(printf '%s' "${2:-}" | tr -cd 'a-zA-Z0-9._-')
        if [ -z "$TARGET" ]; then
            write_stats
            exit 0
        fi
        if is_whitelisted "$TARGET"; then
            log_line INFO "单包跳过 · $TARGET 在白名单"
        else
            log_line INFO "单包清理开始 · $TARGET（进程 PID $$）"
            n=$(clean_pkg_dirs "$TARGET")
            ROUND=$((ROUND + n))
            if [ "$n" -eq 0 ]; then
                log_line INFO "$TARGET 无 data/obb/media 目录，无需清理"
            fi
        fi
        ;;
    lists)
        # 仅刷新列表与统计，不删除任何目录
        ;;
    *)
        log_line ERROR "未知清理模式: $MODE"
        write_stats
        exit 1
        ;;
esac

if [ "$ROUND" -gt 0 ]; then
    CLEANED_COUNT=$((CLEANED_COUNT + ROUND))
    echo "$CLEANED_COUNT" > "$CLEANED_FILE" 2>/dev/null
    chmod 666 "$CLEANED_FILE" 2>/dev/null
fi
[ "$MODE" = "pkg" ] && log_line INFO "单包清理结束 · 清理 $ROUND 项"
write_stats
exit 0
