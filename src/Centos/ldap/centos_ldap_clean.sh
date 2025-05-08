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

# 创建临时目录用于备份
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "${TEMP_DIR}"' EXIT

# 备份现有配置（如果需要）
log "备份现有配置..."
if [ -d "/etc/openldap/slapd.d" ] && [ -n "$(ls -A /etc/openldap/slapd.d/)" ]; then
    cp -r /etc/openldap/slapd.d/* "${TEMP_DIR}/" || error "备份配置失败"
fi

# 停止LDAP服务
log "停止 LDAP 服务..."
if ps aux | grep slapd | grep -v grep > /dev/null; then
    kill $(ps aux | grep slapd | grep -v grep | awk '{print $2}')
    sleep 2
    # 二次检查确保服务已停止
    if ps aux | grep slapd | grep -v grep > /dev/null; then
        kill -9 $(ps aux | grep slapd | grep -v grep | awk '{print $2}') || error "强制停止LDAP服务失败"
    fi
fi

# 删除LDAP数据和配置
log "删除 LDAP 数据和配置..."

# 删除数据目录内容
rm -rf /var/lib/ldap/*
rm -f /var/lib/ldap/DB_CONFIG

# 删除配置目录
rm -rf /etc/openldap/slapd.d/*
rm -f /etc/openldap/slapd.conf

# 删除运行时文件
rm -rf /var/run/openldap/*

# 如果存在备份，恢复原始配置
if [ -d "${TEMP_DIR}" ] && [ -n "$(ls -A ${TEMP_DIR}/)" ]; then
    log "恢复原始配置..."
    mkdir -p /etc/openldap/slapd.d
    cp -r "${TEMP_DIR}"/* /etc/openldap/slapd.d/ || error "恢复配置失败"
fi

# 删除环境变量配置
log "删除环境变量配置..."
rm -f /etc/profile.d/ldap.sh

# 验证清理
log "验证清理..."

# 检查服务状态
if ps aux | grep slapd | grep -v grep > /dev/null; then
    error "LDAP 服务仍在运行"
fi

# 检查端口状态
if netstat -tuln | grep -q ':389'; then
    error "端口 389 仍被占用"
fi

# 检查数据目录
rm -fr /var/lib/ldap/*
if [ -n "$(ls -A /var/lib/ldap/ 2>/dev/null)" ]; then
    error "LDAP 数据目录未清空"
fi

# 检查配置目录
rm -fr /etc/openldap/slapd.d/*
if [ -n "$(ls -A /etc/openldap/slapd.d/ 2>/dev/null)" ]; then
    error "LDAP 配置目录未清空"
fi

# 检查运行时目录
rm -fr /var/run/openldap/*
if [ -n "$(ls -A /var/run/openldap/ 2>/dev/null)" ]; then
    error "LDAP 运行时目录未清空"
fi

# 清理日志文件
log "清理日志文件..."
if [ -f /var/log/messages ]; then
    sed -i '/slapd/d' /var/log/messages
fi
if [ -f /var/log/syslog ]; then
    sed -i '/slapd/d' /var/log/syslog
fi

log "LDAP 环境清理完成！"

# 提示用户
cat << EOF
清理内容：
1. 停止了 LDAP 服务
2. 清理了 LDAP 数据目录 (/var/lib/ldap/)
3. 清理了 LDAP 配置目录 (/etc/openldap/slapd.d/)
4. 删除了 LDAP 配置文件 (/etc/openldap/slapd.conf)
5. 清理了 LDAP 运行时目录 (/var/run/openldap/)
6. 删除了环境变量配置 (/etc/profile.d/ldap.sh)
7. 清理了系统日志中的LDAP相关记录
如果要重新安装 LDAP，请执行安装脚本。
EOF