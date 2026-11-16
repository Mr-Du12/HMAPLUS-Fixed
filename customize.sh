#!/system/bin/sh

CONF_PATH=$(ls -d /data/misc/*hide_my_applist*/config.json 2>/dev/null | head -n1)

ui_print "-----------------------------"
ui_print "      HMAPLUS 环境检测       "
ui_print "-----------------------------"

if [ -f "$CONF_PATH" ]; then
    BLACKLIST=$(cat "$CONF_PATH" | tr -d '\n\r ' | grep -o '{"isWhitelist":false[^}]*}' | grep -o '"appList":\[[^]]*\]' | sed 's/"appList":\[//;s/\]//' | tr ',' '\n' | sed 's/[^a-zA-Z0-9._-]//g' | grep '\.')
    B_COUNT=$(echo "$BLACKLIST" | grep -c '\.' 2>/dev/null || echo 0)

    ui_print "检测到 HMA 配置"
    ui_print "黑名单应用：$B_COUNT 个"

    if [ "$B_COUNT" -gt 0 ]; then
        EXAMPLE=$(echo "$BLACKLIST" | head -n 3)
        ui_print "待清理示例："
        for ex in $EXAMPLE; do
            ui_print " - $ex"
        done
    fi
else
    ui_print "未发现 HMA 配置文件"
    ui_print "请在安装后打开 HMA 保存一次配置"
fi

# 白名单文件初始化（路径与 service.sh 保持一致）
mkdir -p "$MODPATH/webroot"
if [ ! -f "$MODPATH/webroot/WhiteList_web.json" ]; then
    ui_print "初始化本地白名单..."
    echo "[]" > "$MODPATH/webroot/WhiteList_web.json"
fi

# UID 内核隐藏：按内核版本挑选匹配的 ko（取自 fgetpriority v0.0.4）
kmi_from_uname() {
    _r="$(uname -r)"
    _branch="$(echo "$_r" | grep -oE 'android[0-9]+' | head -n1)"
    _ver="$(echo "$_r" | grep -oE '^[0-9]+\.[0-9]+' | head -n1)"

    if [ -n "$_branch" ]; then
        echo "${_branch}-${_ver}"
        return
    fi

    _cands=""
    for _c in $(ls "$MODPATH/ko" 2>/dev/null | sed 's/_arm64_fgetpriority\.ko$//' | sort -u); do
        [ "${_c#*-}" = "$_ver" ] && _cands="$_cands $_c"
    done
    _cands="${_cands# }"
    [ "$(echo "$_cands" | wc -w)" -gt 1 ] && ui_print "! $(uname -r) fits $_cands; taking the first"
    echo "${_cands%% *}"
}

if [ "$ARCH" != "arm64" ]; then
    ui_print "! 当前架构非 arm64，UID 内核隐藏不可用"
else
    KMI="$(kmi_from_uname)"
    if [ -z "$KMI" ] && command -v ksud >/dev/null 2>&1; then
        KMI=$(ksud boot-info current-kmi 2>/dev/null)
    fi

    SRC=""
    [ -n "$KMI" ] && [ -f "$MODPATH/ko/${KMI}_arm64_fgetpriority.ko" ] && SRC="$MODPATH/ko/${KMI}_arm64_fgetpriority.ko"

    if [ -n "$SRC" ]; then
        cp -f "$SRC" "$MODPATH/ko/fgetpriority.ko"
        for f in "$MODPATH"/ko/*_arm64_fgetpriority.ko; do
            [ -e "$f" ] && rm -f "$f"
        done
        echo "$KMI" > "$MODPATH/ko/kmi"
        ui_print "- UID 内核模块：$(uname -r) -> $(basename "$SRC")"
    else
        ui_print "! 未找到匹配 $(uname -r) 的内核模块（KMI ${KMI:-unknown}）"
        ui_print "! UID 内核隐藏不可用，目录清理不受影响"
        ui_print "! ko/ 目录保留全部预编译版本，可等待后续适配"
    fi
    ui_print "- UID 内核隐藏默认关闭，可在 WebUI 中开启"
fi

# 权限
set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in "$MODPATH"/*.sh; do
    [ -e "$f" ] && set_perm "$f" 0 0 0755
done
[ -f "$MODPATH/ko/fgetpriority.ko" ] && set_perm "$MODPATH/ko/fgetpriority.ko" 0 0 0644

ui_print "-----------------------------"
ui_print "    安装完成 重启后生效      "
ui_print "-----------------------------"
