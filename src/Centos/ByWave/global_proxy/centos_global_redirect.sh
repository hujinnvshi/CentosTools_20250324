#!/bin/bash
# iptables + ipset 智能分流一键部署脚本 (优化版)
# 版本: 2.0
# 作者: 网络性能专家
# 最后更新: 2023-10-15

# 配置参数
PROXY_PORT=1080        # 本地代理端口
PROXY_IP="127.0.0.1"   # 本地代理IP
CHINA_IPS_URL="https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt"
DNS_SERVERS="223.5.5.5,114.114.114.114"  # 国内DNS
LOG_FILE="/var/log/iptables-split.log"
BACKUP_DIR="/etc/iptables/backup"
CACHE_DIR="/var/cache/iptables-split"
CHINA_IPS_FILE="${CACHE_DIR}/china_ip_list.txt"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # 无颜色

# 日志函数
log() {
    local level=$1
    local message=$2
    local color=$3
    
    case $level in
        error) echo -e "${RED}[ERROR] $message${NC}" >&2 ;;
        warn) echo -e "${YELLOW}[WARN] $message${NC}" ;;
        info) echo -e "${color:-$BLUE}[INFO] $message${NC}" ;;
        success) echo -e "${GREEN}[SUCCESS] $message${NC}" ;;
        *) echo -e "[$level] $message" ;;
    esac
    
    # 记录到日志文件
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
}

# 检查root权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        log error "此脚本必须以root权限运行"
        exit 1
    fi
}

# 初始化环境
init_environment() {
    log info "初始化环境..."
    
    # 创建必要的目录
    mkdir -p "$BACKUP_DIR" "$CACHE_DIR"
    
    # 创建日志文件
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    log success "环境初始化完成"
}

# 安装必要工具
install_dependencies() {
    log info "安装必要工具..."
    
    # 检查是否已安装
    local missing=()
    command -v ipset &>/dev/null || missing+=("ipset")
    command -v iptables &>/dev/null || missing+=("iptables")
    command -v curl &>/dev/null || missing+=("curl")
    
    if [ ${#missing[@]} -eq 0 ]; then
        log info "所有依赖已安装"
        return 0
    fi
    
    # 更新包列表
    apt-get update >/dev/null 2>&1
    
    # 安装缺失的包
    for pkg in "${missing[@]}"; do
        log info "安装 $pkg..."
        apt-get install -y "$pkg" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            log error "安装 $pkg 失败"
            return 1
        fi
    done
    
    log success "工具安装完成"
    return 0
}

# 备份当前配置
backup_config() {
    log info "备份当前配置..."
    
    # 备份iptables规则
    iptables-save > "$BACKUP_DIR/iptables.rules.bak" 2>/dev/null
    ip6tables-save > "$BACKUP_DIR/ip6tables.rules.bak" 2>/dev/null
    
    # 备份DNS配置
    cp /etc/resolv.conf "$BACKUP_DIR/resolv.conf.bak"
    
    log success "配置备份完成 (保存在 $BACKUP_DIR)"
}

# 创建ipset集合
create_ipset() {
    log info "创建ipset集合..."
    
    # 检查是否已存在
    if ipset list china &>/dev/null; then
        log warn "已存在 'china' ipset集合，将刷新内容"
        ipset flush china
    else
        ipset create china hash:net hashsize 4096 maxelem 1000000 2>/dev/null
    fi
    
    # 下载中国IP列表
    log info "下载中国IP列表..."
    curl -sL "$CHINA_IPS_URL" -o "$CHINA_IPS_FILE"
    if [ $? -ne 0 ] || [ ! -s "$CHINA_IPS_FILE" ]; then
        log error "下载中国IP列表失败"
        return 1
    fi
    
    # 添加IP到集合
    log info "添加IP到集合..."
    local count=0
    while read -r ip; do
        [[ -z "$ip" || "$ip" =~ ^# ]] && continue
        ipset add china "$ip" &>/dev/null
        ((count++))
    done < "$CHINA_IPS_FILE"
    
    log success "已添加 $count 个中国IP到集合"
    return 0
}

# 配置iptables规则
configure_iptables() {
    log info "配置iptables规则..."
    
    # 清除现有规则
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    
    # 创建自定义链
    iptables -t nat -N SHADOWSOCKS 2>/dev/null
    
    # 跳过本地地址
    local private_nets=(
        "0.0.0.0/8" "10.0.0.0/8" "127.0.0.0/8" "169.254.0.0/16"
        "172.16.0.0/12" "192.168.0.0/16" "224.0.0.0/4" "240.0.0.0/4"
    )
    
    for net in "${private_nets[@]}"; do
        iptables -t nat -A SHADOWSOCKS -d "$net" -j RETURN
    done
    
    # 跳过中国IP
    iptables -t nat -A SHADOWSOCKS -m set --match-set china dst -j RETURN
    
    # 重定向其他流量到代理
    iptables -t nat -A SHADOWSOCKS -p tcp -j REDIRECT --to-ports "$PROXY_PORT"
    
    # 应用规则
    iptables -t nat -A OUTPUT -p tcp -j SHADOWSOCKS
    iptables -t nat -A PREROUTING -p tcp -j SHADOWSOCKS
    
    # 添加日志规则
    iptables -t nat -I SHADOWSOCKS 1 -p tcp -m limit --limit 1/sec -j LOG --log-prefix "SS-REDIRECT: " --log-level 4
    
    log success "iptables规则配置完成"
    return 0
}

# 配置DNS分流
configure_dns() {
    log info "配置DNS分流..."
    
    # 检查systemd-resolved
    if ! systemctl is-active systemd-resolved &>/dev/null; then
        log warn "systemd-resolved未运行，跳过DNS分流配置"
        return 0
    fi
    
    # 备份原配置
    mkdir -p /etc/systemd/resolved.conf.d
    if [ -f /etc/systemd/resolved.conf.d/split-dns.conf ]; then
        cp /etc/systemd/resolved.conf.d/split-dns.conf "$BACKUP_DIR/split-dns.conf.bak"
    fi
    
    # 创建新配置
    cat > /etc/systemd/resolved.conf.d/split-dns.conf <<EOF
[Resolve]
DNS=$DNS_SERVERS
Domains=~.
EOF
    
    # 重启服务
    systemctl restart systemd-resolved
    
    # 更新resolv.conf
    if grep -q "127.0.0.53" /etc/resolv.conf; then
        log info "resolv.conf已指向127.0.0.53"
    else
        log info "更新resolv.conf..."
        echo "nameserver 127.0.0.53" > /etc/resolv.conf
        echo "options edns0 trust-ad" >> /etc/resolv.conf
    fi
    
    log success "DNS分流配置完成"
    return 0
}

# 配置持久化
configure_persistence() {
    log info "配置持久化..."
    
    # 保存ipset
    mkdir -p /etc/iptables
    ipset save china > /etc/iptables/china.ipset
    
    # 保存iptables
    iptables-save > /etc/iptables/rules.v4
    
    # 创建systemd服务
    cat > /etc/systemd/system/ipset-split.service <<EOF
[Unit]
Description=Load China IP Set
Before=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/ipset restore -f /etc/iptables/china.ipset
ExecStop=/sbin/ipset flush china

[Install]
WantedBy=multi-user.target
EOF
    
    # 启用服务
    systemctl daemon-reload
    systemctl enable ipset-split >/dev/null 2>&1
    systemctl start ipset-split
    
    # 配置logrotate
    cat > /etc/logrotate.d/iptables-split <<EOF
$LOG_FILE {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF
    
    log success "持久化配置完成"
}

# 测试分流效果
test_split() {
    log info "测试分流效果..."
    
    local success=true
    
    # 测试国内网站
    echo -n "测试国内网站 (baidu.com): "
    if curl -s --max-time 3 http://www.baidu.com >/dev/null; then
        echo -e "${GREEN}成功 (直连)${NC}"
    else
        echo -e "${RED}失败${NC}"
        success=false
    fi
    
    # 测试国外网站
    echo -n "测试国外网站 (google.com): "
    if curl -s --max-time 5 https://www.google.com >/dev/null; then
        echo -e "${GREEN}成功 (代理)${NC}"
    else
        echo -e "${RED}失败${NC}"
        success=false
    fi
    
    # 测试DNS
    echo -n "测试DNS解析 (baidu.com): "
    if dig +short www.baidu.com | grep -q '^[0-9]'; then
        echo -e "${GREEN}成功 (国内DNS)${NC}"
    else
        echo -e "${RED}失败${NC}"
        success=false
    fi
    
    # 测试IP分流
    echo -n "测试IP分流 (中国IP): "
    if curl -s --max-time 3 http://cip.cc >/dev/null; then
        echo -e "${GREEN}成功 (直连)${NC}"
    else
        echo -e "${RED}失败${NC}"
        success=false
    fi
    
    if $success; then
        log success "所有测试通过"
    else
        log warn "部分测试失败，请检查配置"
    fi
}

# 清理和恢复
cleanup() {
    log info "清理临时资源..."
    
    # 停止服务
    systemctl stop ipset-split 2>/dev/null
    
    # 删除服务
    rm -f /etc/systemd/system/ipset-split.service
    systemctl daemon-reload
    
    # 删除日志配置
    rm -f /etc/logrotate.d/iptables-split
    
    log success "清理完成"
}

# 主函数
main() {
    echo -e "\n${BLUE}======================================${NC}"
    echo -e "${BLUE} iptables + ipset 智能分流一键部署脚本 ${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo "开始时间: $(date)"
    
    # 执行部署步骤
    check_root
    init_environment
    install_dependencies || exit 1
    backup_config
    create_ipset || exit 1
    configure_iptables || exit 1
    configure_dns
    configure_persistence
    
    echo ""
    test_split
    
    echo ""
    log success "✅ 部署完成!"
    echo "代理设置:"
    echo "  - 代理地址: $PROXY_IP:$PROXY_PORT"
    echo "  - 中国IP数量: $(ipset list china | grep -c '^[0-9]')"
    echo "  - 日志文件: $LOG_FILE"
    echo "  - 备份目录: $BACKUP_DIR"
    echo ""
    echo "重启后规则将自动恢复"
    echo -e "${BLUE}======================================${NC}"
}

# 执行主函数
trap cleanup EXIT
main