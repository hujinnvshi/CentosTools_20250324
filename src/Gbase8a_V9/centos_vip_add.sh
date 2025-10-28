#!/bin/bash
# CentOS 7 Virtual IP Auto-Configuration Script
# Author: Linux运维专家
# Version: 1.1
# Usage: ./vip_config.sh [CONFIG_FILE]

# 默认配置文件路径
DEFAULT_CONFIG="./virtual-ips.conf"

# 加载配置文件
load_config() {
    local config_file=${1:-$DEFAULT_CONFIG}
    
    if [ ! -f "$config_file" ]; then
        echo "错误: 配置文件 $config_file 不存在" >&2
        exit 1
    fi
    
    # 安全加载配置文件
    if ! source "$config_file"; then
        echo "错误: 加载配置文件失败" >&2
        exit 1
    fi
    
    # 验证必要参数
    if [ -z "$MAIN_INTERFACE" ] || [ ${#VIRTUAL_IPS[@]} -eq 0 ]; then
        echo "错误: 配置文件中缺少 MAIN_INTERFACE 或 VIRTUAL_IPS" >&2
        exit 1
    fi
    
    # 设置默认子网掩码
    NETMASK=${NETMASK:-"255.255.255.0"}
}

# 备份现有配置
backup_configs() {
    local config_dir="/etc/sysconfig/network-scripts"
    local backup_dir="/tmp/network-scripts-backup-$(date +%Y%m%d%H%M%S)"
    
    echo "创建配置备份: $backup_dir"
    mkdir -p "$backup_dir" && cp -a "$config_dir"/* "$backup_dir"/ || {
        echo "警告: 配置备份失败" >&2
        return 1
    }
}

# 创建虚拟接口配置文件
create_vip_configs() {
    local interface="$1"
    shift
    local vips=("$@")
    local config_dir="/etc/sysconfig/network-scripts"
    local main_config="${config_dir}/ifcfg-${interface}"
    
    if [ ! -f "$main_config" ]; then
        echo "错误: 主接口配置文件 $main_config 不存在" >&2
        return 1
    fi
    
    # 创建虚拟IP配置文件
    local index=0
    for vip in "${vips[@]}"; do
        # 检查IP格式
        if ! [[ $vip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "警告: 跳过无效IP地址: $vip" >&2
            continue
        fi
        
        local vip_config="${config_dir}/ifcfg-${interface}:${index}"
        
        # 检查配置文件是否已存在
        if [ -f "$vip_config" ]; then
            echo "警告: 配置文件 $vip_config 已存在，跳过创建" >&2
            ((index++))
            continue
        fi
        
        # 复制主接口配置
        if ! cp -p "$main_config" "$vip_config"; then
            echo "错误: 无法创建配置文件 $vip_config" >&2
            return 1
        fi
        
        # 修改虚拟接口配置
        sed -i -e "/^UUID/d" \
               -e "/^HWADDR/d" \
               -e "/^MACADDR/d" \
               -e "s/^DEVICE=.*/DEVICE=${interface}:${index}/" \
               -e "s/^NAME=.*/NAME=\"${interface}-virtual-${index}\"/" \
               -e "s/^BOOTPROTO=.*/BOOTPROTO=static/" \
               -e "/^IPADDR/d" \
               -e "/^NETMASK/d" \
               -e "/^PREFIX/d" \
               "$vip_config"
        
        # 添加虚拟IP配置
        echo "IPADDR=$vip" >> "$vip_config"
        echo "NETMASK=$NETMASK" >> "$vip_config"
        
        echo "已创建虚拟IP配置: $vip_config (IP: $vip)"
        ((index++))
    done
}

# 重启网络服务
restart_network() {
    echo "正在重启网络服务..."
    if ! systemctl restart network.service; then
        echo "错误: 网络服务重启失败" >&2
        return 1
    fi
    echo "网络服务重启成功"
}

# 验证配置
verify_configuration() {
    local interface="$1"
    shift
    local vips=("$@")
    local success=0
    
    echo -e "\n[验证] 检查接口配置:"
    if ! ip addr show "$interface"; then
        echo "错误: 无法获取接口 $interface 信息" >&2
        return 1
    fi
    
    echo -e "\n[验证] 虚拟IP列表:"
    for vip in "${vips[@]}"; do
        if ip addr show "$interface" | grep -q "inet $vip/"; then
            echo "成功: $vip 已配置"
        else
            echo "错误: $vip 未配置" >&2
            success=1
        fi
    done
    
    echo -e "\n[验证] 测试连通性:"
    for vip in "${vips[@]}"; do
        if ping -c 2 -W 1 "$vip" >/dev/null 2>&1; then
            echo "成功: $vip 可达"
        else
            echo "警告: $vip 不可达，请检查网络配置" >&2
            success=1
        fi
    done
    
    return $success
}

# 回滚配置
rollback_configs() {
    local backup_dir="$1"
    local config_dir="/etc/sysconfig/network-scripts"
    
    echo "正在回滚配置..."
    cp -a "$backup_dir"/* "$config_dir"/ && \
    systemctl restart network.service && \
    echo "配置已回滚到之前状态"
}

# 主函数
main() {
    local config_file="$1"
    local backup_dir
    
    # 加载配置
    load_config "$config_file"
    
    # 创建备份
    backup_dir=$(mktemp -d /tmp/network-backup-XXXXXX)
    if ! backup_configs "$backup_dir"; then
        echo "警告: 备份失败，继续执行..." >&2
    fi
    
    # 创建虚拟IP配置
    if ! create_vip_configs "$MAIN_INTERFACE" "${VIRTUAL_IPS[@]}"; then
        echo "错误: 创建虚拟IP配置失败" >&2
        rollback_configs "$backup_dir" || true
        exit 1
    fi
    
    # 重启网络服务
    if ! restart_network; then
        echo "错误: 网络服务重启失败" >&2
        rollback_configs "$backup_dir" || true
        exit 1
    fi
    
    # 验证配置
    if ! verify_configuration "$MAIN_INTERFACE" "${VIRTUAL_IPS[@]}"; then
        echo "警告: 配置验证失败" >&2
        # 不自动回滚，让管理员决定
    fi
    
    echo -e "\n虚拟IP配置完成!"
}

# 执行主函数
main "$@"