#!/bin/bash
# Consul 一键安装脚本（稳定版本推荐）
# 版本: 2.1
# 描述: 安装稳定的 Consul 1.14.10 版本

set -euo pipefail

# 配置参数 - 使用推荐的稳定版本
CONSUL_VERSION="1.14.10"             # 推荐: 稳定的 LTS 版本
# CONSUL_VERSION="1.16.2"            # 备选: 最新稳定版
# CONSUL_VERSION="1.13.9"            # 备选: 成熟稳定版

CONSUL_USER="consul_$CONSUL_VERSION"
CONSUL_GROUP="consul_$CONSUL_VERSION"
CONSUL_DIR="/data/consul/base_$CONSUL_VERSION"
CONSUL_DATA_DIR="/data/consul/data_$CONSUL_VERSION"
CONSUL_CONFIG_DIR="/etc/consul.d/conf_$CONSUL_VERSION"
CONSUL_LOG_DIR="/var/log/consul_$CONSUL_VERSION"
CONSUL_SERVICE_NAME="consul_$CONSUL_VERSION"
CONSUL_SERVICE_FILE="/etc/systemd/system/${CONSUL_SERVICE_NAME}.service"

# 版本说明
echo "=================================================="
echo "Consul 稳定版本安装脚本"
echo "当前选择版本: $CONSUL_VERSION"
echo "版本类型: LTS (长期支持)"
echo "发布日期: 2023年"
echo "适用环境: 生产环境"
echo "=================================================="

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 此脚本必须以 root 权限运行" >&2
    exit 1
fi

# 安装依赖
echo "安装依赖..."
apt-get update
apt-get install -y curl unzip jq

# 创建版本化用户和组
if ! getent group "$CONSUL_GROUP" >/dev/null; then
    echo "创建用户组: $CONSUL_GROUP"
    groupadd --system "$CONSUL_GROUP"
fi

if ! id -u "$CONSUL_USER" >/dev/null; then
    echo "创建用户: $CONSUL_USER"
    useradd --system \
        --gid "$CONSUL_GROUP" \
        --home-dir "$CONSUL_CONFIG_DIR" \
        --no-create-home \
        --shell /bin/bash \
        "$CONSUL_USER"
fi

# 创建版本化目录
echo "创建目录..."
mkdir -p "$CONSUL_DIR" "$CONSUL_DATA_DIR" "$CONSUL_CONFIG_DIR" "$CONSUL_LOG_DIR"
chown -R "$CONSUL_USER:$CONSUL_GROUP" "$CONSUL_DIR" "$CONSUL_DATA_DIR" "$CONSUL_CONFIG_DIR" "$CONSUL_LOG_DIR"
chmod 750 "$CONSUL_DIR" "$CONSUL_DATA_DIR" "$CONSUL_CONFIG_DIR" "$CONSUL_LOG_DIR"

# 下载安装 Consul
echo "下载 Consul v$CONSUL_VERSION (稳定版)..."
cd /tmp
curl -O "https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip"

echo "解压并安装..."
unzip -o "consul_${CONSUL_VERSION}_linux_amd64.zip"
mv consul "$CONSUL_DIR/"
chown "$CONSUL_USER:$CONSUL_GROUP" "$CONSUL_DIR/consul"
chmod 750 "$CONSUL_DIR/consul"

# 创建版本化符号链接
BIN_LINK="/usr/local/bin/consul-$CONSUL_VERSION"
ln -sf "$CONSUL_DIR/consul" "$BIN_LINK"
ln -sf "$CONSUL_DIR/consul" "/usr/local/bin/consul"  # 默认链接

# 创建配置文件
echo "创建配置文件..."
cat > "$CONSUL_CONFIG_DIR/consul.hcl" << EOF
# Consul 服务器配置 - 稳定版本 $CONSUL_VERSION
datacenter = "dc1"
data_dir = "$CONSUL_DATA_DIR"

# 服务器模式配置
server = true
bootstrap_expect = 1
ui_config {
  enabled = true
}

# 网络配置
bind_addr = "0.0.0.0"
client_addr = "0.0.0.0"

# 性能调优
performance {
    raft_multiplier = 1
    leave_drain_time = "5s"
    rpc_hold_timeout = "15s"
}

# 选举超时调整（针对单节点）
raft_protocol = 3
autopilot {
  cleanup_dead_servers = true
  last_contact_threshold = "200ms"
  max_trailing_logs = 250
  server_stabilization_time = "10s"
}

# 日志配置
log_file = "$CONSUL_LOG_DIR/consul.log"
log_level = "WARN"
log_rotate_bytes = 10485760
log_rotate_max_files = 10
enable_syslog = false

# 安全配置 (可选)
# encrypt = "your-gossip-key-here"
# ca_file = "/path/to/ca.crt"
# cert_file = "/path/to/server.crt"
# key_file = "/path/to/server.key"
# verify_incoming = false
# verify_outgoing = false
# verify_server_hostname = false
EOF

# 设置配置权限
chown "$CONSUL_USER:$CONSUL_GROUP" "$CONSUL_CONFIG_DIR/consul.hcl"
chmod 640 "$CONSUL_CONFIG_DIR/consul.hcl"

# 创建 systemd 服务
echo "创建 systemd 服务..."
cat > "$CONSUL_SERVICE_FILE" << EOF
[Unit]
Description=Consul $CONSUL_VERSION Service (Stable LTS)
Documentation=https://www.consul.io/
After=network.target
Wants=network.target

[Service]
Type=simple
User=$CONSUL_USER
Group=$CONSUL_GROUP
ExecStart=$CONSUL_DIR/consul agent -config-dir=$CONSUL_CONFIG_DIR
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=no
LimitNOFILE=65536
NotifyAccess=all
TimeoutStartSec=300

# 日志配置
StandardOutput=file:$CONSUL_LOG_DIR/consul.stdout.log
StandardError=file:$CONSUL_LOG_DIR/consul.stderr.log
ExecStartPre=/bin/mkdir -p $CONSUL_LOG_DIR
ExecStartPre=/bin/chown $CONSUL_USER:$CONSUL_GROUP $CONSUL_LOG_DIR
ExecStartPre=/bin/chmod 750 $CONSUL_LOG_DIR

[Install]
WantedBy=multi-user.target
EOF

# 创建日志轮转配置
echo "配置日志轮转..."
cat > /etc/logrotate.d/consul_$CONSUL_VERSION << EOF
$CONSUL_LOG_DIR/*.log {
    daily
    rotate 30
    missingok
    compress
    delaycompress
    notifempty
    copytruncate
    dateext
    dateformat -%Y%m%d
    sharedscripts
    postrotate
        systemctl reload $CONSUL_SERVICE_NAME >/dev/null 2>&1 || true
    endscript
}
EOF

# 启用并启动服务
echo "启用服务..."
systemctl daemon-reload
systemctl enable "$CONSUL_SERVICE_NAME"

echo "启动 Consul 服务..."
if systemctl start "$CONSUL_SERVICE_NAME"; then
    echo "✓ Consul 服务启动成功"
else
    echo "✗ Consul 服务启动失败，检查日志: journalctl -u $CONSUL_SERVICE_NAME"
    exit 1
fi

# 等待服务启动
echo "等待服务就绪..."
sleep 5

# 检查服务状态
echo "服务状态检查:"
if systemctl is-active --quiet "$CONSUL_SERVICE_NAME"; then
    echo "✓ 服务运行正常"
else
    echo "✗ 服务运行异常"
    systemctl status "$CONSUL_SERVICE_NAME" --no-pager
    exit 1
fi

# 验证安装
echo -e "\n验证安装:"
echo "版本信息:"
"$BIN_LINK" version

echo -e "\n节点状态:"
"$BIN_LINK" members

echo -e "\n健康检查:"
"$BIN_LINK" operator raft list-peers

# 输出摘要信息
echo -e "\n=================================================="
echo "Consul 稳定版安装完成!"
echo "=================================================="
echo "版本: $CONSUL_VERSION (LTS)"
echo "服务: $CONSUL_SERVICE_NAME"
echo "状态: $(systemctl is-active $CONSUL_SERVICE_NAME)"
echo "Web UI: http://$(hostname -I | awk '{print $1}'):8500"
echo ""
echo "重要路径:"
echo "  安装目录: $CONSUL_DIR"
echo "  数据目录: $CONSUL_DATA_DIR"
echo "  配置目录: $CONSUL_CONFIG_DIR"
echo "  日志目录: $CONSUL_LOG_DIR"
echo ""
echo "常用命令:"
echo "  查看日志: tail -f $CONSUL_LOG_DIR/consul.log"
echo "  服务管理: systemctl {start|stop|restart} $CONSUL_SERVICE_NAME"
echo "  状态检查: consul operator raft list-peers"
echo "=================================================="