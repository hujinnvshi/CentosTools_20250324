#!/bin/bash
set -euo pipefail

# 配置参数 - 这些参数必须与安装时一致
HIVE_VERSION="${HIVE_VERSION:-2.3.9}"
INSTANCE_ID="${INSTANCE_ID:-v2}"  # 实例标识，用于区分同版本的不同实例
HIVE_BASE_DIR="/data/hive_${HIVE_VERSION}_${INSTANCE_ID}"
MYSQL_HOST="172.16.48.233"
MYSQL_PORT="6005"
MYSQL_USER="admin"
MYSQL_PASS="Secsmart#612"
HIVE_META_DB="hive_meta_${HIVE_VERSION//./}_${INSTANCE_ID}"  # 动态生成元数据库名称

# 服务参数
HIVE_USER="hive_${HIVE_VERSION}_${INSTANCE_ID}"
SERVICE_LOG_DIR="$HIVE_BASE_DIR/logs"
PID_DIR="$HIVE_BASE_DIR/pids"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 状态函数
error() { echo -e "${RED}[ERROR] $* ${NC}" >&2; exit 1; }
warn() { echo -e "${YELLOW}[WARN] $* ${NC}" >&2; }
info() { echo -e "${GREEN}[INFO] $* ${NC}"; }

# 停止Hive服务
stop_hive_services() {
    info "停止Hive服务..."
    
    # 停止Metastore服务
    if [ -f "$PID_DIR/metastore.pid" ]; then
        local metastore_pid=$(cat "$PID_DIR/metastore.pid")
        if kill -0 $metastore_pid 2>/dev/null; then
            info "停止Metastore服务 (PID: $metastore_pid)"
            kill $metastore_pid
            sleep 2
            if kill -0 $metastore_pid 2>/dev/null; then
                warn "Metastore服务未正常退出，强制终止"
                kill -9 $metastore_pid
            fi
        fi
        rm -f "$PID_DIR/metastore.pid"
    else
        warn "未找到Metastore PID文件"
    fi
    
    # 停止HiveServer2服务
    if [ -f "$PID_DIR/hiveserver2.pid" ]; then
        local hiveserver_pid=$(cat "$PID_DIR/hiveserver2.pid")
        if kill -0 $hiveserver_pid 2>/dev/null; then
            info "停止HiveServer2服务 (PID: $hiveserver_pid)"
            kill $hiveserver_pid
            sleep 2
            if kill -0 $hiveserver_pid 2>/dev/null; then
                warn "HiveServer2服务未正常退出，强制终止"
                kill -9 $hiveserver_pid
            fi
        fi
        rm -f "$PID_DIR/hiveserver2.pid"
    else
        warn "未找到HiveServer2 PID文件"
    fi
    
    # 确保所有Hive进程已停止
    if pgrep -f "hive.metastore.HiveMetaStore" >/dev/null; then
        warn "检测到残留的Metastore进程，强制终止"
        pkill -9 -f "hive.metastore.HiveMetaStore"
    fi
    
    if pgrep -f "hive.server2.HiveServer2" >/dev/null; then
        warn "检测到残留的HiveServer2进程，强制终止"
        pkill -9 -f "hive.server2.HiveServer2"
    fi
    
    info "Hive服务已停止"
}

# 清理HDFS目录
clean_hdfs_directories() {
    info "清理HDFS上的Hive目录..."
    
    # 尝试从配置文件中获取仓库目录
    local warehouse_dir=""
    if [ -f "$HIVE_BASE_DIR/conf/hive-site.xml" ]; then
        warehouse_dir=$(grep -A1 'hive.metastore.warehouse.dir' "$HIVE_BASE_DIR/conf/hive-site.xml" | tail -1 | sed -e 's/<[^>]*>//g' | tr -d ' ')
    fi
    
    # 尝试从配置文件中获取临时目录
    local scratch_dir=""
    if [ -f "$HIVE_BASE_DIR/conf/hive-site.xml" ]; then
        scratch_dir=$(grep -A1 'hive.exec.scratchdir' "$HIVE_BASE_DIR/conf/hive-site.xml" | tail -1 | sed -e 's/<[^>]*>//g' | tr -d ' ')
    fi
    
    # 默认目录作为后备
    [ -z "$warehouse_dir" ] && warehouse_dir="/user/hive_${HIVE_VERSION}_${INSTANCE_ID}/warehouse"
    [ -z "$scratch_dir" ] && scratch_dir="/tmp/hive_${HIVE_VERSION}_${INSTANCE_ID}"
    
    # 清理仓库目录
    if hdfs dfs -test -d "$warehouse_dir" 2>/dev/null; then
        info "删除HDFS仓库目录: $warehouse_dir"
        hdfs dfs -rm -r -f "$warehouse_dir"
    else
        warn "HDFS仓库目录不存在: $warehouse_dir"
    fi
    
    # 清理临时目录
    if hdfs dfs -test -d "$scratch_dir" 2>/dev/null; then
        info "删除HDFS临时目录: $scratch_dir"
        hdfs dfs -rm -r -f "$scratch_dir"
    else
        warn "HDFS临时目录不存在: $scratch_dir"
    fi
    
    # 清理用户目录
    local user_dir="/user/$HIVE_USER"
    if hdfs dfs -test -d "$user_dir" 2>/dev/null; then
        info "删除HDFS用户目录: $user_dir"
        hdfs dfs -rm -r -f "$user_dir"
    else
        warn "HDFS用户目录不存在: $user_dir"
    fi
    
    info "HDFS清理完成"
}

# 清理元数据库
clean_metastore_database() {
    info "清理Hive元数据库: ${HIVE_META_DB}"
    
    # 删除元数据库
    if mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASS" \
        -e "SHOW DATABASES LIKE '${HIVE_META_DB}'" | grep -q "${HIVE_META_DB}"; then
        info "删除元数据库: ${HIVE_META_DB}"
        mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASS" \
            -e "DROP DATABASE IF EXISTS ${HIVE_META_DB}"
    else
        warn "元数据库不存在: ${HIVE_META_DB}"
    fi
    
    info "元数据库清理完成"
}

# 清理本地文件和目录
clean_local_files() {
    info "清理本地文件和目录..."
    
    # 删除安装目录
    if [ -d "$HIVE_BASE_DIR" ]; then
        info "删除Hive安装目录: $HIVE_BASE_DIR"
        rm -rf "$HIVE_BASE_DIR"
    else
        warn "Hive安装目录不存在: $HIVE_BASE_DIR"
    fi
    
    # 删除环境变量配置
    local env_file="/etc/profile.d/hive-${HIVE_VERSION}-${INSTANCE_ID}.sh"
    if [ -f "$env_file" ]; then
        info "删除环境变量配置: $env_file"
        rm -f "$env_file"
    else
        warn "环境变量配置文件不存在: $env_file"
    fi
    
    # 删除临时文件
    if [ -f "/tmp/apache-hive-${HIVE_VERSION}-bin.tar.gz" ]; then
        info "删除Hive安装包"
        # rm -f "/tmp/apache-hive-${HIVE_VERSION}-bin.tar.gz"
    fi
    
    info "本地文件清理完成"
}

# 清理系统用户
clean_system_user() {
    info "清理系统用户..."
    
    if id -u "$HIVE_USER" &>/dev/null; then
        info "删除系统用户: $HIVE_USER"
        userdel "$HIVE_USER"
    else
        warn "系统用户不存在: $HIVE_USER"
    fi
    
    info "系统用户清理完成"
}

# 主清理函数
clean_main() {
    info "开始清理 Hive $HIVE_VERSION (实例: $INSTANCE_ID)"
    
    # 确保root权限
    if [ "$(id -u)" -ne 0 ]; then
        error "请使用root用户运行此脚本"
    fi
    
    # 执行清理步骤
    stop_hive_services
    clean_hdfs_directories
    clean_metastore_database
    clean_local_files
    clean_system_user
    
    info "Hive环境清理完成!"
    echo "============================================================="
    info "已清理以下内容:"
    info "  - Hive服务进程"
    info "  - HDFS上的Hive目录"
    info "  - MySQL中的元数据库"
    info "  - 本地安装文件和目录"
    info "  - 环境变量配置"
    info "  - 系统用户"
    echo "============================================================="
}

# 执行入口
if [ $# -eq 0 ]; then
    echo "Hive多实例清理工具"
    echo "用法:"
    echo "  HIVE_VERSION=x.x.x INSTANCE_ID=id $0 clean"
    echo "示例:"
    echo "  HIVE_VERSION=2.3.9 INSTANCE_ID=v1 $0 clean"
    echo "  HIVE_VERSION=3.1.3 INSTANCE_ID=v2 $0 clean"
    exit 1
fi

case "$1" in
    clean)
        clean_main
        ;;
    *)
        echo "无效命令: $1"
        echo "可用命令: clean"
        exit 1
        ;;
esac