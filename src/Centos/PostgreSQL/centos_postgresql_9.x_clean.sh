#!/bin/bash

# 定义变量
PG_VERSION="9.4.26"
PG_USER="PostgreSQL_${PG_VERSION}_V1"
PG_HOME="/data/PostgreSQL_${PG_VERSION}_V1"
PG_DATA="$PG_HOME/data"
PG_BASE="$PG_HOME/base"
PG_SOFT="$PG_HOME/soft"
PG_CONF="$PG_HOME/conf"

# 检查是否以 root 用户运行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本"
  exit 1
fi

# 停止 PostgreSQL 服务
if systemctl is-active --quiet postgresql_$PG_VERSION 2>/dev/null; then
    systemctl stop postgresql_$PG_VERSION || { echo "停止 PostgreSQL 服务失败"; exit 1; }
    echo "PostgreSQL 服务已停止"
else
    echo "PostgreSQL 服务未运行，跳过停止操作"
fi

# 禁用服务
if systemctl is-enabled --quiet postgresql_$PG_VERSION 2>/dev/null; then
    systemctl disable postgresql_$PG_VERSION || { echo "禁用 PostgreSQL 服务失败"; exit 1; }
    echo "PostgreSQL 服务已禁用"
else
    echo "PostgreSQL 服务未启用，跳过禁用操作"
fi

# 删除服务文件
if [ -f "/etc/systemd/system/postgresql_$PG_VERSION.service" ]; then
    rm -f /etc/systemd/system/postgresql_$PG_VERSION.service || { echo "删除服务文件失败"; exit 1; }
    echo "PostgreSQL 服务文件已删除"
else
    echo "PostgreSQL 服务文件不存在，跳过删除操作"
fi

# 重新加载 systemd 配置
systemctl daemon-reload || { echo "重新加载 systemd 配置失败"; exit 1; }
echo "systemd 配置已重新加载"

# 删除用户和主目录
if id -u $PG_USER >/dev/null 2>&1; then
    userdel $PG_USER || { echo "删除用户失败"; exit 1; }
    echo "用户 $PG_USER 已删除"
else
    echo "用户 $PG_USER 不存在，跳过删除操作"
fi

if [ -d "$PG_HOME" ]; then
    rm -rf $PG_HOME || { echo "删除主目录失败"; exit 1; }
    echo "主目录 $PG_HOME 已删除"
else
    echo "主目录 $PG_HOME 不存在，跳过删除操作"
fi

# 删除自动启动配置
if [ -f "/etc/rc.local" ]; then
    # 使用 grep 检查是否存在目标行，避免 sed 执行失败
    if grep -q "pg_ctl restart -D $PG_DATA" /etc/rc.local; then
        sed -i.bak "/pg_ctl restart -D $PG_DATA/d" /etc/rc.local || { echo "删除自动启动配置失败"; exit 1; }
        echo "自动启动配置已删除"
    else
        echo "自动启动配置不存在，跳过删除操作"
    fi
else
    echo "/etc/rc.local 文件不存在，跳过删除自动启动配置"
fi

echo "PostgreSQL $PG_VERSION 清理完成！"