#!/bin/bash
set -euo pipefail

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo "❌ 此脚本必须使用 root 权限运行" >&2
    exit 1
fi

# 配置参数
REDIS_VERSION="7.0.12"  # 可修改为其他版本
INSTALL_DIR="/data/Redis_${REDIS_VERSION}"
CONFIG_FILE="${INSTALL_DIR}/redis.conf"
SERVICE_NAME="Redis_${REDIS_VERSION}"
RUN_USER="redis"  # 专用运行用户

# 安装依赖
function install_deps() {
    echo "🔧 安装系统依赖..."
    yum install -y epel-release
    yum install -y wget tar gcc make tcl
}

# 创建专用用户
function create_user() {
    if ! id -u "${RUN_USER}" >/dev/null 2>&1; then
        echo "👤 创建专用用户: ${RUN_USER}"
        useradd -r -s /sbin/nologin -d "${INSTALL_DIR}" "${RUN_USER}"
    fi
}

# 下载并编译 Redis
function install_redis() {
    echo "📦 下载 Redis v${REDIS_VERSION}..."
    local download_url="http://download.redis.io/releases/redis-${REDIS_VERSION}.tar.gz"
    
    if ! wget -qO /tmp/redis.tar.gz "${download_url}"; then
        echo "❌ Redis 下载失败"
        exit 1
    fi

    echo "📂 解压安装文件..."
    mkdir -p /tmp/redis-src
    tar -zxf /tmp/redis.tar.gz -C /tmp/redis-src --strip-components=1
    rm -f /tmp/redis.tar.gz

    echo "🔨 编译安装..."
    cd /tmp/redis-src
    make -j$(nproc)
    make PREFIX="${INSTALL_DIR}" install
    
    # 清理编译文件
    cd /
    rm -rf /tmp/redis-src
}

# 创建目录结构
function create_dirs() {
    echo "📁 创建目录结构..."
    mkdir -p "${INSTALL_DIR}"/{bin,data,logs,conf}
    chown -R ${RUN_USER}:${RUN_USER} "${INSTALL_DIR}"
    chmod -R 750 "${INSTALL_DIR}"
}

# 配置文件
function create_config() {
    echo "⚙️ 生成配置文件..."
    cat << EOF > "${CONFIG_FILE}"
# Redis 基础配置
daemonize yes
pidfile ${INSTALL_DIR}/redis.pid
port 6379
bind 0.0.0.0
timeout 1000
tcp-keepalive 300

# 数据存储
dir ${INSTALL_DIR}/data
dbfilename dump.rdb
save 900 1
save 300 10
save 60 10000
rdbcompression yes

# 日志配置
logfile ${INSTALL_DIR}/logs/redis.log
loglevel notice

# 安全配置
protected-mode yes
# 无密码 (生产环境不推荐)
requirepass "Secsmart#612"

# 性能优化
maxmemory 1gb
maxmemory-policy volatile-lru
maxclients 10000
tcp-backlog 511

# 高级配置
io-threads 4
io-threads-do-reads yes
EOF

    chown ${RUN_USER}:${RUN_USER} "${CONFIG_FILE}"
}

# 创建 systemd 服务
function create_service() {
    echo "🛠️ 创建 systemd 服务: ${SERVICE_NAME}"
    
    cat << EOF > /etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=Redis persistent key-value database (${REDIS_VERSION})
After=network.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_USER}
ExecStart=${INSTALL_DIR}/bin/redis-server ${CONFIG_FILE}
ExecStop=${INSTALL_DIR}/bin/redis-cli shutdown
Restart=always
RestartSec=5
LimitNOFILE=100000
WorkingDirectory=${INSTALL_DIR}

# 安全加固
PrivateTmp=yes
ProtectSystem=full
NoNewPrivileges=yes
ReadWritePaths=${INSTALL_DIR}/data ${INSTALL_DIR}/logs

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME}
}

# 启动服务
function start_service() {
    echo "🚀 启动 Redis 服务..."
    systemctl start ${SERVICE_NAME}
    
    # 等待服务启动
    sleep 2
    
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        echo "✅ 服务启动成功"
    else
        echo "❌ 服务启动失败"
        journalctl -u ${SERVICE_NAME} --no-pager -n 20
        exit 1
    fi
}

# 验证安装
function verify_installation() {
    echo "🔍 验证安装..."
    
    # 检查进程
    local pid=$(systemctl show -p MainPID ${SERVICE_NAME} | cut -d= -f2)
    if [[ $pid -gt 0 ]]; then
        echo "PID: $pid"
    else
        echo "❌ 未找到 Redis 进程"
        exit 1
    fi
    
    # 检查端口
    if ss -tln | grep -q ':6379 '; then
        echo "端口: 6379 (监听中)"
    else
        echo "❌ 端口 6379 未监听"
        exit 1
    fi
    
    # 简单测试
    local test_key="install_test_$(date +%s)"
    ${INSTALL_DIR}/bin/redis-cli set ${test_key} "success" >/dev/null
    local result=$(${INSTALL_DIR}/bin/redis-cli get ${test_key})
    
    if [[ "$result" == "success" ]]; then
        echo "✅ 功能测试通过"
        ${INSTALL_DIR}/bin/redis-cli del ${test_key} >/dev/null
    else
        echo "❌ 功能测试失败"
        exit 1
    fi
}

# 创建管理脚本
function create_management_scripts() {
    echo "📝 创建管理脚本..."
    
    cat << EOF > "${INSTALL_DIR}/redis-start.sh"
#!/bin/bash
systemctl start ${SERVICE_NAME}
EOF

    cat << EOF > "${INSTALL_DIR}/redis-stop.sh"
#!/bin/bash
systemctl stop ${SERVICE_NAME}
EOF

    cat << EOF > "${INSTALL_DIR}/redis-status.sh"
#!/bin/bash
systemctl status ${SERVICE_NAME}
EOF

    cat << EOF > "${INSTALL_DIR}/redis-logs.sh"
#!/bin/bash
journalctl -u ${SERVICE_NAME} -f
EOF

    chmod +x "${INSTALL_DIR}"/*.sh
    chown ${RUN_USER}:${RUN_USER} "${INSTALL_DIR}"/*.sh
}

# 显示安装摘要
function show_summary() {
    echo -e "\n🎉 Redis 安装完成!"
    echo "=============================================="
    echo "版本: Redis ${REDIS_VERSION}"
    echo "安装目录: ${INSTALL_DIR}"
    echo "配置文件: ${CONFIG_FILE}"
    echo "数据目录: ${INSTALL_DIR}/data"
    echo "日志目录: ${INSTALL_DIR}/logs"
    echo "服务名称: ${SERVICE_NAME}"
    echo "运行用户: ${RUN_USER}"
    echo "监听端口: 6379"
    echo "=============================================="
    echo "管理命令:"
    echo "启动: systemctl start ${SERVICE_NAME}"
    echo "停止: systemctl stop ${SERVICE_NAME}"
    echo "状态: systemctl status ${SERVICE_NAME}"
    echo "日志: journalctl -u ${SERVICE_NAME}"
    echo "=============================================="
    echo "客户端连接:"
    echo "${INSTALL_DIR}/bin/redis-cli"
    echo "=============================================="
    echo "管理脚本:"
    echo "启动: ${INSTALL_DIR}/redis-start.sh"
    echo "停止: ${INSTALL_DIR}/redis-stop.sh"
    echo "状态: ${INSTALL_DIR}/redis-status.sh"
    echo "日志: ${INSTALL_DIR}/redis-logs.sh"
    echo "=============================================="
}

# 主函数
function main() {
    install_deps
    create_user
    create_dirs
    install_redis
    create_config
    create_service
    start_service
    verify_installation
    create_management_scripts
    show_summary
}

main