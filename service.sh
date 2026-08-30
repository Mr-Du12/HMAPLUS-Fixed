#!/system/bin/sh

# --- 单实例保护：杀掉旧的 HMAPLUS/service.sh 进程 ---
# 只匹配包含 HMAPLUS/service.sh 完整路径的进程，避免误杀其他模块
kill_old_instances() {
    local current_pid=$$
    # 遍历 /proc 下所有进程，匹配命令行中包含 HMAPLUS/service.sh 的进程
    for pid_dir in /proc/[0-9]*; do
        local pid=${pid_dir##*/}
        [ "$pid" = "$current_pid" ] && continue
        local cmdline=""
        if [ -f "$pid_dir/cmdline" ]; then
            cmdline=$(cat "$pid_dir/cmdline" 2>/dev/null | tr '\0' ' ')
        fi
        # 精确匹配 HMAPLUS/service.sh 路径，不误伤其他模块的 service.sh
        case "$cmdline" in
            *HMAPLUS/service.sh*)
                # 确认进程还存在再杀，避免误杀
                if [ -d "/proc/$pid" ]; then
                    kill -9 "$pid" 2>/dev/null
                fi
                ;;
        esac
    done
}
# 环境配置
export PATH=/system/bin:/system/xbin:/data/adb/magisk:/data/adb/ksu/bin:$PATH
MOD_DIR="/data/adb/modules/HMAPLUS"
WEB_DIR="$MOD_DIR/webroot"
M_BASE="/data/media/0/Android"
CONF_PATH=$(ls -d /data/misc/*hide_my_applist*/config.json 2>/dev/null | head -n1)
LOCAL_WHITE="$WEB_DIR/WhiteList_web.json"
FLAG_FILE="$MOD_DIR/.need_clean"
PID_FILE="$WEB_DIR/pid.txt"
STATS_FILE="$WEB_DIR/stats.json"
CLEANED_FILE="$MOD_DIR/.cleaned_count"
BLACKLIST_FILE="$WEB_DIR/blacklist.json"
MODULE_INFO_FILE="$WEB_DIR/module_info.json"

# 缓存变量
LAST_CONF_TIME=0
LAST_WHITE_TIME=0
WHITE_LIST=""
CACHED_LIST=""
BLACKLIST_COUNT=0
WHITELIST_COUNT=0
CLEANED_COUNT=0

# --- 0. 写入PID ---
write_pid() {
    echo $$ > "$PID_FILE"
    chmod 666 "$PID_FILE"
}

# --- 0.5 导出模块信息（供WebUI关于页面动态读取） ---
export_module_info() {
    local mod_prop="$MOD_DIR/module.prop"
    [ ! -f "$mod_prop" ] && return

    local name=$(grep '^name=' "$mod_prop" | cut -d= -f2-)
    local version=$(grep '^version=' "$mod_prop" | cut -d= -f2-)
    local author=$(grep '^author=' "$mod_prop" | cut -d= -f2-)
    local description=$(grep '^description=' "$mod_prop" | cut -d= -f2-)

    # 转义JSON特殊字符
    name=$(echo "$name" | sed 's/\\/\\\\/g; s/"/\\"/g')
    version=$(echo "$version" | sed 's/\\/\\\\/g; s/"/\\"/g')
    author=$(echo "$author" | sed 's/\\/\\\\/g; s/"/\\"/g')
    description=$(echo "$description" | sed 's/\\/\\\\/g; s/"/\\"/g')

    cat > "$MODULE_INFO_FILE" << EOF
{"name":"$name","version":"$version","author":"$author","description":"$description"}
EOF
    chmod 666 "$MODULE_INFO_FILE"
}

# --- 1. 数据初始化 ---
init_web_data() {
    mkdir -p "$WEB_DIR"

    # 白名单默认包含 bin.mt.plus
    if [ ! -f "$LOCAL_WHITE" ] || [ ! -s "$LOCAL_WHITE" ]; then
        echo '["bin.mt.plus"]' > "$LOCAL_WHITE"
    else
        # 确保已存在的情况下也包含 bin.mt.plus
        if ! grep -q "bin.mt.plus" "$LOCAL_WHITE" 2>/dev/null; then
            local existing=$(cat "$LOCAL_WHITE" | tr -d '\n\r ')
            if echo "$existing" | grep -q '^\[.*\]$'; then
                # 在数组末尾插入 bin.mt.plus
                local new_json=$(echo "$existing" | sed 's/\]$//' | sed 's/\[\[\(\)/[/' )
                if [ "$existing" = "[]" ]; then
                    echo '["bin.mt.plus"]' > "$LOCAL_WHITE"
                else
                    echo "${existing%\]},\"bin.mt.plus\"]" > "$LOCAL_WHITE"
                fi
            else
                echo '["bin.mt.plus"]' > "$LOCAL_WHITE"
            fi
        fi
    fi
    chmod 666 "$LOCAL_WHITE"

    pm list packages -3 --user 0 | cut -d: -f2 | sort -u > "$WEB_DIR/app_raw.txt"
    chmod 666 "$WEB_DIR/app_raw.txt"
    [ ! -f "$CLEANED_FILE" ] && echo "0" > "$CLEANED_FILE"
    chmod 666 "$CLEANED_FILE"
}

# --- 2. 解析黑名单/白名单 ---
refresh_lists() {
    [ ! -f "$LOCAL_WHITE" ] && init_web_data
    [ ! -f "$CONF_PATH" ] && return 1

    local c_mtime=$(stat -c %Y "$CONF_PATH" 2>/dev/null || echo 0)
    local w_mtime=$(stat -c %Y "$LOCAL_WHITE" 2>/dev/null || echo 0)

    if [ "$c_mtime" != "$LAST_CONF_TIME" ] || [ "$w_mtime" != "$LAST_WHITE_TIME" ]; then
        CACHED_LIST=$(cat "$CONF_PATH" | tr -d '\n\r ' | grep -o '{"isWhitelist":false[^}]*}' | grep -o '"appList":\[[^]]*\]' | sed 's/"appList":\[//;s/\]//' | tr ',' '\n' | sed 's/[^a-zA-Z0-9._-]//g' | grep '\.')

        if [ -n "$CACHED_LIST" ]; then
            BLACKLIST_COUNT=$(echo "$CACHED_LIST" | wc -l | tr -d ' ')
        else
            BLACKLIST_COUNT=0
        fi

        local bl_json="["
        local bl_first=1
        for pkg in $CACHED_LIST; do
            local clean_pkg=$(echo "$pkg" | tr -cd 'a-zA-Z0-9._-')
            [ -z "$clean_pkg" ] && continue
            if [ $bl_first -eq 1 ]; then bl_first=0; else bl_json="$bl_json,"; fi
            bl_json="$bl_json\"$clean_pkg\""
        done
        bl_json="$bl_json]"
        echo "$bl_json" > "$BLACKLIST_FILE"
        chmod 666 "$BLACKLIST_FILE"

        local raw_json=$(cat "$LOCAL_WHITE" | tr -d '\n\r ')
        if echo "$raw_json" | grep -q "^\[.*\]$"; then
            WHITE_LIST=$(echo "$raw_json" | tr -d '[]"' | tr ',' '\n' | sed 's/[^a-zA-Z0-9._-]//g' | grep '\.')
            if [ -n "$WHITE_LIST" ]; then
                WHITELIST_COUNT=$(echo "$WHITE_LIST" | wc -l | tr -d ' ')
            else
                WHITELIST_COUNT=0
            fi
        else
            WHITE_LIST=""
            WHITELIST_COUNT=0
        fi

        LAST_CONF_TIME=$c_mtime
        LAST_WHITE_TIME=$w_mtime
    fi
    return 0
}

# --- 2.5 读取已清理计数 ---
load_cleaned_count() {
    if [ -f "$CLEANED_FILE" ]; then
        CLEANED_COUNT=$(cat "$CLEANED_FILE" | tr -d '[:space:]')
        [ -z "$CLEANED_COUNT" ] && CLEANED_COUNT=0
    else
        CLEANED_COUNT=0
    fi
}

# --- 2.6 写入统计数据 ---
write_stats() {
    load_cleaned_count
    cat > "$STATS_FILE" << EOF
{"pid":$$,"blacklist":$BLACKLIST_COUNT,"whitelist":$WHITELIST_COUNT,"cleaned":$CLEANED_COUNT}
EOF
    chmod 666 "$STATS_FILE"
}

# --- 3. 清理任务 ---
clean_task() {
    refresh_lists || return
    # 快速路径：黑名单为空则直接返回，避免不必要的循环
    [ -z "$CACHED_LIST" ] && return
    [ "$BLACKLIST_COUNT" -eq 0 ] && return

    local cleaned_this_round=0
    for pkg in $CACHED_LIST; do
        local current_pkg=$(echo "$pkg" | tr -cd 'a-zA-Z0-9._-')
        [ -z "$current_pkg" ] && continue
        # 白名单快速匹配
        case " $WHITE_LIST " in
            *" $current_pkg "*) continue ;;
        esac
        for sub in data obb media; do
            if [ -d "$M_BASE/$sub/$current_pkg" ]; then
                rm -rf "$M_BASE/$sub/$current_pkg"
                log -t HMAPLUS "已清理 $current_pkg" 2>/dev/null
                cleaned_this_round=$((cleaned_this_round + 1))
            fi
        done
    done

    if [ $cleaned_this_round -gt 0 ]; then
        load_cleaned_count
        CLEANED_COUNT=$((CLEANED_COUNT + cleaned_this_round))
        echo "$CLEANED_COUNT" > "$CLEANED_FILE"
        chmod 666 "$CLEANED_FILE"
    fi
    write_stats
}

# --- 4. 分发 ---
if [ "$1" = "trigger" ]; then
    write_pid
    export_module_info
    refresh_lists
    clean_task
    write_stats
    exit 0
fi

# --- 单实例保护：杀掉旧的 HMAPLUS 守护进程（仅守护模式生效，不影响 trigger 一次性调用）---
kill_old_instances

until [ -d "/sdcard/Android" ]; do sleep 5; done

write_pid
init_web_data
export_module_info
refresh_lists
write_stats
clean_task

# --- 5. 事件监听 ---
(
    busybox inotifyd - "$M_BASE/data":c "$M_BASE/obb":c "$M_BASE/media":c 2>/dev/null | while read -r ev dir file; do
        touch "$FLAG_FILE" 2>/dev/null
    done
) 2>/dev/null &

# --- 6. 主循环 ---
# 功耗优化：inotifyd 已监听目录变化并即时触发清理
# 因此定时检查间隔可以大幅延长，减少CPU唤醒
TICK=0
CHECK_INTERVAL=30       # 主循环检查间隔（秒）
FORCE_CLEAN_EVERY=600   # 强制全量清理间隔（秒），默认10分钟
while :; do
    if [ -f "$FLAG_FILE" ]; then
        rm -f "$FLAG_FILE" 2>/dev/null
        clean_task
        TICK=0
    fi
    TICK=$((TICK + CHECK_INTERVAL))
    if [ $TICK -ge $FORCE_CLEAN_EVERY ]; then
        # 仅刷新统计，不做全量清理（inotify已覆盖实时变化）
        refresh_lists
        write_stats
        TICK=0
    fi
    sleep $CHECK_INTERVAL
done
