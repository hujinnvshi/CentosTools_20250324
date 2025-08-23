#!/bin/bash
# Consul 一键安装脚本
# 版本: 1.0
# 作者: 您的名字
# 描述: 在 Ubuntu 上安装 Consul 服务并部署到 /data/consul_version

set -euo pipefail

# 配置参数
CONSUL_VERSION="1.15.3"          # Consul 版本
CONSUL_USER="consul"              # Consul 运行用户
CONSUL_GROUP="consul"             # Consul 运行组
CONSUL_DIR="/data/consul_version" # Consul 安装目录
CONSUL_DATA_DIR="/data/consul_data" # Consul 数据目录
CONSUL_CONFIG_DIR="/etc/consul.d"  # Consul 配置目录
CONSUL_SERVICE_FILE="/etc/systemd/system/consul.service" # Systemd 服务文件

# 检查是否以 root 用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 此脚本必须以 root 权限运行"
    exit 1
fi

# 安装依赖
echo "安装依赖..."
apt-get update
apt-get install -y curl unzip jq

# 创建用户和组
if ! id -u "$CONSUL_USER" >/dev/null 2>&1; then
    echo "创建 Consul 用户: $CONSUL_USER"
    useradd --system --home $CONSUL_CONFIG_DIR --shell /bin/false $CONSUL_USER
fi

# 创建目录
echo "创建目录..."
mkdir -p $CONSUL_DIR $CONSUL_DATA_DIR $CONSUL_CONFIG_DIR
chown -R $CONSUL_USER:$CONSUL_GROUP $CONSUL_DIR $CONSUL_DATA_DIR $CONSUL_CONFIG_DIR

# 下载并安装 Consul
echo "下载 Consul v$CONSUL_VERSION..."
cd /tmp
curl -O https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip

echo "解压并安装 Consul..."
unzip consul_${CONSUL_VERSION}_linux_amd64.zip
mv consul $CONSUL_DIR/
chmod 755 $CONSUL_DIR/consul
ln -sf $CONSUL_DIR/consul /usr/local/bin/consul

# 创建配置文件
echo "创建基本配置文件..."
cat > $CONSUL_CONFIG_DIR/consul.hcl << EOF
# Consul 主配置文件
datacenter = "dc1"
data_dir = "$CONSUL_DATA_DIR"
server = true
bootstrap_expect = 1
ui = true
bind_addr = "0.0.0.0"
client_addr = "0.0.0.0"
EOF

# 设置权限
chown -R $CONSUL_USER:$CONSUL_GROUP $CONSUL_CONFIG_DIR
chmod 640 $CONSUL_CONFIG_DIR/consul.hcl

# 创建 systemd 服务文件
echo "创建 systemd 服务..."
cat > $CONSUL_SERVICE_FILE << EOF
[Unit]
Description=Consul Service Discovery Agent
Documentation=https://www.consul.io/
After=network-online.target
Wants=network-online.target

[Service]
User=$CONSUL_USER
Group=$CONSUL_GROUP
ExecStart=$CONSUL_DIR/consul agent -config-dir=$CONSUL_CONFIG_DIR
ExecReload=/bin/kill -HUP \$MAINPID
KillSignal=SIGTERM
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# 启用并启动服务
echo "启用并启动 Consul 服务..."
systemctl daemon-reload
systemctl enable consul
systemctl start consul

# 检查服务状态
echo "检查 Consul 服务状态..."
systemctl status consul --no-pager

# 验证安装
echo "验证 Consul 版本..."
consul version

echo "检查 Consul 成员..."
consul members

echo -e "\nConsul 安装完成!"
echo "安装目录: $CONSUL_DIR"
echo "数据目录: $CONSUL_DATA_DIR"
echo "配置目录: $CONSUL_CONFIG_DIR"
echo "Web UI: http://$(hostname -I | awk '{print $1}'):8500"