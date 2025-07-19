#!/bin/bash
# Prometheus 监控系统卸载脚本
# 用于完全清理 Prometheus、Node Exporter 和 Grafana 服务
# 版本：2023.10

# 颜色定义
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
NC="\033[0m" # No Color

# 打印彩色消息
print_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# 确认卸载
echo -e "${YELLOW}警告: 此脚本将完全卸载 Prometheus 监控系统，包括所有数据和配置。${NC}"
echo -e "${YELLOW}此操作不可逆，请确保已备份所有重要数据。${NC}"
read -p "是否继续卸载? (y/n): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  print_info "卸载已取消"
  exit 0
fi

# 定义路径变量（与安装脚本保持一致）
BASE_DIR="/data/prometheus"
CONFIG_DIR="${BASE_DIR}/config"
DATA_DIR="${BASE_DIR}/data"
LOG_DIR="${BASE_DIR}/logs"

# 停止服务
print_info "停止 Prometheus、Node Exporter 和 Grafana 服务..."
services=("prometheus" "node_exporter" "grafana-server")
for service in "${services[@]}"; do
  if systemctl is-active "$service" &>/dev/null; then
    print_info "停止 $service 服务..."
    systemctl stop "$service"
    if systemctl is-active "$service" &>/dev/null; then
      print_error "$service 服务停止失败"
    else
      print_info "$service 服务已停止"
    fi
  else
    print_warn "$service 服务未运行"
  fi
done

# 禁用服务
print_info "禁用服务..."
for service in "${services[@]}"; do
  if systemctl is-enabled "$service" &>/dev/null; then
    print_info "禁用 $service 服务..."
    systemctl disable "$service"
    print_info "$service 服务已禁用"
  else
    print_warn "$service 服务未启用"
  fi
done

# 删除服务文件
print_info "删除服务文件..."
service_files=(
  "/etc/systemd/system/prometheus.service"
  "/etc/systemd/system/node_exporter.service"
  "/usr/lib/systemd/system/grafana-server.service"
)

for file in "${service_files[@]}"; do
  if [ -f "$file" ]; then
    print_info "删除 $file..."
    rm -f "$file"
  else
    print_warn "文件不存在: $file"
  fi
done

# 重新加载 systemd
systemctl daemon-reload
print_info "systemd 配置已重新加载"

# 删除二进制文件
print_info "删除二进制文件..."
binaries=(
  "/usr/local/bin/prometheus"
  "/usr/local/bin/promtool"
  "/usr/local/bin/node_exporter"
)

for binary in "${binaries[@]}"; do
  if [ -f "$binary" ]; then
    print_info "删除 $binary..."
    rm -f "$binary"
  else
    print_warn "文件不存在: $binary"
  fi
done

# 删除管理脚本
print_info "删除管理脚本..."
if [ -f "/usr/local/bin/prometheus-manage" ]; then
  rm -f "/usr/local/bin/prometheus-manage"
  print_info "管理脚本已删除"
else
  print_warn "管理脚本不存在"
fi

# 删除 Grafana
print_info "卸载 Grafana..."
if rpm -q grafana &>/dev/null; then
  print_info "卸载 Grafana 软件包..."
  yum remove -y grafana
  print_info "Grafana 软件包已卸载"
else
  print_warn "Grafana 软件包未安装"
fi

# 删除 Grafana 配置和数据
print_info "删除 Grafana 配置和数据..."
grafana_dirs=(
  "/etc/grafana"
  "/var/lib/grafana"
  "/var/log/grafana"
)

for dir in "${grafana_dirs[@]}"; do
  if [ -d "$dir" ]; then
    print_info "删除 $dir..."
    rm -rf "$dir"
  else
    print_warn "目录不存在: $dir"
  fi
done

# 删除 Prometheus 配置文件和数据
print_info "删除 Prometheus 配置文件和数据..."
if [ -d "$BASE_DIR" ]; then
  print_info "删除 $BASE_DIR..."
  rm -rf "$BASE_DIR"
  print_info "Prometheus 数据目录已删除"
else
  print_warn "Prometheus 数据目录不存在: $BASE_DIR"
fi

# 删除 Prometheus 用户
print_info "删除 Prometheus 用户..."
if id prometheus &>/dev/null; then
  userdel prometheus
  print_info "Prometheus 用户已删除"
else
  print_warn "Prometheus 用户不存在"
fi

# 清理防火墙规则
print_info "清理防火墙规则..."
if command -v firewall-cmd &>/dev/null; then
  if firewall-cmd --state &>/dev/null; then
    print_info "移除防火墙规则..."
    # 使用 9091 端口（安装脚本中使用的端口）
    firewall-cmd --permanent --remove-port=9091/tcp &>/dev/null || print_warn "移除 9091 端口失败"
    firewall-cmd --permanent --remove-port=9100/tcp &>/dev/null || print_warn "移除 9100 端口失败"
    firewall-cmd --permanent --remove-port=3000/tcp &>/dev/null || print_warn "移除 3000 端口失败"
    firewall-cmd --reload &>/dev/null
    print_info "防火墙规则已更新"
  else
    print_warn "防火墙服务未运行"
  fi
else
  print_warn "未找到 firewall-cmd 命令，跳过防火墙配置"
fi

# 删除日志轮转配置
print_info "删除日志轮转配置..."
if [ -f "/etc/logrotate.d/prometheus" ]; then
  rm -f "/etc/logrotate.d/prometheus"
  print_info "日志轮转配置已删除"
else
  print_warn "日志轮转配置不存在"
fi

# 删除 Grafana 源配置
print_info "删除 Grafana 源配置..."
if [ -f "/etc/yum.repos.d/grafana.repo" ]; then
  rm -f "/etc/yum.repos.d/grafana.repo"
  print_info "Grafana 源配置已删除"
else
  print_warn "Grafana 源配置不存在"
fi

# 清理完成
echo ""
echo -e "${GREEN}========================================================${NC}"
echo -e "${GREEN}Prometheus 监控系统已完全卸载！${NC}"
echo -e "${GREEN}所有服务、配置文件和数据已被删除。${NC}"
echo -e "${GREEN}========================================================${NC}"