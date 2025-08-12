#!/bin/bash
set -euo pipefail

# http://172.16.47.57:9100/metrics
# 配置参数
NODE_EXPORTER_VERSION="1.6.1"
NODE_EXPORTER_USER="node_exporter"
ARCH="linux-amd64"  # 明确指定架构

# 下载最新版
echo "📦 下载 Node Exporter v${NODE_EXPORTER_VERSION}..."
#wget "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.${ARCH}.tar.gz" --no-check-certificate \
#     -O "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.tar.gz"
cp /tmp/node_exporter-1.6.1.linux-amd64.tar.gz /tmp/node_exporter-${NODE_EXPORTER_VERSION}.tar.gz

# 创建专用用户
echo "👤 创建专用用户: ${NODE_EXPORTER_USER}"
if ! id -u "${NODE_EXPORTER_USER}" >/dev/null 2>&1; then
    useradd -rs /bin/false "${NODE_EXPORTER_USER}"
else
    echo "⚠️ 用户 ${NODE_EXPORTER_USER} 已存在"
fi

# 解压安装
echo "📂 解压安装文件..."
tar -xzf "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.tar.gz" -C /tmp

# 移动二进制文件
echo "🚚 移动二进制文件..."
mv "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.${ARCH}/node_exporter" /usr/local/bin/

# 清理临时文件
echo "🧹 清理临时文件..."
# rm -rf "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.${ARCH}"
# rm -f "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.tar.gz"

# 创建系统服务
echo "🛠️ 创建系统服务..."
cat <<EOF > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=${NODE_EXPORTER_USER}
Group=${NODE_EXPORTER_USER}
ExecStart=/usr/local/bin/node_exporter
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# 设置权限
chown root:root /etc/systemd/system/node_exporter.service
chmod 644 /etc/systemd/system/node_exporter.service

# 启动服务
echo "🚀 启动服务..."
systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

# 验证安装
echo "✅ 验证安装..."
sleep 2
if systemctl is-active --quiet node_exporter; then
    echo "Node Exporter 运行正常!"
    echo "访问地址: http://$(hostname -I | awk '{print $1}'):9100/metrics"
else
    echo "❌ 启动失败，查看日志: journalctl -u node_exporter"
    exit 1
fi