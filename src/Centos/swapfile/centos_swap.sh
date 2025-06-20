#!/bin/bash

# CentOS添加swap分区的完整操作步骤
# 此脚本用于在CentOS系统上创建和配置swap分区
# 作者：AI助手
# 日期：2024年3月24日

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 检查是否以root用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误: 此脚本必须以root用户运行${NC}"
    exit 1
 fi

# 显示当前swap状态
echo -e "${BLUE}当前swap状态:${NC}"
free -h
swapon --show

# 询问用户swap大小
read -p "请输入要创建的swap大小(GB，推荐为物理内存的1-2倍): " SWAP_SIZE

# 验证输入是否为数字
if ! [[ "$SWAP_SIZE" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}错误: 请输入有效的数字${NC}"
    exit 1
fi

# 设置swap文件路径
SWAP_FILE="/old-data/centos_swap/swapfile"

# 检查是否已存在swap文件
if [ -f "$SWAP_FILE" ]; then
    echo -e "${YELLOW}警告: swap文件已存在${NC}"
    read -p "是否删除现有swap文件并创建新的? (y/n): " CONFIRM
    if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
        echo -e "${YELLOW}正在关闭现有swap...${NC}"
        swapoff -v "$SWAP_FILE"
        rm -f "$SWAP_FILE"
    else
        echo -e "${GREEN}操作已取消${NC}"
        exit 0
    fi
fi

# 检查磁盘空间是否足够
FREE_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$FREE_SPACE" -lt "$SWAP_SIZE" ]; then
    echo -e "${RED}错误: 磁盘空间不足。可用: ${FREE_SPACE}GB, 需要: ${SWAP_SIZE}GB${NC}"
    exit 1
fi

echo -e "${GREEN}开始创建${SWAP_SIZE}GB的swap文件...${NC}"

# 创建swap文件
echo -e "${BLUE}步骤1: 创建swap文件${NC}"
dd if=/dev/zero of="$SWAP_FILE" bs=1G count="$SWAP_SIZE" status=progress
if [ $? -ne 0 ]; then
    echo -e "${RED}创建swap文件失败${NC}"
    exit 1
fi

# 设置swap文件权限
echo -e "${BLUE}步骤2: 设置swap文件权限${NC}"
chmod 600 "$SWAP_FILE"

# 设置swap文件格式
echo -e "${BLUE}步骤3: 格式化swap文件${NC}"
mkswap "$SWAP_FILE"
if [ $? -ne 0 ]; then
    echo -e "${RED}格式化swap文件失败${NC}"
    exit 1
fi

# 激活swap
echo -e "${BLUE}步骤4: 激活swap${NC}"
swapon "$SWAP_FILE"
if [ $? -ne 0 ]; then
    echo -e "${RED}激活swap失败${NC}"
    exit 1
fi

# 设置开机自动挂载swap
echo -e "${BLUE}步骤5: 设置开机自动挂载swap${NC}"
if grep -q "$SWAP_FILE" /etc/fstab; then
    echo -e "${YELLOW}swap文件已在/etc/fstab中配置${NC}"
else
    echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
    if [ $? -ne 0 ]; then
        echo -e "${RED}更新/etc/fstab失败${NC}"
        echo -e "${YELLOW}警告: swap已激活但未配置为开机自动挂载${NC}"
    else
        echo -e "${GREEN}已将swap添加到/etc/fstab，将在系统重启后自动挂载${NC}"
    fi
fi

# 配置swappiness参数
echo -e "${BLUE}步骤6: 配置swappiness参数${NC}"
CURRENT_SWAPPINESS=$(cat /proc/sys/vm/swappiness)
echo -e "${YELLOW}当前swappiness值: $CURRENT_SWAPPINESS${NC}"
echo -e "${YELLOW}swappiness参数控制系统使用swap的倾向性:${NC}"
echo -e "${YELLOW}- 值越低，系统越倾向于使用物理内存${NC}"
echo -e "${YELLOW}- 值越高，系统越倾向于使用swap${NC}"
echo -e "${YELLOW}- 推荐值: 服务器10-30，桌面系统60${NC}"

read -p "是否修改swappiness值? (y/n): " MODIFY_SWAPPINESS
if [ "$MODIFY_SWAPPINESS" = "y" ] || [ "$MODIFY_SWAPPINESS" = "Y" ]; then
    read -p "请输入新的swappiness值(0-100): " NEW_SWAPPINESS
    if [[ "$NEW_SWAPPINESS" =~ ^[0-9]+$ ]] && [ "$NEW_SWAPPINESS" -ge 0 ] && [ "$NEW_SWAPPINESS" -le 100 ]; then
        sysctl vm.swappiness="$NEW_SWAPPINESS"
        echo "vm.swappiness=$NEW_SWAPPINESS" > /etc/sysctl.d/99-swappiness.conf
        echo -e "${GREEN}swappiness已设置为$NEW_SWAPPINESS并将在重启后生效${NC}"
    else
        echo -e "${RED}无效的swappiness值，保持当前设置${NC}"
    fi
fi

# 显示结果
echo -e "\n${GREEN}Swap创建完成!${NC}"
echo -e "${BLUE}当前swap状态:${NC}"
free -h
swapon --show

echo -e "\n${GREEN}Swap配置总结:${NC}"
echo -e "${BLUE}- Swap文件: ${NC}$SWAP_FILE"
echo -e "${BLUE}- Swap大小: ${NC}${SWAP_SIZE}GB"
echo -e "${BLUE}- 权限设置: ${NC}$(ls -lh $SWAP_FILE | awk '{print $1}')"
echo -e "${BLUE}- Swappiness: ${NC}$(cat /proc/sys/vm/swappiness)"
echo -e "${BLUE}- 开机自动挂载: ${NC}已配置"

echo -e "\n${YELLOW}注意事项:${NC}"
echo -e "1. 如需关闭swap: ${GREEN}swapoff -v $SWAP_FILE${NC}"
echo -e "2. 如需完全移除swap:${NC}"
echo -e "   ${GREEN}swapoff -v $SWAP_FILE${NC}"
echo -e "   ${GREEN}sed -i '\\|^$SWAP_FILE|d' /etc/fstab${NC}"
echo -e "   ${GREEN}rm -f $SWAP_FILE${NC}"
echo -e "3. 如需查看swap使用情况: ${GREEN}free -h${NC} 或 ${GREEN}swapon --show${NC}"