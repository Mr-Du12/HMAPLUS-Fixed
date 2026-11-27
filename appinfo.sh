#!/system/bin/sh
# 应用信息生成器：通过 app_process 借用系统 PackageManager，
# 导出应用名称（apps_meta.json）与原生图标（icons/*.png）供 WebUI 使用。
# 失败不影响清理主流程，仅记录错误日志并让 WebUI 回退字母图标。
MOD_DIR=${0%/*}
WEB_DIR="$MOD_DIR/webroot"
HELPER="$MOD_DIR/tools/helper.jar"
LOG_FILE="$WEB_DIR/hmaplusa_log.txt"
META="$WEB_DIR/apps_meta.json"
COMPONENT="APP"
LOG_MAX_BYTES=131072

# 统一日志格式：[时间] [级别] [来源] 消息，按大小轮转
log_line() {
    local lvl=$1; shift
    local ts size
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    printf '[%s] [%s] [%s] %s\n' "$ts" "$lvl" "$COMPONENT" "$*" >> "$LOG_FILE" 2>/dev/null
    size=$(wc -c < "$LOG_FILE" 2>/dev/null | tr -d ' ')
    if [ -n "$size" ] && [ "$size" -gt "$LOG_MAX_BYTES" ]; then
        tail -n 600 "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null \
            && mv -f "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
    chmod 666 "$LOG_FILE" 2>/dev/null
}

[ -f "$HELPER" ] || exit 0

# 定位 app_process（部分精简 ROM 不在 PATH 里）
APP_PROC=""
if command -v app_process >/dev/null 2>&1; then
    APP_PROC="app_process"
elif [ -x /system/bin/app_process ]; then
    APP_PROC="/system/bin/app_process"
elif [ -x /system/bin/app_process64 ]; then
    APP_PROC="/system/bin/app_process64"
elif [ -x /system/bin/app_process32 ]; then
    APP_PROC="/system/bin/app_process32"
fi
[ -n "$APP_PROC" ] || exit 0

mkdir -p "$WEB_DIR/icons" 2>/dev/null
chmod 755 "$WEB_DIR/icons" 2>/dev/null

# 最多尝试 3 轮（开机阶段 PackageManager 可能尚未就绪）
try_gen() {
    "$APP_PROC" -Djava.class.path="$HELPER" "$1" com.hmaplus.AppLister "$WEB_DIR" 2>&1
}

attempt=0
while [ $attempt -lt 3 ]; do
    attempt=$((attempt + 1))

    OUT=$(try_gen /system/bin)
    RC=$?
    if [ $RC -eq 0 ] && [ -s "$META" ]; then
        chmod 666 "$META" 2>/dev/null
        chmod 666 "$WEB_DIR/apps_meta.build" 2>/dev/null
        chmod 666 "$WEB_DIR"/icons/*.png 2>/dev/null
        SUMMARY=$(printf '%s\n' "$OUT" | grep -a '完成:' | tail -n1 | sed 's/^\[AppLister\] //')
        log_line INFO "应用信息生成完成 · ${SUMMARY:-第 ${attempt} 轮}"
        exit 0
    fi

    # 退回根目录作为 cmd-dir 再试一次
    OUT2=$(try_gen /)
    RC2=$?
    if [ $RC2 -eq 0 ] && [ -s "$META" ]; then
        chmod 666 "$META" 2>/dev/null
        chmod 666 "$WEB_DIR/apps_meta.build" 2>/dev/null
        chmod 666 "$WEB_DIR"/icons/*.png 2>/dev/null
        SUMMARY=$(printf '%s\n' "$OUT2" | grep -a '完成:' | tail -n1 | sed 's/^\[AppLister\] //')
        log_line INFO "应用信息生成完成 · ${SUMMARY:-第 ${attempt} 轮}"
        exit 0
    fi

    # 仅失败时把 helper 原始输出逐行写入日志，便于排查
    if [ -n "$OUT" ]; then
        printf '%s\n' "$OUT" | while IFS= read -r l; do
            [ -n "$l" ] && log_line ERROR "helper: $l"
        done
    fi
    if [ -n "$OUT2" ]; then
        printf '%s\n' "$OUT2" | while IFS= read -r l; do
            [ -n "$l" ] && log_line ERROR "helper: $l"
        done
    fi

    sleep 5
done

log_line ERROR "应用信息生成失败（rc=${RC}/${RC2}），WebUI 回退字母图标"
exit 0
