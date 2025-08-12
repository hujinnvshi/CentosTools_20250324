#!/bin/bash
# Telegraf 完全清理脚本
# 适用于 CentOS 7.9
# 作者：卓越运维专家

# 配置参数（与安装脚本一致）
ESXI_HOSTS=("172.16.48.11" "172.16.48.12" "172.16.48.13" "172.16.48.14" "172.16.48.15" "172.16.48.17" "172.16.48.18")
ESXI_USER="root"
ESXI_PASSWORD="Secsmart\#612"
PROMETHEUS_HOST="172.16.47.185"
GRAFANA_DASHBOARD_ID="10826"

# 检查 root 权限
if [ "$(id -u)" != "0" ]; then
    echo "错误：此脚本必须以 root 权限运行"
    exit 1
fi

# 步骤 1: 停止并禁用服务
stop_services() {
    echo "停止并禁用 Telegraf 服务..."
    
    systemctl stop telegraf 2>/dev/null
    systemctl disable telegraf 2>/dev/null
    systemctl daemon-reload
    
    echo "服务已停止"
}

# 步骤 2: 卸载软件包
uninstall_telegraf() {
    echo "卸载 Telegraf..."
    
    yum remove -y telegraf 2>/dev/null
    yum autoremove -y 2>/dev/null
    
    echo "Telegraf 已卸载"
}

# 步骤 3: 删除配置文件和数据
remove_configs() {
    echo "删除配置文件和数据..."
    
    # 删除配置目录
    rm -rf /etc/telegraf
    rm -rf /var/lib/telegraf
    
    # 删除日志文件
    rm -f /var/log/telegraf/telegraf.log*
    
    # 删除仓库配置
    rm -f /etc/yum.repos.d/influxdata.repo
    
    # 删除生成的 Prometheus 配置片段
    rm -f prometheus-telegraf.yml
    
    echo "配置文件已清除"
}

# 步骤 4: 清理防火墙规则
clean_firewall() {
    echo "清理防火墙规则..."
    
    firewall-cmd --zone=public --remove-port=9273/tcp --permanent 2>/dev/null
    firewall-cmd --reload 2>/dev/null
    
    echo "防火墙规则已清除"
}

# 步骤 5: 删除系统用户
remove_user() {
    echo "删除系统用户..."
    
    # 检查并删除 telegraf 用户
    if id "telegraf" &>/dev/null; then
        userdel -r telegraf 2>/dev/null
        echo "telegraf 用户已删除"
    else
        echo "telegraf 用户不存在"
    fi
}

# 步骤 6: 清理残留文件
clean_residual_files() {
    echo "清理残留文件..."
    
    # 删除临时文件
    rm -f /tmp/telegraf*.rpm
    
    # 删除缓存文件
    rm -f /var/cache/yum/influxdata*
    
    # 删除日志目录
    rm -rf /var/log/telegraf
    
    echo "残留文件已清理"
}

# 步骤 7: 清理 ESXi 只读账户（可选）
clean_esxi_accounts() {
    echo "清理 ESXi 只读账户（可选）..."
    
    echo "请在每台 ESXi 主机上执行以下命令:"
    echo "----------------------------------------"
    echo "esxcli system account remove -i telegraf"
    echo "----------------------------------------"
    echo ""
    echo "完成后，只读账户将被删除"
}

# 步骤 8: 清理 Grafana 仪表板（可选）
clean_grafana_dashboard() {
    echo "清理 Grafana 仪表板（可选）..."
    
    echo "请按以下步骤操作:"
    echo "1. 登录 Grafana (http://${PROMETHEUS_HOST}:3000)"
    echo "2. 导航到仪表板管理"
    echo "3. 找到 ID 为 ${GRAFANA_DASHBOARD_ID} 的仪表板并删除"
    echo ""
    echo "完成后，仪表板将被删除"
}

# 主执行流程
main() {
    echo "开始清理 Telegraf 环境..."
    echo "========================================"
    
    stop_services
    uninstall_telegraf
    remove_configs
    clean_firewall
    remove_user
    clean_residual_files
    
    echo ""
    echo "基本清理完成！"
    echo ""
    echo "可选清理步骤:"
    echo "1. 在 ESXi 主机上删除只读账户"
    echo "2. 在 Grafana 中删除仪表板"
    echo ""
    echo "执行以下命令完成可选清理:"
    echo "  clean_esxi_accounts"
    echo "  clean_grafana_dashboard"
    
    echo ""
    echo "========================================"
    echo "Telegraf 环境清理完成！"
    echo "您现在可以重新运行安装脚本进行全新安装"
}

# 执行主函数
main