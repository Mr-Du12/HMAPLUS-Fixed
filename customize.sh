#!/sbin/sh

# 1. 定义 HMA 配置路径
CONF_PATH=$(ls -d /data/misc/*hide_my_applist*/config.json 2>/dev/null | head -n1)

ui_print "-----------------------------"
ui_print "      HMAPLUS 环境检测       "
ui_print "-----------------------------"

if [ -f "$CONF_PATH" ]; then
    # 提取黑名单（仅 isWhitelist:false）
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

# 2. 白名单文件初始化（路径与 service.sh 保持一致）
mkdir -p "$MODPATH/webroot"
if [ ! -f "$MODPATH/webroot/WhiteList_web.json" ]; then
    ui_print "初始化本地白名单..."
    echo "[]" > "$MODPATH/webroot/WhiteList_web.json"
fi

# 3. 设置权限
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755

ui_print "-----------------------------"
ui_print "    安装完成 重启后生效      "
ui_print "-----------------------------"
