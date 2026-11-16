#!/system/bin/sh
PATH=/data/adb/ksu/bin:$PATH

# 卸载模块时尝试卸载 UID 内核模块
if lsmod 2>/dev/null | grep -q '^fgetpriority'; then
    rmmod fgetpriority 2>/dev/null
fi
