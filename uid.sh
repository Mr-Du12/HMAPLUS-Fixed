#!/system/bin/sh
# UID 内核隐藏（合并自 fgetpriority v0.0.4）
# 通过加载内核模块隐藏 getpriority 查询结果，配置仅一个开关
set -eu
MODDIR=${0%/*}
ID=HMAPLUS
STORE=/data/adb/HMAPLUS
CONF="$STORE/uid.conf"
KO="$MODDIR/ko/fgetpriority.ko"
LOG_FILE="$MODDIR/webroot/hmaplusa_log.txt"
LOG_MAX_LINES=200

export PATH=/system/bin:/system/xbin:/data/adb/magisk:/data/adb/ksu/bin:$PATH

log_write() {
    log_level=$1
    shift
    [ -d "$MODDIR/webroot" ] || { mkdir -p "$MODDIR/webroot"; chmod 755 "$MODDIR/webroot"; }
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$log_level" "$*" >> "$LOG_FILE" 2>/dev/null || return 0
    chmod 666 "$LOG_FILE" 2>/dev/null || true
    log_lines=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ')
    if [ -n "$log_lines" ] && [ "$log_lines" -gt "$LOG_MAX_LINES" ]; then
        tail -n "$LOG_MAX_LINES" "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null \
            && mv -f "$LOG_FILE.tmp" "$LOG_FILE"
        chmod 666 "$LOG_FILE" 2>/dev/null || true
    fi
}

ensure_conf() {
    [ "$(id -u)" = 0 ] || { echo '需要模块管理器的 Root 接口' >&2; exit 1; }
    mkdir -p "$STORE"
    chmod 700 "$STORE" 2>/dev/null || true
    if [ ! -f "$CONF" ]; then
        printf 'enabled=0\n' > "$CONF"
        chmod 600 "$CONF"
    fi
    case "$(head -n 1 "$CONF")" in
        enabled=0|enabled=1) ;;
        *)
            printf 'enabled=0\n' > "$CONF"
            chmod 600 "$CONF"
            log_write ERROR 'UID内核隐藏配置无效，已重置为关闭'
            ;;
    esac
}

is_loaded() {
    lsmod 2>/dev/null | grep -q '^fgetpriority'
}

is_supported() {
    [ -f "$KO" ]
}

load_module() {
    is_supported || return 2
    if is_loaded; then
        return 0
    fi
    kptr_set=$(cat /proc/sys/kernel/kptr_restrict 2>/dev/null || echo 0)
    echo 1 > /proc/sys/kernel/kptr_restrict 2>/dev/null || true
    addr=$(grep ' kallsyms_lookup_name$' /proc/kallsyms 2>/dev/null | awk '{print "0x"$1}' | head -n 1)
    echo "$kptr_set" > /proc/sys/kernel/kptr_restrict 2>/dev/null || true
    [ -n "$addr" ] || return 3
    if insmod "$KO" kallsyms_lookup_name_fn="$addr" 2>/dev/null; then
        :
    elif command -v ksud >/dev/null 2>&1 && ksud insmod "$KO" kallsyms_lookup_name_fn="$addr" 2>/dev/null; then
        :
    else
        return 1
    fi
    is_loaded
}

unload_module() {
    is_loaded || return 0
    rmmod fgetpriority 2>/dev/null || return 1
    ! is_loaded
}

module_version() {
    sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null | head -n 1
}

kmi_name() {
    cat "$MODDIR/ko/kmi" 2>/dev/null | head -n 1
}

status() {
    enabled=false; [ "$(head -n 1 "$CONF")" = enabled=1 ] && enabled=true
    loaded=false; is_loaded && loaded=true
    supported=false; is_supported && supported=true
    version=$(module_version)
    kernel=$(uname -r 2>/dev/null || echo unknown)
    kmi=$(kmi_name)
    printf '{"enabled":%s,"loaded":%s,"supported":%s,"kernel":"%s","module":"%s","version":"%s"}\n' \
        "$enabled" "$loaded" "$supported" "$kernel" "${kmi:-unknown}" "${version:-unknown}"
}

case "${1:-status}" in
    ensure) ensure_conf ;;
    status) ensure_conf; status ;;
    init)
        ensure_conf
        if [ "$(head -n 1 "$CONF")" = enabled=1 ]; then
            rc=0
            load_module || rc=$?
            if [ "$rc" -eq 0 ]; then
                log_write UID '开机已加载 UID 内核隐藏'
            elif [ "$rc" -eq 2 ]; then
                log_write ERROR '当前内核没有匹配的 UID 内核模块，未加载'
            else
                log_write ERROR 'UID 内核模块加载失败，请检查内核兼容性'
            fi
        fi
        ;;
    save)
        ensure_conf
        enable=${2:-}
        case "$enable" in
            0|1) ;;
            *) echo '参数无效' >&2; exit 1 ;;
        esac
        if [ "$enable" = 1 ]; then
            if ! is_supported; then
                log_write ERROR '当前内核没有匹配的 UID 内核模块，开启已取消'
                echo '当前内核没有匹配的 UID 内核模块' >&2
                exit 1
            fi
            printf 'enabled=1\n' > "$CONF"
            if load_module; then
                log_write UID '已开启 UID 内核隐藏'
            else
                log_write ERROR 'UID 内核模块加载失败，请检查内核兼容性'
                echo '内核模块加载失败' >&2
                exit 1
            fi
        else
            printf 'enabled=0\n' > "$CONF"
            if unload_module; then
                log_write UID '已关闭 UID 内核隐藏'
            else
                log_write ERROR 'UID 内核模块卸载失败，重启后不再加载'
                echo '内核模块卸载失败，已关闭开机加载' >&2
                exit 1
            fi
        fi
        status ;;
    *) echo '未知操作' >&2; exit 1 ;;
esac
