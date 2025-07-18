#!/bin/bash
# Prometheus 单机部署脚本（使用 /data/prometheus 路径）
# 包含：Prometheus + Node Exporter + Grafana
# 版本：2023.10
# 作者：运维专家

set -e

# 配置参数
PROMETHEUS_VERSION="2.45.0"
NODE_EXPORTER_VERSION="1.6.1"
GRAFANA_VERSION="10.1.1"
BASE_DIR="/data/prometheus"
CONFIG_DIR="${BASE_DIR}/config"
DATA_DIR="${BASE_DIR}/data"
LOG_DIR="${BASE_DIR}/logs"
SERVICE_USER="prometheus"
GRAFANA_ADMIN_PASSWORD="SecurePass123!"  # 修改为您的安全密码

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
  echo "错误：此脚本必须以 root 权限运行"
  exit 1
fi

# 安装依赖
echo "安装系统依赖..."
yum install -y wget tar curl firewalld

# 创建基础目录
echo "创建目录结构..."
mkdir -p "${BASE_DIR}"
mkdir -p "${CONFIG_DIR}" "${DATA_DIR}" "${LOG_DIR}"

# 创建系统用户
echo "创建服务用户..."
if ! id "${SERVICE_USER}" &>/dev/null; then
  useradd --system --no-create-home --shell /sbin/nologin "${SERVICE_USER}"
fi

# 设置目录权限
chown -R "${SERVICE_USER}:${SERVICE_USER}" "${BASE_DIR}"
chmod -R 755 "${BASE_DIR}"

# 安装 Prometheus
echo "下载并安装 Prometheus ${PROMETHEUS_VERSION}..."
cd /tmp
# Prometheus 下载地址
wget -q "https://mirrors.aliyun.com/prometheus/${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
tar xzf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
cd "prometheus-${PROMETHEUS_VERSION}.linux-amd64"

install -m 0755 prometheus /usr/local/bin/
install -m 0755 promtool /usr/local/bin/
cp -r consoles/ console_libraries/ "${CONFIG_DIR}/"
chown -R "${SERVICE_USER}:${SERVICE_USER}" "${CONFIG_DIR}/consoles" "${CONFIG_DIR}/console_libraries"

# 创建 Prometheus 配置文件
echo "创建 Prometheus 配置文件..."
cat > "${CONFIG_DIR}/prometheus.yml" <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9091']

  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
EOF

# 创建 Prometheus systemd 服务（使用新路径）
echo "创建 Prometheus systemd 服务..."
cat > /etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus
Documentation=https://prometheus.io/docs/introduction/overview/
After=network.target

[Service]
User=${SERVICE_USER}
Group=${SERVICE_USER}
Type=simple
ExecStart=/usr/local/bin/prometheus \\
  --config.file=${CONFIG_DIR}/prometheus.yml \\
  --storage.tsdb.path=${DATA_DIR} \\
  --web.console.templates=${CONFIG_DIR}/consoles \\
  --web.console.libraries=${CONFIG_DIR}/console_libraries \\
  --web.listen-address=0.0.0.0:9091 \\
  --web.enable-lifecycle \\
  --log.level=info \\
  --log.format=json \\
  --storage.tsdb.retention.time=15d

Restart=always
RestartSec=3
SyslogIdentifier=prometheus
StandardOutput=append:${LOG_DIR}/prometheus.log
StandardError=append:${LOG_DIR}/prometheus_error.log

# 设置文件描述符限制
LimitNOFILE=65536

# 安全设置
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# 安装 Node Exporter
echo "下载并安装 Node Exporter ${NODE_EXPORTER_VERSION}..."
cd /tmp
# Node Exporter 下载地址（修正后的URL）
wget -q "https://mirrors.aliyun.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
cd "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"

install -m 0755 node_exporter /usr/local/bin/

# 创建 Node Exporter systemd 服务
echo "创建 Node Exporter systemd 服务..."
cat > /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Node Exporter
Documentation=https://prometheus.io/docs/guides/node-exporter/
After=network.target

[Service]
User=${SERVICE_USER}
Group=${SERVICE_USER}
Type=simple
ExecStart=/usr/local/bin/node_exporter \\
  --collector.systemd \\
  --collector.processes \\
  --collector.filesystem \\
  --collector.netdev \\
  --collector.meminfo \\
  --collector.cpu \\
  --web.listen-address=:9100

Restart=always
RestartSec=3
SyslogIdentifier=node_exporter
StandardOutput=append:${LOG_DIR}/node_exporter.log
StandardError=append:${LOG_DIR}/node_exporter_error.log

# 安全设置
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# 安装 Grafana
echo "安装 Grafana ${GRAFANA_VERSION}..."
cat > /etc/yum.repos.d/grafana.repo <<EOF
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

yum install -y "grafana-${GRAFANA_VERSION}"

# 配置 Grafana
echo "配置 Grafana..."
# 更健壮的密码替换
sed -i "s/^;admin_password\s*=\s*admin/admin_password = ${GRAFANA_ADMIN_PASSWORD}/" /etc/grafana/grafana.ini
sed -i "s/;disable_gravatar = false/disable_gravatar = true/" /etc/grafana/grafana.ini

# 创建日志轮转配置
echo "配置日志轮转..."
cat > /etc/logrotate.d/prometheus <<EOF
${LOG_DIR}/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 ${SERVICE_USER} ${SERVICE_USER}
    sharedscripts
    postrotate
        systemctl try-reload-or-restart prometheus >/dev/null 2>&1 || true
        systemctl try-reload-or-restart node_exporter >/dev/null 2>&1 || true
    endscript
}
EOF

# 启动服务
echo "启动服务..."
systemctl daemon-reload

systemctl enable --now prometheus
systemctl enable --now node_exporter
systemctl enable --now grafana-server

# 导入 Grafana 仪表盘
echo "导入 Grafana 仪表盘..."
# 增加等待时间确保 Grafana 完全启动
sleep 15

# 添加重试机制
for i in {1..3}; do
  curl -X POST -H "Content-Type: application/json" \
    -d '{
          "name": "Prometheus",
          "type": "prometheus",
          "access": "proxy",
          "url": "http://localhost:9091",
          "basicAuth": false
        }' \
    "http://admin:${GRAFANA_ADMIN_PASSWORD}@localhost:3000/api/datasources" && break
  
  echo "数据源导入失败，重试 ($i/3)..."
  sleep 5
done

for i in {1..3}; do
  curl -X POST -H "Content-Type: application/json" \
    -d '{
          "dashboard": {
            "id": 1860,
            "overwrite": true
          }
        }' \
    "http://admin:${GRAFANA_ADMIN_PASSWORD}@localhost:3000/api/dashboards/import" && break
  
  echo "仪表盘导入失败，重试 ($i/3)..."
  sleep 5
done

# 创建管理脚本
echo "创建管理脚本..."
cat > /usr/local/bin/prometheus-manage <<EOF
#!/bin/bash
# Prometheus 管理脚本

ACTION=\$1

case \$ACTION in
  start)
    systemctl start prometheus node_exporter grafana-server
    ;;
  stop)
    systemctl stop prometheus node_exporter grafana-server
    ;;
  restart)
    systemctl restart prometheus node_exporter grafana-server
    ;;
  status)
    systemctl status prometheus node_exporter grafana-server
    ;;
  logs)
    tail -f ${LOG_DIR}/prometheus.log ${LOG_DIR}/node_exporter.log
    ;;
  backup)
    BACKUP_DIR="/backup"
    mkdir -p "\${BACKUP_DIR}"
    BACKUP_FILE="\${BACKUP_DIR}/prometheus-backup-\$(date +%Y%m%d-%H%M%S).tar.gz"
    tar czf "\${BACKUP_FILE}" "${BASE_DIR}"
    echo "备份已创建: \${BACKUP_FILE}"
    ;;
  *)
    echo "用法: \$0 {start|stop|restart|status|logs|backup}"
    exit 1
    ;;
esac
EOF

chmod +x /usr/local/bin/prometheus-manage

# 完成信息
IP_ADDRESS=$(hostname -I | awk '{print $1}')

echo ""
echo "========================================================"
echo "Prometheus 单机部署完成！"
echo ""
echo "所有数据存储在: ${BASE_DIR}"
echo "  配置目录: ${CONFIG_DIR}"
echo "  数据目录: ${DATA_DIR}"
echo "  日志目录: ${LOG_DIR}"
echo ""
echo "访问以下服务："
echo "- Prometheus:  http://${IP_ADDRESS}:9091"
echo "- Node Exporter: http://${IP_ADDRESS}:9100/metrics"
echo "- Grafana:     http://${IP_ADDRESS}:3000"
echo ""
echo "Grafana 登录信息："
echo "- 用户名: admin"
echo "- 密码: ${GRAFANA_ADMIN_PASSWORD}"
echo ""
echo "已自动导入 Node Exporter 仪表盘 (ID: 1860)"
echo ""
echo "管理命令:"
echo "  prometheus-manage start    # 启动服务"
echo "  prometheus-manage stop     # 停止服务"
echo "  prometheus-manage status   # 查看状态"
echo "  prometheus-manage logs     # 查看日志"
echo "  prometheus-manage backup   # 创建备份"
echo "========================================================"