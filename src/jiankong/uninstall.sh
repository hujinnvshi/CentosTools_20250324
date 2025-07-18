#!/bin/bash
# Prometheus 卸载脚本（自定义路径）

# 停止服务
systemctl stop prometheus node_exporter grafana-server

# 禁用服务
systemctl disable prometheus node_exporter grafana-server

# 删除服务文件
rm -f /etc/systemd/system/prometheus.service
rm -f /etc/systemd/system/node_exporter.service

# 删除二进制文件
rm -f /usr/local/bin/prometheus
rm -f /usr/local/bin/promtool
rm -f /usr/local/bin/node_exporter

# 删除配置文件和数据
rm -rf /data/prometheus

# 删除管理脚本
rm -f /usr/local/bin/prometheus-manage

# 删除 Grafana
yum remove -y grafana
rm -rf /etc/grafana
rm -rf /var/lib/grafana

# 删除用户
userdel prometheus 2>/dev/null

# 清理防火墙
firewall-cmd --permanent --remove-port=9090/tcp
firewall-cmd --permanent --remove-port=9100/tcp
firewall-cmd --permanent --remove-port=3000/tcp
firewall-cmd --reload

# 删除日志轮转配置
rm -f /etc/logrotate.d/prometheus

echo "Prometheus 已完全卸载"