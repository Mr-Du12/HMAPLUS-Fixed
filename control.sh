#!/system/bin/sh
# UID 过滤（合并自 UID Filter 0.2.8）
# 配置持久化在 /data/adb/HMAPLUS，并同步到模块目录 config 供 Zygisk 原生库读取
set -eu
MODDIR=${0%/*}
ID=HMAPLUS
STORE=/data/adb/HMAPLUS
CURRENT=/data/adb/modules/$ID
PENDING=/data/adb/modules_update/$ID

[ "$(id -u)" = 0 ] || { echo '需要模块管理器的 Root 接口' >&2; exit 1; }
mkdir -p "$STORE"
chmod 700 "$STORE"

LOG_FILE="$MODDIR/webroot/hmaplusa_log.txt"
LOG_MAX_LINES=200

# 日志仅在事件发生时写入，无定时轮询，不增加耗电
log_write() {
    log_level=$1
    shift
    [ -d "$MODDIR/webroot" ] || { mkdir -p "$MODDIR/webroot"; chmod 755 "$MODDIR/webroot"; }
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$log_level" "$*" >> "$LOG_FILE" 2>/dev/null || return 0
    chmod 666 "$LOG_FILE" 2>/dev/null || true
    log_lines=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ')
    if [ -n "$log_lines" ] && [ "$log_lines" -gt "$LOG_MAX_LINES" ]; then
        tail -n "$LOG_MAX_LINES" "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv -f "$LOG_FILE.tmp" "$LOG_FILE"
        chmod 666 "$LOG_FILE" 2>/dev/null || true
    fi
}

validate() {
    [ "$(wc -c < "$1")" -le 32768 ] || return 1
    awk 'NR==1 {if ($0!="enabled=0" && $0!="enabled=1") exit 1; next}
        {if (length($0)>255 || $0 !~ /^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+$/ || ++n>128) exit 1}
        END {if (NR<1) exit 1}' "$1"
}

copy_config() {
    target=$1
    [ -d "$target" ] || return 0
    cp "$STORE/config" "$target/config.new"
    chmod 644 "$target/config.new"
    chcon u:object_r:system_file:s0 "$target/config.new" 2>/dev/null || true
    mv -f "$target/config.new" "$target/config"
}

sync_config() {
    copy_config "$MODDIR"
    [ "$CURRENT" = "$MODDIR" ] || copy_config "$CURRENT"
    [ "$PENDING" = "$MODDIR" ] || copy_config "$PENDING"
}

init_config() {
    if [ ! -f "$STORE/config" ]; then
        cp "$MODDIR/uid_defaults" "$STORE/config"
        chmod 600 "$STORE/config"
    fi
    validate "$STORE/config" || { log_write ERROR 'UID过滤配置无效，已保留原文件'; echo '已保存的 UID 过滤配置无效；未覆盖原文件' >&2; exit 1; }
    sync_config
}

module_version() {
    sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null | head -n1
}

status() {
    enabled=false; [ "$(head -n 1 "$STORE/config")" = enabled=1 ] && enabled=true
    disabled=false; [ ! -f "$CURRENT/disable" ] || disabled=true
    pending=false; [ ! -f "$CURRENT/update" ] || pending=true
    version=$(module_version)
    printf '{"enabled":%s,"moduleDisabled":%s,"pendingUpdate":%s,"version":"%s","packages":[' "$enabled" "$disabled" "$pending" "${version:-unknown}"
    comma=''
    tail -n +2 "$STORE/config" | while IFS= read -r package; do
        printf '%s"%s"' "$comma" "$package"; comma=,
    done
    printf ']}\n'
}

case "${1:-status}" in
    init) init_config ;;
    status) init_config; status ;;
    save)
        init_config
        encoded=${2:-}
        [ "${#encoded}" -le 44000 ] || { log_write ERROR 'UID过滤配置过长，保存已中止'; echo '配置过长' >&2; exit 1; }
        case "$encoded" in ''|*[!A-Za-z0-9+/=]*) log_write ERROR 'UID过滤配置编码无效，保存已中止'; echo '配置编码无效' >&2; exit 1;; esac
        temp="$STORE/incoming.$$"
        trap 'rm -f "$temp" "$temp.sorted" "$temp.previous" "$temp.affected" "$temp.added" "$temp.removed"' EXIT
        printf '%s' "$encoded" | base64 -d > "$temp"
        validate "$temp" || { log_write ERROR 'UID过滤包名格式无效或超过 128 项，保存已中止'; echo '包名格式无效或超过 128 项' >&2; exit 1; }
        { head -n 1 "$temp"; tail -n +2 "$temp" | sort -u; } > "$temp.sorted"
        cp "$STORE/config" "$temp.previous"
        previous_enabled=$(head -n 1 "$temp.previous")
        [ ! -f "$CURRENT/disable" ] || previous_enabled=enabled=0
        chmod 600 "$temp.sorted"
        mv -f "$temp.sorted" "$STORE/config"
        sync_config
        if [ "$(head -n 1 "$STORE/config")" = enabled=1 ]; then
            rm -f "$CURRENT/disable" "$PENDING/disable"
        fi

        # 计算新增/移除的包名，用于日志
        awk 'FNR==1 {next} NR==FNR {old[$0]=1;next} !($0 in old)' "$temp.previous" "$STORE/config" > "$temp.added" || true
        awk 'FNR==1 {next} NR==FNR {cur[$0]=1;next} !($0 in cur)' "$STORE/config" "$temp.previous" > "$temp.removed" || true
        added_list=$(tr '\n' ' ' < "$temp.added" 2>/dev/null | sed 's/ *$//')
        removed_list=$(tr '\n' ' ' < "$temp.removed" 2>/dev/null | sed 's/ *$//')

        current_enabled=$(head -n 1 "$STORE/config")
        pkg_count=$(awk 'NR>1 && NF' "$STORE/config" | wc -l | tr -d ' ')
        if [ "$current_enabled" = enabled=1 ]; then
            log_write UID "已启用 UID 过滤，生效 ${pkg_count} 个应用"
        else
            log_write UID "已关闭 UID 过滤"
        fi
        [ -z "$added_list" ] || log_write UID "新增生效应用: $added_list"
        [ -z "$removed_list" ] || log_write UID "移除生效应用: $removed_list"

        # 过滤只在进程启动时生效：仅重启配置有变化的目标应用，不清除应用数据
        if [ "${3:-}" = apply ]; then
            if [ "$previous_enabled" != "$current_enabled" ]; then
                { tail -n +2 "$temp.previous"; tail -n +2 "$STORE/config"; } | sort -u > "$temp.affected"
            elif [ "$current_enabled" = enabled=1 ]; then
                awk 'FNR==1 {next} NR==FNR {old[$0]=1;next}
                    {if ($0 in old) delete old[$0]; else added[$0]=1}
                    END {for (p in old) print p; for (p in added) print p}' "$temp.previous" "$STORE/config" > "$temp.affected"
            else
                : > "$temp.affected"
            fi
            restarted=0
            while IFS= read -r package; do
                [ -n "$package" ] || continue
                case "$package" in android|com.android.systemui|me.weishu.kernelsu|me.bmax.apatch|com.topjohnwu.magisk|icu.icu4x.solar) continue;; esac
                am force-stop --user current "$package" >/dev/null 2>&1 || true
                restarted=$((restarted + 1))
            done < "$temp.affected"
            [ "$restarted" -eq 0 ] || log_write UID "已重启 ${restarted} 个应用使配置生效"
        fi
        status ;;
    *) echo '未知操作' >&2; exit 1 ;;
esac
