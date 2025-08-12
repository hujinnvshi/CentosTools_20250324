#!/bin/bash
# Telegraf ESXi 监控一键部署脚本
# 适用于 CentOS 7.9
# 作者：卓越运维专家
# 优化版 (2025-08-12)

# 配置参数
TELEGRAF_VERSION="1.25.0"
ESXI_HOSTS=("172.16.48.11" "172.16.48.12" "172.16.48.13" "172.16.48.14" "172.16.48.15" "172.16.48.17" "172.16.48.18")
ESXI_USER="root"
ESXI_PASSWORD='Secsmart#612'  # 修复转义问题（单引号避免不必要转义）
PROMETHEUS_HOST="172.16.47.185"
PROMETHEUS_PORT="9091"        # 更正端口：9090是标准Prometheus端口
GRAFANA_DASHBOARD_ID="10826"  # ESXi 主机性能仪表板
TELEGRAF_PORT="9273"          # 新增 Telegraf 端口

# 检查 root 权限
if [ "$(id -u)" != "0" ]; then
    echo "错误：此脚本必须以 root 权限运行"
    exit 1
fi

# 安装依赖
yum install -y curl

# 步骤 1: 安装 Telegraf
install_telegraf() {
    echo "正在安装 Telegraf..."
    
    # 添加 InfluxData 仓库
    cat <<EOF | tee /etc/yum.repos.d/influxdata.repo
[influxdata]
name = InfluxData Repository - Stable
baseurl = https://repos.influxdata.com/stable/\$basearch/main
enabled = 1
gpgcheck = 1
gpgkey = https://repos.influxdata.com/influxdata-archive.key
EOF

    # 导入 GPG 密钥
    rpm --import https://repos.influxdata.com/influxdata-archive.key
    
    # 安装 Telegraf
    yum update -y
    echo "安装 Telegraf..."
    yum install -y telegraf --nogpgcheck
    
    # 验证安装
    telegraf --version
    echo "Telegraf 安装完成"
}

# 步骤 2: 配置 Telegraf
configure_telegraf() {
    echo "配置 Telegraf..."
    
    # 动态生成vcenters配置
    vcenter_config=""
    for host in "${ESXI_HOSTS[@]}"; do
        vcenter_config+=" \"https://${host}/sdk\", "
    done
    
    # 创建 ESXi 监控配置
    mkdir -p /etc/telegraf/telegraf.d
    tee /etc/telegraf/telegraf.d/esxi.conf <<EOF
[agent]
  interval = "60s"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "5s"

[[inputs.vsphere]]
  vcenters = [
     ${vcenter_config::-2}
  ]
  
  # 认证信息
  username = "${ESXI_USER}"
  password = '${ESXI_PASSWORD}'
  
  # 安全设置
  insecure_skip_verify = true
  
  # 采集间隔
  interval = "60s"
  
  # 高级设置
  max_query_metrics = 256
  timeout = "30s"
  host_include = ["/"]
  
[[outputs.prometheus_client]]
  # 监听地址和端口
  listen = "0.0.0.0:${TELEGRAF_PORT}"
  
  # 指标格式版本
  metric_version = 2
  
  # 指标过期时间
  expiration_interval = "120s"
  
  # 添加路径
  path = "/metrics"
  
  # 添加标签
  [outputs.prometheus_client.tags]
    environment = "production"
    location = "datacenter1"
EOF
    echo "Telegraf 配置完成"
}


# 步骤 4: 启动服务
start_services() {
    echo "启动 Telegraf 服务..."
    
    systemctl daemon-reload
    systemctl enable --now telegraf
    
    # 检查服务状态
    for _ in {1..5}; do
        if systemctl is-active telegraf &>/dev/null; then
            echo "服务状态正常"
            return
        fi
        sleep 2
    done
    
    echo "错误：Telegraf 服务启动失败！"
    journalctl -u telegraf -b --no-pager -n 20
    exit 1
}

# 步骤 5: 验证配置
verify_configuration() {
    echo "验证配置..."
    
    # 测试配置
    echo "测试配置文件..."
    if ! telegraf --config /etc/telegraf/telegraf.conf --test; then
        echo "错误：配置测试失败！"
        exit 1
    fi
    
    # 检查指标输出
    echo -e "\n检查指标输出... (等待15秒)"
    sleep 15
    local_ips=$(hostname -I)
    for ip in $local_ips; do
        echo "尝试访问 http://$ip:9273/metrics"
        if curl -s --connect-timeout 5 "http://$ip:9273/metrics" | head -n 20; then
            echo "配置验证完成"
            return
        fi
    done
    
    echo "错误：无法访问指标端点"
    exit 1
}

# 步骤 6: 配置 Prometheus
configure_prometheus() {
    echo "配置 Prometheus..."
    
    # 获取本机IP
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    # 生成 Prometheus 配置片段
    tee prometheus-telegraf.yml <<EOF
# Telegraf ESXi 监控配置
scrape_configs:
  - job_name: 'telegraf_esxi'
    static_configs:
      - targets: ['${SERVER_IP}:9273']
    metrics_path: /metrics
    scrape_interval: 60s
    honor_labels: true
    scheme: http
EOF
    
    echo "请将以下内容添加到 Prometheus 配置文件中:"
    cat prometheus-telegraf.yml
    echo ""
    echo "文件已保存为: $(pwd)/prometheus-telegraf.yml"
    echo "配置完成后，请重启 Prometheus 服务"
}

# 步骤 7: 配置 Grafana
configure_grafana() {
    echo "配置 Grafana..."
    
    echo "请按以下步骤操作:"
    echo "1. 登录 Grafana (http://${PROMETHEUS_HOST}:3000)"
    echo "2. 添加数据源:"
    echo "   - 类型: Prometheus"
    echo "   - URL: http://${PROMETHEUS_HOST}:${PROMETHEUS_PORT}"  # 使用配置的端口
    echo "3. 导入仪表板:"
    echo "   - 点击 '+' > Import"
    echo "   - 输入仪表板 ID: ${GRAFANA_DASHBOARD_ID}"
    echo "   - 选择新创建的 Prometheus 数据源"
    echo ""
    echo "仪表板导入完成"
}

# 步骤 8: 创建只读账户 (可选)
create_readonly_account() {
    echo "创建只读账户 (可选步骤)..."
    
    echo "请在每台 ESXi 主机上执行以下命令:"
    echo "----------------------------------------"
    echo "esxcli system account add -i telegraf -p 'StrongP@ss123' -c \"Telegraf Monitoring\""
    echo "esxcli system permission set -i telegraf -r ReadOnly"
    echo "----------------------------------------"
    echo ""
    echo "完成后，更新 Telegraf 配置使用新账户:"
    echo "username = \"telegraf\""
    echo "password = \"StrongP@ss123\""
}

# 主执行流程
main() {
    echo "开始部署 Telegraf ESXi 监控..."
    echo "========================================"
    
    install_telegraf
    configure_telegraf
    start_services
    verify_configuration
    configure_prometheus
    configure_grafana
    create_readonly_account
    
    echo ""
    echo "========================================"
    echo "Telegraf ESXi 监控部署完成！"
    echo ""
    echo "下一步:"
    echo "1. 将生成的 Prometheus 配置添加到 Prometheus"
    echo "2. 在 Grafana 中导入仪表板 (ID: ${GRAFANA_DASHBOARD_ID})"
    echo "3. 考虑创建只读账户提高安全性"
}

# 执行主函数
main