#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 输出函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    print_error "请使用 root 用户执行此脚本"
    exit 1
fi

# 设置变量
DB2_HOME="/data/db2"
DB2_INSTANCE="db2inst1"
DB2_FENCED="db2fenc1"

# 停止数据库实例
print_message "停止数据库实例..."
su - ${DB2_INSTANCE} -c "db2stop force" 2>/dev/null || print_warning "数据库实例已停止"

# 删除实例
print_message "删除数据库实例..."
${DB2_HOME}/instance/db2idrop ${DB2_INSTANCE} 2>/dev/null || print_warning "实例可能已删除"

# 卸载 DB2
print_message "卸载 DB2..."
if [ -f "${DB2_HOME}/install/db2_deinstall" ]; then
    ${DB2_HOME}/install/db2_deinstall -a
else
    print_warning "卸载程序不存在，尝试直接删除文件"
fi

# 删除用户和组
print_message "删除用户和组..."
userdel -r ${DB2_INSTANCE} 2>/dev/null || print_warning "用户 ${DB2_INSTANCE} 已删除"
userdel -r ${DB2_FENCED} 2>/dev/null || print_warning "用户 ${DB2_FENCED} 已删除"
groupdel db2iadm1 2>/dev/null || print_warning "组 db2iadm1 已删除"
groupdel db2fadm1 2>/dev/null || print_warning "组 db2fadm1 已删除"

# 删除环境变量配置
print_message "删除环境变量配置..."
rm -f /etc/profile.d/db2.sh

# 清理文件
print_message "清理文件..."
rm -rf ${DB2_HOME}
rm -rf /home/${DB2_INSTANCE}
rm -rf /home/${DB2_FENCED}

# 清理系统限制配置
print_message "清理系统配置..."
sed -i '/db2inst/d' /etc/security/limits.conf
sed -i '/db2fenc/d' /etc/security/limits.conf

print_message "DB2 清理完成！"
print_message "如需重新安装，请执行安装脚本。"