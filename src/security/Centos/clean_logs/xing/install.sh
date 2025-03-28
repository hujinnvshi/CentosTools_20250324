#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 设置脚本路径
SCRIPT_DIR="/data/scripts/clean_logs"
SCRIPT_PATH="${SCRIPT_DIR}/clean_logs.sh"

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用root用户执行此脚本${NC}"
    exit 1
fi

# 创建目录并复制脚本
mkdir -p "${SCRIPT_DIR}"
cp clean_logs.sh "${SCRIPT_PATH}"
chmod +x "${SCRIPT_PATH}"

# 创建crontab任务
(crontab -l 2>/dev/null; echo "*/30 * * * * ${SCRIPT_PATH}") | crontab -

echo -e "${GREEN}安装完成：${NC}"
echo "1. 脚本已安装到: ${SCRIPT_PATH}"
echo "2. 已添加定时任务，每30分钟执行一次"
echo "3. 日志文件位置: ${SCRIPT_DIR}/clean_logs.log"
echo -e "${GREEN}可以通过以下命令手动执行：${NC}"
echo "${SCRIPT_PATH}"