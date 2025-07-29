#!/bin/bash
# Prometheus 单机部署脚本（使用 /data/prometheus 路径）
# 包含：Prometheus + Node Exporter + Grafana
# 版本：2025.07.23
# 作者：Rancher

set -e

# 配置参数
PROMETHEUS_VERSION="2.46.0"
NODE_EXPORTER_VERSION="1.6.1"
GRAFANA_VERSION="10.1.1"
BASE_DIR="/data/prometheus"
CONFIG_DIR="${BASE_DIR}/config"
DATA_DIR="${BASE_DIR}/data"
LOG_DIR="${BASE_DIR}/logs"
SERVICE_USER="prometheus"
GRAFANA_ADMIN_PASSWORD="admin"

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
  useradd --system --no-create-home --shell /sbin/nologin "${SERVICE_USER}" || {
    echo "警告: 创建用户 ${SERVICE_USER} 失败，可能已存在或需要更高权限"
  }
fi

# 设置目录权限
chown -R "${SERVICE_USER}:${SERVICE_USER}" "${BASE_DIR}" || {
  echo "警告: 设置目录所有者失败，请检查权限"
  # 尝试使用sudo
  command -v sudo >/dev/null 2>&1 && {
    echo "尝试使用sudo设置权限..."
    sudo chown -R "${SERVICE_USER}:${SERVICE_USER}" "${BASE_DIR}"
  }
}
chmod -R 755 "${BASE_DIR}"

# 安装 Prometheus
echo "下载并安装 Prometheus ${PROMETHEUS_VERSION}..."
cd /tmp
# Prometheus 下载地址 - 直接使用官方地址，增加校验和重试机制
# 首先检查/tmp目录下是否已有安装包
PROMETHEUS_PACKAGE="prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

DOWNLOAD_SUCCESS=true
echo $PROMETHEUS_PACKAGE

if [ -f "$PROMETHEUS_PACKAGE" ]; then
  echo "检测到/tmp目录下已有安装包: $PROMETHEUS_PACKAGE"
  # 验证文件完整性
  echo "验证文件完整性..."
  if tar tzf "$PROMETHEUS_PACKAGE" &>/dev/null; then
    echo "文件验证成功，将直接使用已有安装包"
    DOWNLOAD_SUCCESS=true
  else
    echo "文件验证失败，可能已损坏，将重新下载"
    rm -f "$PROMETHEUS_PACKAGE"*
  fi
fi

# 如果没有找到有效的安装包，则下载
if [ $DOWNLOAD_SUCCESS = false ]; then
  echo "尝试从官方地址下载 Prometheus..."
  
  # 设置下载重试次数
  MAX_RETRY=3
  RETRY_COUNT=0
  
  while [ $RETRY_COUNT -lt $MAX_RETRY ] && [ $DOWNLOAD_SUCCESS = false ]; do
    RETRY_COUNT=$((RETRY_COUNT+1))
    
    # 清理可能存在的不完整文件
    rm -f "$PROMETHEUS_PACKAGE"*
    
    echo "下载尝试 $RETRY_COUNT/$MAX_RETRY..."
    echo "wget https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/$PROMETHEUS_PACKAGE"
    wget --continue --timeout=30 --tries=3 "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/$PROMETHEUS_PACKAGE" --no-check-certificate
    
    # 检查下载是否成功
    if [ $? -ne 0 ]; then
      echo "下载尝试 $RETRY_COUNT 失败"
      sleep 5
      continue
    fi
    
    # 验证文件完整性
    echo "验证文件完整性..."
    if tar tzf "$PROMETHEUS_PACKAGE" &>/dev/null; then
      echo "文件验证成功，继续安装"
      DOWNLOAD_SUCCESS=true
    else
      echo "文件验证失败，可能已损坏"
      sleep 5
    fi
  done
fi

# 如果所有下载尝试都失败
if [ $DOWNLOAD_SUCCESS = false ]; then
  echo "警告: 从官方地址下载失败或文件损坏，请检查网络连接或手动下载文件"
  echo "您可以尝试以下方法："
  echo "1. 检查网络连接和代理设置"
  echo "2. 使用浏览器或其他工具下载文件并放置在 /tmp 目录下："
  echo "   下载地址: https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/$PROMETHEUS_PACKAGE"
  echo "3. 如果您已手动下载文件到 /tmp 目录，请按 Enter 继续；否则按 Ctrl+C 中断此脚本"
  
  # 等待用户确认
  read -p "按 Enter 继续或 Ctrl+C 退出..." confirm
  
  # 检查用户可能手动下载的文件
  for possible_file in "/tmp/$PROMETHEUS_PACKAGE" "./$PROMETHEUS_PACKAGE"; do
    if [ -f "$possible_file" ]; then
      echo "检测到文件: $possible_file"
      # 验证文件完整性
      if tar tzf "$possible_file" &>/dev/null; then
        echo "文件验证成功，继续安装"
        # 如果文件不在当前目录，复制过来
        if [ "$possible_file" != "./$PROMETHEUS_PACKAGE" ]; then
          cp "$possible_file" "./$PROMETHEUS_PACKAGE"
        fi
        DOWNLOAD_SUCCESS=true
        break
      else
        echo "文件验证失败，可能已损坏: $possible_file"
      fi
    fi
  done
  
  # 如果仍然没有有效文件
  if [ $DOWNLOAD_SUCCESS = false ]; then
    echo "未检测到有效的安装文件，安装失败"
    exit 1
  fi
fi

tar xzf "$PROMETHEUS_PACKAGE"

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
# 首先检查/tmp目录下是否已有安装包
NODE_EXPORTER_PACKAGE="node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
DOWNLOAD_SUCCESS=true
echo $NODE_EXPORTER_PACKAGE

if [ -f "$NODE_EXPORTER_PACKAGE" ]; then
  echo "检测到/tmp目录下已有安装包: $NODE_EXPORTER_PACKAGE"
  # 验证文件完整性
  echo "验证文件完整性..."
  if tar tzf "$NODE_EXPORTER_PACKAGE" &>/dev/null; then
    echo "文件验证成功，将直接使用已有安装包"
    DOWNLOAD_SUCCESS=true
  else
    echo "文件验证失败，可能已损坏，将重新下载"
    rm -f "$NODE_EXPORTER_PACKAGE"*
  fi
fi

# 如果没有找到有效的安装包，则下载
if [ $DOWNLOAD_SUCCESS = false ]; then
  echo "尝试从官方地址下载 Node Exporter..."
  
  # 设置下载重试次数
  MAX_RETRY=3
  RETRY_COUNT=0
  
  while [ $RETRY_COUNT -lt $MAX_RETRY ] && [ $DOWNLOAD_SUCCESS = false ]; do
    RETRY_COUNT=$((RETRY_COUNT+1))
    
    # 清理可能存在的不完整文件
    rm -f "$NODE_EXPORTER_PACKAGE"*
    
    echo "下载尝试 $RETRY_COUNT/$MAX_RETRY..."
    echo "wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/$NODE_EXPORTER_PACKAGE"
    wget --continue --timeout=30 --tries=3 "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/$NODE_EXPORTER_PACKAGE" --no-check-certificate
    
    # 检查下载是否成功
    if [ $? -ne 0 ]; then
      echo "下载尝试 $RETRY_COUNT 失败"
      sleep 5
      continue
    fi
    
    # 验证文件完整性
    echo "验证文件完整性..."
    if tar tzf "$NODE_EXPORTER_PACKAGE" &>/dev/null; then
      echo "文件验证成功，继续安装"
      DOWNLOAD_SUCCESS=true
    else
      echo "文件验证失败，可能已损坏"
      sleep 5
    fi
  done
fi

# 如果所有下载尝试都失败
if [ $DOWNLOAD_SUCCESS = false ]; then
  echo "警告: 从官方地址下载 Node Exporter 失败或文件损坏，请检查网络连接或手动下载文件"
  echo "您可以尝试以下方法："
  echo "1. 检查网络连接和代理设置"
  echo "2. 使用浏览器或其他工具下载文件并放置在 /tmp 目录下："
  echo "   下载地址: https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/$NODE_EXPORTER_PACKAGE"
  echo "3. 如果您已手动下载文件到 /tmp 目录，请按 Enter 继续；否则按 Ctrl+C 中断此脚本"
  
  # 等待用户确认
  read -p "按 Enter 继续或 Ctrl+C 退出..." confirm
  
  # 检查用户可能手动下载的文件
  for possible_file in "/tmp/$NODE_EXPORTER_PACKAGE" "./$NODE_EXPORTER_PACKAGE"; do
    if [ -f "$possible_file" ]; then
      echo "检测到文件: $possible_file"
      # 验证文件完整性
      if tar tzf "$possible_file" &>/dev/null; then
        echo "文件验证成功，继续安装"
        # 如果文件不在当前目录，复制过来
        if [ "$possible_file" != "./$NODE_EXPORTER_PACKAGE" ]; then
          cp "$possible_file" "./$NODE_EXPORTER_PACKAGE"
        fi
        DOWNLOAD_SUCCESS=true
        break
      else
        echo "文件验证失败，可能已损坏: $possible_file"
      fi
    fi
  done
  
  # 如果仍然没有有效文件
  if [ $DOWNLOAD_SUCCESS = false ]; then
    echo "未检测到有效的 Node Exporter 安装文件，安装失败"
    exit 1
  fi
fi

tar xzf "$NODE_EXPORTER_PACKAGE"
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

# 安全设置
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# 安装 Grafana
echo "安装 Grafana ${GRAFANA_VERSION}..."

# 直接使用官方源
echo "使用官方源安装 Grafana..."
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

# 安装 Grafana 并处理可能的错误
if ! yum install -y "grafana-${GRAFANA_VERSION}"; then
  echo "警告: Grafana 安装失败，请检查网络连接或手动安装"
  echo "您可以尝试以下方法："
  echo "1. 检查网络连接和代理设置"
  echo "2. 手动安装 Grafana："
  echo "   a. 下载 RPM 包: https://packages.grafana.com/oss/rpm/grafana-${GRAFANA_VERSION}-1.x86_64.rpm"
  echo "   b. 使用 'rpm -ivh' 命令安装下载的 RPM 包"
  echo "3. 如果您已手动安装 Grafana，请按 Enter 继续；否则按 Ctrl+C 中断此脚本"
  
  # 等待用户确认
  read -p "按 Enter 继续或 Ctrl+C 退出..." confirm
  
  # 检查 Grafana 是否已安装
  if ! rpm -q grafana >/dev/null 2>&1; then
    echo "未检测到 Grafana 安装，脚本将退出"
    exit 1
  else
    echo "检测到 Grafana 已安装，继续配置..."
  fi
fi

# 配置 Grafana
echo "配置 Grafana..."

# 更健壮的密码替换
sed -i "s/;admin_password\s*=\s*admin/admin_password = ${GRAFANA_ADMIN_PASSWORD}/" /etc/grafana/grafana.ini
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

# 启动Prometheus并检查状态
echo "启动Prometheus服务..."
systemctl enable prometheus
systemctl start prometheus
if systemctl is-active prometheus >/dev/null 2>&1; then
  echo "Prometheus服务启动成功"
else
  echo "警告: Prometheus服务启动失败，请检查日志: journalctl -u prometheus"
fi

# 启动Node Exporter并检查状态
echo "启动Node Exporter服务..."
systemctl enable node_exporter
systemctl start node_exporter
if systemctl is-active node_exporter >/dev/null 2>&1; then
  echo "Node Exporter服务启动成功"
else
  echo "警告: Node Exporter服务启动失败，请检查日志: journalctl -u node_exporter"
fi

# 启动Grafana并检查状态
echo "启动Grafana服务..."
systemctl enable grafana-server
systemctl start grafana-server
if systemctl is-active grafana-server >/dev/null 2>&1; then
  echo "Grafana服务启动成功"
else
  echo "警告: Grafana服务启动失败，请检查日志: journalctl -u grafana-server"
fi

# 导入 Grafana 仪表盘
echo "导入 Grafana 仪表盘..."
# 增加等待时间确保 Grafana 完全启动
echo "等待Grafana服务完全启动..."
sleep 20

# 检查Grafana是否可访问
echo "检查Grafana服务是否可访问..."
GRAFANA_READY=false
for i in {1..6}; do
  if curl -s "http://localhost:3000/api/health" | grep -q 'ok'; then
    GRAFANA_READY=true
    echo "Grafana服务已就绪"
    break
  else
    echo "Grafana服务尚未就绪，等待10秒... ($i/6)"
    sleep 10
  fi
done

if [ "$GRAFANA_READY" = false ]; then
  echo "警告: Grafana服务未就绪，跳过仪表盘导入"
else
  # 添加数据源
  echo "添加Prometheus数据源..."
  DATASOURCE_ADDED=false
  for i in {1..3}; do
    RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
      -d '{
            "name": "Prometheus",
            "type": "prometheus",
            "access": "proxy",
            "url": "http://localhost:9091",
            "basicAuth": false
          }' \
      "http://admin:${GRAFANA_ADMIN_PASSWORD}@localhost:3000/api/datasources")
    
    if echo "$RESPONSE" | grep -q 'Datasource added' || echo "$RESPONSE" | grep -q 'Data source with same name already exists'; then
      DATASOURCE_ADDED=true
      echo "Prometheus数据源添加成功"
      break
    else
      echo "数据源添加失败，重试 ($i/3)..."
      echo "错误信息: $RESPONSE"
      sleep 5
    fi
  done
  
  # 导入仪表盘
  if [ "$DATASOURCE_ADDED" = true ]; then
    echo "导入Node Exporter仪表盘..."
    
    # 先获取仪表盘JSON
    echo "获取Node Exporter仪表盘JSON..."
    DASHBOARD_JSON=$(curl -s "https://grafana.com/api/dashboards/1860/revisions/30/download")
    
    if [ -z "$DASHBOARD_JSON" ] || ! echo "$DASHBOARD_JSON" | grep -q "title"; then
      echo "获取仪表盘JSON失败，尝试备用方法..."
      DASHBOARD_JSON=$(curl -s "https://grafana.com/api/dashboards/1860/revisions/latest/download")
    fi
    
    if [ -z "$DASHBOARD_JSON" ] || ! echo "$DASHBOARD_JSON" | grep -q "title"; then
      echo "无法获取仪表盘JSON，跳过导入"
    else
      echo "成功获取仪表盘JSON，准备导入..."
      # 导入仪表盘
      for i in {1..3}; do
          echo "尝试导入仪表盘 (尝试 $i/3)..."

          # 验证仪表盘 JSON 格式
          if ! jq -e . >/dev/null 2>&1 <<<"$DASHBOARD_JSON"; then
              echo "❌ 仪表盘 JSON 格式无效"
              # 不要退出，而是继续重试
              sleep 5
              continue
          fi

          # 创建临时文件
          DASHBOARD_FILE=$(mktemp)
          
          # 安全生成 JSON（无缩进）
          cat << EOF > "${DASHBOARD_FILE}"
{
  "dashboard": $DASHBOARD_JSON,
  "inputs": [{
    "name": "DS_PROMETHEUS",
    "type": "datasource",
    "pluginId": "prometheus",
    "value": "Prometheus"
  }],
  "overwrite": true
}
EOF

          # 发送请求
          RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
                    --data-binary @"${DASHBOARD_FILE}" \
                    "http://admin:${GRAFANA_ADMIN_PASSWORD}@localhost:3000/api/dashboards/db")
          curl_status=$?

          # 清理临时文件（即使失败也要清理）
          rm -f "${DASHBOARD_FILE}"

          # 检查 curl 状态
          if [ $curl_status -ne 0 ]; then
              echo "❌ curl 请求失败 (状态码: $curl_status)"
              # 继续重试而不是退出
              sleep 5
              continue
          fi

          # 使用 jq 检查响应
          if jq -e '.status == "success" or .imported == true or has("uid")' <<<"$RESPONSE" >/dev/null; then
              echo "✅ Node Exporter仪表盘导入成功"
              break
          else
              echo "❌ 仪表盘导入失败，重试 ($i/3)..."
              echo "详细错误:"
              # 使用 jq 格式化输出
              jq . <<<"$RESPONSE"
              sleep 5
          fi
      done
    fi
  else
    echo "警告: 由于数据源添加失败，跳过仪表盘导入"
  fi
fi

# 创建管理脚本
echo "创建管理脚本..."
cat > /usr/local/bin/prometheus-manage <<EOF
#!/bin/bash
# Prometheus 管理脚本
# 增强版 - 包含更多功能和错误处理

BASE_DIR="${BASE_DIR}"
CONFIG_DIR="${CONFIG_DIR}"
DATA_DIR="${DATA_DIR}"
LOG_DIR="${LOG_DIR}"

# 颜色定义
RED="\\033[0;31m"
GREEN="\\033[0;32m"
YELLOW="\\033[0;33m"
NC="\\033[0m" # No Color

# 打印彩色消息
print_info() {
  echo -e "${GREEN}[INFO]${NC} \$1"
}

print_warn() {
  echo -e "${YELLOW}[WARN]${NC} \$1"
}

print_error() {
  echo -e "${RED}[ERROR]${NC} \$1"
}

# 检查服务状态
check_service() {
  local service_name="\$1"
  if systemctl is-active "\$service_name" >/dev/null 2>&1; then
    print_info "\$service_name 服务正在运行"
    return 0
  else
    print_warn "\$service_name 服务未运行"
    return 1
  fi
}

# 主函数
ACTION="\$1"
SERVICE="\$2"

# 如果没有指定服务，则默认为所有服务
if [ -z "\$SERVICE" ]; then
  SERVICES=("prometheus" "node_exporter" "grafana-server")
else
  case "\$SERVICE" in
    prometheus|node_exporter|grafana|grafana-server)
      if [ "\$SERVICE" = "grafana" ]; then
        SERVICE="grafana-server"
      fi
      SERVICES=("\$SERVICE")
      ;;
    *)
      print_error "未知服务: \$SERVICE"
      echo "可用服务: prometheus, node_exporter, grafana"
      exit 1
      ;;
  esac
fi

case "\$ACTION" in
  start)
    for service in "\${SERVICES[@]}"; do
      print_info "启动 \$service 服务..."
      systemctl start "\$service"
      check_service "\$service"
    done
    ;;
  stop)
    for service in "\${SERVICES[@]}"; do
      print_info "停止 \$service 服务..."
      systemctl stop "\$service"
      if systemctl is-active "\$service" >/dev/null 2>&1; then
        print_error "\$service 服务停止失败"
      else
        print_info "\$service 服务已停止"
      fi
    done
    ;;
  restart)
    for service in "\${SERVICES[@]}"; do
      print_info "重启 \$service 服务..."
      systemctl restart "\$service"
      check_service "\$service"
    done
    ;;
  status)
    for service in "\${SERVICES[@]}"; do
      check_service "\$service"
      echo "详细状态:"
      systemctl status "\$service"
      echo ""
    done
    ;;
  logs)
    if [ "\${#SERVICES[@]}" -eq 1 ]; then
      case "\${SERVICES[0]}" in
        prometheus)
          print_info "查看 Prometheus 日志..."
          tail -f "${LOG_DIR}/prometheus.log" "${LOG_DIR}/prometheus_error.log"
          ;;
        node_exporter)
          print_info "查看 Node Exporter 日志..."
          tail -f "${LOG_DIR}/node_exporter.log" "${LOG_DIR}/node_exporter_error.log"
          ;;
        grafana-server)
          print_info "查看 Grafana 日志..."
          tail -f "/var/log/grafana/grafana.log"
          ;;
      esac
    else
      print_info "查看所有服务日志..."
      tail -f "${LOG_DIR}/"*.log "/var/log/grafana/grafana.log"
    fi
    ;;
  backup)
    BACKUP_DIR="/backup/prometheus"
    mkdir -p "\${BACKUP_DIR}"
    BACKUP_FILE="\${BACKUP_DIR}/prometheus-backup-\$(date +%Y%m%d-%H%M%S).tar.gz"
    
    print_info "创建备份: \${BACKUP_FILE}"
    print_info "备份数据目录..."
    
    # 停止服务以确保数据一致性
    print_warn "临时停止服务以确保数据一致性..."
    for service in "\${SERVICES[@]}"; do
      systemctl stop "\$service"
    done
    
    # 创建备份
    tar czf "\${BACKUP_FILE}" "${BASE_DIR}" && {
      print_info "备份已创建: \${BACKUP_FILE}"
    } || {
      print_error "备份创建失败"
    }
    
    # 重新启动服务
    print_info "重新启动服务..."
    for service in "\${SERVICES[@]}"; do
      systemctl start "\$service"
      check_service "\$service"
    done
    ;;
  check)
    print_info "检查 Prometheus 监控系统状态..."
    
    # 检查服务状态
    for service in "\${SERVICES[@]}"; do
      check_service "\$service"
    done
    
    # 检查端口
    print_info "检查端口状态..."
    command -v netstat >/dev/null 2>&1 || {
      print_warn "netstat 命令不可用，安装中..."
      yum install -y net-tools
    }
    
    netstat -tulpn | grep -E '9091|9100|3000' || {
      print_warn "未找到预期的监听端口"
    }
    
    # 检查数据目录
    print_info "检查数据目录..."
    du -sh "${DATA_DIR}" || print_warn "无法检查数据目录大小"
    
    # 检查配置文件
    print_info "检查配置文件..."
    if [ -f "${CONFIG_DIR}/prometheus.yml" ]; then
      print_info "Prometheus 配置文件存在"
      if command -v promtool >/dev/null 2>&1; then
        promtool check config "${CONFIG_DIR}/prometheus.yml" && {
          print_info "Prometheus 配置文件验证通过"
        } || {
          print_error "Prometheus 配置文件验证失败"
        }
      else
        print_warn "promtool 不可用，跳过配置验证"
      fi
    else
      print_error "Prometheus 配置文件不存在"
    fi
    ;;
  *)
    echo "用法: \$0 {start|stop|restart|status|logs|backup|check} [服务名称]"
    echo "服务名称可选值: prometheus, node_exporter, grafana"
    echo "示例:"
    echo "  \$0 start           # 启动所有服务"
    echo "  \$0 restart grafana # 仅重启 Grafana"
    echo "  \$0 logs prometheus # 查看 Prometheus 日志"
    echo "  \$0 check           # 检查监控系统状态"
    exit 1
    ;;
esac
EOF

chmod +x /usr/local/bin/prometheus-manage

# 完成信息
IP_ADDRESS=$(hostname -I | awk '{print $1}')

echo ""
echo -e "\033[1;32m========================================================\033[0m"
echo -e "\033[1;32mPrometheus 单机部署完成！\033[0m"
echo ""
echo -e "\033[1;34m系统信息:\033[0m"
echo -e "所有数据存储在: \033[1;36m${BASE_DIR}\033[0m"
echo -e "  配置目录: \033[1;36m${CONFIG_DIR}\033[0m"
echo -e "  数据目录: \033[1;36m${DATA_DIR}\033[0m"
echo -e "  日志目录: \033[1;36m${LOG_DIR}\033[0m"
echo ""
echo -e "\033[1;34m访问以下服务：\033[0m"
echo -e "- Prometheus:  \033[1;36mhttp://${IP_ADDRESS}:9091\033[0m"
echo -e "- Node Exporter: \033[1;36mhttp://${IP_ADDRESS}:9100/metrics\033[0m"
echo -e "- Grafana:     \033[1;36mhttp://${IP_ADDRESS}:3000\033[0m"
echo ""
echo -e "\033[1;34mGrafana 登录信息：\033[0m"
echo -e "- 用户名: \033[1;33madmin\033[0m"
echo -e "- 密码: \033[1;33m${GRAFANA_ADMIN_PASSWORD}\033[0m"
echo ""
echo -e "\033[1;34m已自动导入 Node Exporter 仪表盘 (ID: 1860)\033[0m"
echo ""
echo -e "\033[1;34m管理命令:\033[0m"
echo -e "  \033[1;36mprometheus-manage start\033[0m    # 启动服务"
echo -e "  \033[1;36mprometheus-manage stop\033[0m     # 停止服务"
echo -e "  \033[1;36mprometheus-manage restart\033[0m  # 重启服务"
echo -e "  \033[1;36mprometheus-manage status\033[0m   # 查看状态"
echo -e "  \033[1;36mprometheus-manage logs\033[0m     # 查看日志"
echo -e "  \033[1;36mprometheus-manage backup\033[0m   # 创建备份"
echo -e "  \033[1;36mprometheus-manage check\033[0m    # 检查系统状态"
echo ""
echo -e "\033[1;34m提示:\033[0m"
echo -e "1. 请确保防火墙已开放 9091、9100 和 3000 端口"
echo -e "2. 如需添加更多监控目标，请编辑 ${CONFIG_DIR}/prometheus.yml 文件"
echo -e "3. 更多 Grafana 仪表盘可在 https://grafana.com/grafana/dashboards/ 获取"
echo -e "4. 如遇问题，请使用 \033[1;36mprometheus-manage check\033[0m 命令检查系统状态"
echo -e "\033[1;32m========================================================\033[0m"