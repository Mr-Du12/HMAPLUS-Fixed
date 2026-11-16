#!/system/bin/sh
MODDIR=${0%/*}
# 仅初始化 UID 开关配置，内核模块由 service.sh 启动时按需加载
sh "$MODDIR/uid.sh" ensure >/dev/null 2>&1
