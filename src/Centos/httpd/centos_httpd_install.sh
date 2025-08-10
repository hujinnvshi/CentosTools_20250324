#!/usr/bin/env bash

# 增强型输出函数
log() { echo -e "\033[1;32m[INFO]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; exit 1; }
success() { echo -e "\033[1;36m[SUCCESS]\033[0m $1"; }

# 配置参数（可修改）
HTTPD_USER="apache"
DOCUMENT_ROOT="/var/www/html"
TREE_DEPTH=3
CRON_INTERVAL="*/5 * * * *" # 每5分钟更新一次

# 检查root权限
check_root() {
    [[ $EUID -eq 0 ]] || error "脚本需要以root权限运行"
}

# 检查命令是否存在
check_command() {
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || error "依赖命令缺失: $cmd"
    done
}

# 安装httpd和tree工具
# 安装httpd和tree工具
install_httpd() {
    log "安装httpd和相关依赖..."
    
    # 尝试检测包管理器
    if command -v dnf >/dev/null 2>&1; then
        PM="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PM="yum"
    else
        error "不支持的包管理器，仅支持yum/dnf"
    fi

    # 一次性安装所有依赖
    $PM install -y httpd httpd-tools tree \
        apr apr-util apr-devel apr-util-devel \
        && success "依赖安装成功" || error "依赖安装失败"
    
    # 验证核心组件
    check_command httpd tree
    
    # 创建文档根目录（如果不存在）并设置正确的权限
    mkdir -p "$DOCUMENT_ROOT" && chown "$HTTPD_USER:$HTTPD_USER" "$DOCUMENT_ROOT"
    chmod 755 "$DOCUMENT_ROOT"  # 添加可执行权限，允许Apache进入目录
    
    # 启动并启用服务
    systemctl start httpd
    systemctl enable httpd --now
    
    # 检查服务状态
    if ! systemctl is-active httpd >/dev/null; then
        journalctl -u httpd -n 20 --no-pager
        error "httpd服务启动失败"
    fi
    success "httpd服务已启动"
}

# 设置cron任务定期更新目录树
setup_cron() {
    log "配置定时更新任务..."
    
    # 创建cron任务
    local cron_job="$CRON_INTERVAL /root/centos_httpd_path_update.sh"
    
    if [[ $CRON_INTERVAL != "manual" ]]; then
        # 清除任何旧的相同任务
        (crontab -l 2>/dev/null | grep -v "centos_httpd_path_update.sh") | crontab -
        
        # 添加新任务
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        
        if crontab -l | grep -q "centos_httpd_path_update.sh"; then
            success "定时任务已设置: $(crontab -l | grep centos_httpd_path_update.sh)"
        else
            warn "定时任务创建失败，但将继续执行"
        fi
    fi

    # 立即执行一次
    log "执行首次目录树生成..."
    if /root/centos_httpd_path_update.sh; then
        success "目录树生成成功"
    else
        error "目录树生成失败"
    fi
    
    # 修正：确保index.html有正确权限
    if [[ -f "${DOCUMENT_ROOT}/index.html" ]]; then
        chown "$HTTPD_USER:$HTTPD_USER" "${DOCUMENT_ROOT}/index.html"
        chmod 644 "${DOCUMENT_ROOT}/index.html"
        log "已设置index.html权限: $(ls -l ${DOCUMENT_ROOT}/index.html)"
    fi
}

# 配置SELinux和防火墙
configure_security() {
    log "配置系统安全策略..."
    
    # SELinux配置
    if sestatus >/dev/null 2>&1; then
        if sestatus | grep -q "enabled"; then
            log "调整SELinux策略..."
            setsebool -P httpd_read_user_content 1
            setsebool -P httpd_can_network_connect 1
            restorecon -FRv "$DOCUMENT_ROOT"
            
            # 检查httpd运行时上下文
            if ! ps -eZ | grep -q 'system_u:system_r:httpd_t:s0'; then
                warn "httpd未在正确的SELinux上下文运行"
            fi
            
            # 重要：设置SELinux允许访问
            chcon -R -t httpd_sys_content_t "$DOCUMENT_ROOT"  # 修正：递归设置上下文
            log "已设置SELinux上下文: $(ls -lZ $DOCUMENT_ROOT)"
        else
            log "SELinux已禁用"
        fi
    else
        warn "未检测到SELinux"
    fi
    
    # 防火墙配置
    if systemctl is-active firewalld >/dev/null; then
        log "配置防火墙允许HTTP访问..."
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --reload
        success "防火墙已允许HTTP(S)访问"
    else
        warn "未检测到firewalld服务"
    fi
    
    # 额外权限检查
    local dir_perms=$(stat -c "%a" "$DOCUMENT_ROOT")
    local file_perms=$(stat -c "%a" "${DOCUMENT_ROOT}/index.html")
    [[ $dir_perms =~ ^[75] ]] || warn "文档根目录权限($dir_perms)可能过严"
    [[ $file_perms =~ ^[64] ]] || warn "index.html文件权限($file_perms)可能过严"
}

# 显示完成信息
show_completion() {
    log "验证httpd状态: $(systemctl is-active httpd)"
    log "验证开放端口: $(ss -tuln | grep ':80')"
    
    # 获取IPv4地址
    local ipv4_addr
    ipv4_addr=$(ip -o -4 addr show scope global | awk '{print $4}' | cut -d'/' -f1 | head -n1)
    
    success "部署完成！"
    echo "------------------------"
    echo "访问地址: http://${ipv4_addr}/"
    echo "文档根目录: $DOCUMENT_ROOT"
    echo "目录树脚本: /root/centos_httpd_path_update.sh"
    echo "定时任务: $(crontab -l | grep centos_httpd_path_update.sh)"
    echo "------------------------"
}

# 主函数
main() {
    clear
    echo -e "\n\033[1;35m===== HTTPD目录树服务器部署脚本 =====\033[0m\n"    
    check_root
    check_command date systemctl
    install_httpd
    setup_cron
    configure_security
    show_completion
}

# 确保从主函数执行
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi