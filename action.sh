#!/system/bin/sh
# 管理器“执行”按钮：手动全量清理，输出可见的执行结果
export PATH=/system/bin:/system/xbin:/data/adb/magisk:/data/adb/ksu/bin:$PATH
MOD_DIR=${0%/*}
[ -d "$MOD_DIR" ] || MOD_DIR="/data/adb/modules/HMAPLUS"

echo "=============================="
echo "  HMAPLUS 手动清理"
echo "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================="

if [ ! -f "$MOD_DIR/clean.sh" ]; then
    echo "[失败] 找不到清理脚本 clean.sh，请重新安装模块"
    exit 1
fi

if sh "$MOD_DIR/clean.sh" full; then
    echo "[完成] 清理执行结束，详细记录请打开 WebUI 运行日志查看"
else
    echo "[失败] 清理过程出错，请打开 WebUI 运行日志查看红色错误记录"
    exit 1
fi
