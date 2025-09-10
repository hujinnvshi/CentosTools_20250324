#!/bin/bash
# VictoriaMetrics Single-Node Installer for CentOS 7.9
# Author: Your Name
# Date: $(date +%Y-%m-%d)
# Version: 1.1

# 配置参数 - 根据实际环境修改
VM_VERSION="v1.100.0"            # VictoriaMetrics版本
VM_USER="victoriametrics"         # 运行用户
VM_GROUP="victoriametrics"        # 运行组
VM_PORT=8428                      # 监听端口
DATA_DIR="/var/lib/victoriametrics" # 数据存储目录
CONFIG_DIR="/etc/victoriametrics"  # 配置文件目录
LOG_DIR="/var/log/victoriametrics" # 日志目录
RETENTION_PERIOD="1h"             # 数据保留时间（建议1小时）

# 检查是否以root运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本必须以root权限运行"
    exit 1
fi

# 创建用户和组
if ! id -u $VM_USER >/dev/null 2>&1; then
    echo "创建用户和组: $VM_USER:$VM_GROUP"
    groupadd -r $VM_GROUP
    useradd -r -s /sbin/nologin -g $VM_GROUP $VM_USER
fi

# 创建目录结构
echo "创建目录结构..."
mkdir -p $DATA_DIR $CONFIG_DIR $LOG_DIR
chown -R $VM_USER:$VM_GROUP $DATA_DIR $CONFIG_DIR $LOG_DIR
chmod 755 $DATA_DIR $CONFIG_DIR $LOG_DIR

# 下载VictoriaMetrics
echo "下载VictoriaMetrics $VM_VERSION..."
VM_URL="https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/$VM_VERSION/victoria-metrics-linux-amd64-$VM_VERSION.tar.gz"
TMP_DIR=$(mktemp -d)
curl -L $VM_URL -o $TMP_DIR/vm.tar.gz

# 检查下载是否成功
if [ $? -ne 0 ]; then
    echo "错误：下载VictoriaMetrics失败"
    exit 1
fi

# 解压并安装
echo "安装VictoriaMetrics..."
tar -xzf $TMP_DIR/vm.tar.gz -C $TMP_DIR
mv $TMP_DIR/victoria-metrics-prod /usr/local/bin/victoria-metrics
chmod +x /usr/local/bin/victoria-metrics
chown $VM_USER:$VM_GROUP /usr/local/bin/victoria-metrics

# 清理临时文件
rm -rf $TMP_DIR

# 创建示例重标签配置文件
echo "创建重标签配置文件..."
cat > $CONFIG_DIR/relabel.yml <<EOF
# VictoriaMetrics重标签配置
# 只保留以node_或vmware_开头的指标
- action: keep
  source_labels: [__name__]
  regex: "node_.*|vmware_.*"
EOF
chown $VM_USER:$VM_GROUP $CONFIG_DIR/relabel.yml

# 创建systemd服务文件
echo "创建systemd服务..."
cat > /etc/systemd/system/victoriametrics.service <<EOF
[Unit]
Description=VictoriaMetrics - fast, cost-effective monitoring solution
Documentation=https://docs.victoriametrics.com
After=network.target

[Service]
Type=simple
User=$VM_USER
Group=$VM_GROUP
ExecStart=/usr/local/bin/victoria-metrics \\
    --httpListenAddr=:$VM_PORT \\
    --storageDataPath=$DATA_DIR \\
    --retentionPeriod=$RETENTION_PERIOD \\
    --remoteWrite.urlRelabelConfig=$CONFIG_DIR/relabel.yml \\
    --loggerFormat=json \\
    --loggerOutput=$LOG_DIR/victoriametrics.log

# 资源限制
LimitNOFILE=65536
LimitNPROC=32000
LimitFSIZE=infinity
TimeoutStopSec=30
Restart=on-failure
RestartSec=5
StartLimitInterval=5min
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF

# 启用日志轮转
echo "配置日志轮转..."
cat > /etc/logrotate.d/victoriametrics <<EOF
$LOG_DIR/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 $VM_USER $VM_GROUP
    sharedscripts
    postrotate
        # 发送USR1信号重新打开日志文件
        kill -USR1 \$(cat /var/run/victoriametrics.pid 2>/dev/null) 2>/dev/null || true
    endscript
}
EOF

# 启动服务
echo "启动VictoriaMetrics服务..."
systemctl daemon-reload
systemctl enable victoriametrics
systemctl start victoriametrics

# 检查服务状态
echo "检查服务状态..."
if systemctl is-active --quiet victoriametrics; then
    echo "VictoriaMetrics服务已成功启动"
    systemctl status victoriametrics --no-pager
else
    echo "错误：VictoriaMetrics服务启动失败"
    journalctl -u victoriametrics -n 50 --no-pager
    exit 1
fi

# 创建README文件
echo "创建README.md..."
SERVER_IP=$(hostname -I | awk '{print $1}' | head -1)
cat > /root/victoriametrics-README.md <<EOF
# VictoriaMetrics 单实例部署指南

## 基本信息
- **版本**: $VM_VERSION
- **监听端口**: $VM_PORT
- **数据目录**: $DATA_DIR
- **配置文件**: $CONFIG_DIR
- **日志目录**: $LOG_DIR

## 服务管理命令
- 启动服务: \`systemctl start victoriametrics\`
- 停止服务: \`systemctl stop victoriametrics\`
- 重启服务: \`systemctl restart victoriametrics\`
- 查看状态: \`systemctl status victoriametrics\`
- 查看日志: \`journalctl -u victoriametrics -f\`

## 数据访问
- Web UI: http://${SERVER_IP}:$VM_PORT
- 指标列表: http://${SERVER_IP}:$VM_PORT/metrics
- Prometheus远程写入地址: http://${SERVER_IP}:$VM_PORT/api/v1/write

## 配置文件
- 主配置文件: /etc/systemd/system/victoriametrics.service
- 重标签配置: $CONFIG_DIR/relabel.yml

## 数据管理
- 数据保留时间: $RETENTION_PERIOD
- 清理旧数据: 自动管理，无需手动干预

## 健康检查
\`curl http://localhost:$VM_PORT/health\`

## 升级指南
1. 下载新版本: \`curl -L https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/<新版本>/victoria-metrics-linux-amd64-<新版本>.tar.gz -o /tmp/vm-new.tar.gz\`
2. 停止服务: \`systemctl stop victoriametrics\`
3. 备份旧版本: \`mv /usr/local/bin/victoria-metrics /usr/local/bin/victoria-metrics-old\`
4. 安装新版本: \`tar -xzf /tmp/vm-new.tar.gz -C /tmp && mv /tmp/victoria-metrics-prod /usr/local/bin/victoria-metrics\`
5. 启动服务: \`systemctl start victoriametrics\`
EOF

echo "安装完成！"
echo "VictoriaMetrics 已成功安装并启动"
echo "服务状态: systemctl status victoriametrics"
echo "详细文档请查看: /root/victoriametrics-README.md"
echo "Web界面: http://${SERVER_IP}:$VM_PORT"