#!/bin/bash
# Hive 实例批量卸载脚本生成器
# 作者：系统开发工程师
# 功能：自动检测/data下所有Hive实例并生成卸载命令
# 版本：1.0

TARGET_DIR="/data"  # 扫描目标路径
OUTPUT_SCRIPT="hive_uninstall_all.sh"  # 生成的卸载脚本文件名

# 检查目录是否存在
if [ ! -d "$TARGET_DIR" ]; then
    echo "错误：目标目录 $TARGET_DIR 不存在!"
    exit 1
fi

# 创建卸载脚本头部
cat > "$OUTPUT_SCRIPT" << 'HEADER'
#!/bin/bash
# 自动生成的Hive卸载脚本
# 执行此脚本将卸载所有检测到的Hive实例
# 警告：此操作不可逆！请确认已备份重要数据

echo "=== 开始卸载所有Hive实例 ==="
echo "当前时间: $(date)"
echo "检测到以下实例:"
HEADER

# 查找所有Hive实例并生成卸载命令
find "$TARGET_DIR" -maxdepth 1 -type d -name "hive_*" | while read -r dir; do
    dir_name=$(basename "$dir")
    
    # 使用正则表达式解析版本和实例ID
    if [[ $dir_name =~ ^hive_([0-9]+\.[0-9]+\.[0-9]+)_(v[0-9]+)$ ]]; then
        version="${BASH_REMATCH[1]}"
        instance_id="${BASH_REMATCH[2]}"
        
        # 在卸载脚本中追加命令和检测信息
        cat >> "$OUTPUT_SCRIPT" << LINE
echo " - HIVE $version 实例: $instance_id"
HIVE_VERSION=$version INSTANCE_ID=$instance_id ./centos_hive_uninstall_vx.sh clean
LINE
    fi
done

# 添加脚本尾部
cat >> "$OUTPUT_SCRIPT" << 'FOOTER'

echo "=== 卸载操作已完成 ==="
echo "提示：建议手动验证以下内容:"
echo "1. /etc/hive 配置目录是否清除"
echo "2. /var/hive 数据目录是否清除"
echo "3. 系统服务是否停止 (systemctl list-units | grep hive)"
echo "4. 用户账号是否删除 (grep 'hive_' /etc/passwd)"
FOOTER

# 设置执行权限
chmod +x "$OUTPUT_SCRIPT"

echo "成功生成卸载脚本: $OUTPUT_SCRIPT"
echo "请执行以下步骤:"
echo "1. 检查脚本内容: less $OUTPUT_SCRIPT"
echo "2. 执行脚本: ./$OUTPUT_SCRIPT"
echo "3. 检查卸载日志"