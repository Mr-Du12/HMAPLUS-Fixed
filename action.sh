#!/system/bin/sh

export PATH=/system/bin:/system/xbin:/data/adb/magisk:/data/adb/ksu/bin:$PATH

REAL_DATA="/data/media/0/Android/data"
REAL_OBB="/data/media/0/Android/obb"
REAL_MEDIA="/data/media/0/Android/media"
WHITE_LIST_FILE="/data/adb/modules/HMAPLUS/webroot/WhiteList_web.json"
CLEANED_FILE="/data/adb/modules/HMAPLUS/.cleaned_count"
STATS_FILE="/data/adb/modules/HMAPLUS/webroot/stats.json"

CONF=$(ls /data/misc/*hide_my_applist*/config.json 2>/dev/null | head -n1)

echo "配置文件: $CONF"
[ ! -f "$CONF" ] && echo "错误: 找不到配置文件" && exit 1

if [ -f "$WHITE_LIST_FILE" ]; then
    WHITELIST_DATA=$(cat "$WHITE_LIST_FILE")
else
    WHITELIST_DATA="[]"
fi

LIST=$(cat "$CONF" | tr -d '\n\r ' | grep -o '{"isWhitelist":false[^}]*}' | grep -o '"appList":\[[^]]*\]' | sed 's/"appList":\[//;s/\]//' | tr ',' '\n' | sed 's/[^a-zA-Z0-9._-]//g' | grep '\.')

echo "当前识别到的黑名单:"
echo "$LIST"
echo "--------清理文件--------"

CLEANED_COUNT=0
[ -f "$CLEANED_FILE" ] && CLEANED_COUNT=$(cat "$CLEANED_FILE" | tr -d '[:space:]')
[ -z "$CLEANED_COUNT" ] && CLEANED_COUNT=0

do_clean() {
    local cleaned_this_round=0
    for pkg in $LIST; do
        [ -z "$pkg" ] && continue
        if echo "$WHITELIST_DATA" | grep -q "\"$pkg\""; then
            echo "白名单保护: $pkg"
            continue
        fi
        for sub_dir in "$REAL_DATA" "$REAL_OBB" "$REAL_MEDIA"; do
            if [ -d "$sub_dir/$pkg" ]; then
                rm -rf "$sub_dir/$pkg"
                echo "已清理: $pkg"
                log -t HMAPLUS "清理: $pkg" 2>/dev/null
                cleaned_this_round=$((cleaned_this_round + 1))
            fi
        done
    done

    if [ $cleaned_this_round -gt 0 ]; then
        CLEANED_COUNT=$((CLEANED_COUNT + cleaned_this_round))
        echo "$CLEANED_COUNT" > "$CLEANED_FILE"
        chmod 666 "$CLEANED_FILE"
    fi

    local pid=$$
    local bl_count=$(echo "$LIST" | wc -l | tr -d ' ')
    local wl_count=$(echo "$WHITELIST_DATA" | tr -d '[]"' | tr ',' '\n' | sed 's/[^a-zA-Z0-9._-]//g' | grep '\.' | wc -l | tr -d ' ')
    cat > "$STATS_FILE" << EOF
{"pid":$pid,"blacklist":$bl_count,"whitelist":$wl_count,"cleaned":$CLEANED_COUNT}
EOF
    chmod 666 "$STATS_FILE"

    echo "--------清理完成--------"
    echo "本轮清理: $cleaned_this_round 项"
    echo "累计清理: $CLEANED_COUNT 项"
}

do_clean
