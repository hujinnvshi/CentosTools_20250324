#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 日志函数
log() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    error "请使用 root 用户执行此脚本"
fi

# 停止LDAP服务
log "停止 LDAP 服务..."
if ps aux | grep slapd | grep -v grep > /dev/null; then
    kill $(ps aux | grep slapd | grep -v grep | awk '{print $2}')
fi

# 删除LDAP数据和配置
log "删除 LDAP 数据和配置..."
# 删除数据目录
rm -rf /var/lib/ldap/*

# 删除配置目录
rm -rf /etc/openldap/slapd.d/*

# 如果存在备份，恢复原始配置
if [ -d "/etc/openldap/slapd.d.bak" ]; then
    log "恢复原始配置..."
    cp -r /etc/openldap/slapd.d.bak/* /etc/openldap/slapd.d/
    rm -rf /etc/openldap/slapd.d.bak
fi

# 删除环境变量配置
log "删除环境变量配置..."
rm -f /etc/profile.d/ldap.sh

# 验证清理
log "验证清理..."
if ps aux | grep slapd | grep -v grep > /dev/null; then
    error "LDAP 服务仍在运行"
fi

if [ -n "$(ls -A /var/lib/ldap/)" ]; then
    error "LDAP 数据目录未清空"
fi

if [ -n "$(ls -A /etc/openldap/slapd.d/)" ]; then
    error "LDAP 配置目录未清空"
fi

log "LDAP 环境清理完成！"

# 提示用户
cat << EOF

${GREEN}LDAP 清理完成！${NC}

清理内容：
1. 停止了 LDAP 服务
2. 清理了 LDAP 数据目录 (/var/lib/ldap/)
3. 清理了 LDAP 配置目录 (/etc/openldap/slapd.d/)
4. 删除了环境变量配置 (/etc/profile.d/ldap.sh)

如果要重新安装 LDAP，请执行安装脚本。

EOF