#!/usr/bin/env bash

# 清理脚本配置（与安装脚本一致）
HTTPD_USER="apache"
DOCUMENT_ROOT="/var/www/html"
SCRIPT_PATH="/usr/local/bin/centos_httpd_path_update.sh.sh"

# 增强型输出函数
log() { echo -e "\033[1;32m[INFO]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; }
success() { echo -e "\033[1;36m[SUCCESS]\033[0m $1"; }

# 检查root权限
check_root() {
    [[ $EUID -eq 0 ]] || error "脚本需要以root权限运行"
    return 0
}

# 停止并卸载HTTPD服务
uninstall_httpd() {
    log "停止并卸载HTTPD服务..."
    
    # 停止服务
    if systemctl is-active httpd >/dev/null; then
        systemctl stop httpd
        systemctl disable httpd
        success "HTTPD服务已停止并禁用"
    else
        warn "HTTPD服务未运行"
    fi
    
    # 尝试检测包管理器
    if command -v dnf >/dev/null 2>&1; then
        PM="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PM="yum"
    else
        error "不支持的包管理器，仅支持yum/dnf"
        return 1
    fi

    # 卸载软件包
    $PM remove -y httpd httpd-tools tree apr apr-util apr-devel apr-util-devel \
        && success "HTTPD及相关组件已卸载" || warn "部分组件卸载失败"
    
    # 清理配置文件
    if [ -d "/etc/httpd" ]; then
        rm -rf /etc/httpd
        log "已删除HTTPD配置文件"
    fi
    
    return 0
}

# 移除目录树脚本
remove_tree_script() {
    log "移除目录树生成脚本..."
    
    if [ -f "$SCRIPT_PATH" ]; then
        rm -f "$SCRIPT_PATH"
        success "已删除脚本: $SCRIPT_PATH"
    else
        warn "目录树脚本不存在: $SCRIPT_PATH"
    fi
    
    return 0
}

# 移除定时任务
remove_cron_job() {
    log "移除定时任务..."    
    if crontab -l | grep -q "centos_httpd_path_update.sh.sh"; then
        crontab -l | grep -v "centos_httpd_path_update.sh.sh" | crontab -
        success "定时任务已移除"
    else
        warn "未找到相关定时任务"
    fi    
    return 0
}

# 恢复安全设置
restore_security() {
    log "恢复安全设置..."    
    # SELinux恢复
    if sestatus >/dev/null 2>&1; then
        if sestatus | grep -q "enabled"; then
            setsebool -P httpd_read_user_content 0
            setsebool -P httpd_can_network_connect 0
            log "SELinux策略已恢复"
        fi
    fi    
    # 防火墙恢复
    if systemctl is-active firewalld >/dev/null; then
        firewall-cmd --permanent --remove-service=http
        firewall-cmd --permanent --remove-service=https
        firewall-cmd --reload
        success "防火墙HTTP(S)规则已移除"
    fi    
    return 0
}

# 清理文档根目录
clean_document_root() {
    log "清理文档根目录..."
    
    if [ -d "$DOCUMENT_ROOT" ]; then
        # 仅删除脚本生成的文件，保留其他内容
        if [ -f "$DOCUMENT_ROOT/index.html" ]; then
            rm -f "$DOCUMENT_ROOT/index.html"
            log "已删除index.html"
        fi
        
        # 检查目录是否为空
        if [ -z "$(ls -A $DOCUMENT_ROOT)" ]; then
            warn "文档根目录为空，是否删除? [y/N]"
            read -r response
            if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                rm -rf "$DOCUMENT_ROOT"
                success "文档根目录已删除"
            else
                log "保留空文档根目录"
            fi
        else
            log "文档根目录包含其他文件，已保留"
        fi
    else
        warn "文档根目录不存在: $DOCUMENT_ROOT"
    fi
    
    return 0
}

# 清理日志文件
clean_logs() {
    log "清理相关日志文件..."
    
    # HTTPD日志
    if [ -d "/var/log/httpd" ]; then
        rm -f /var/log/httpd/*
        log "已清空HTTPD日志"
    fi
    
    # Cron日志
    if [ -f "/var/log/cron" ]; then
        sed -i '/centos_httpd_path_update.sh.sh/d' /var/log/cron
        log "已清理Cron日志"
    fi
    
    return 0
}

# 验证清理结果
verify_cleanup() {
    log "验证清理结果..."
    
    local errors=0
    
    # 检查HTTPD服务
    if systemctl is-active httpd >/dev/null; then
        error "HTTPD服务仍在运行"
        errors=$((errors+1))
    fi
    
    # 检查脚本文件
    if [ -f "$SCRIPT_PATH" ]; then
        error "脚本文件仍存在: $SCRIPT_PATH"
        errors=$((errors+1))
    fi
    
    # 检查定时任务
    if crontab -l | grep -q "centos_httpd_path_update.sh.sh"; then
        error "定时任务仍存在"
        errors=$((errors+1))
    fi
    
    # 检查index.html
    if [ -f "$DOCUMENT_ROOT/index.html" ]; then
        error "index.html文件仍存在"
        errors=$((errors+1))
    fi
    
    if [ $errors -eq 0 ]; then
        success "所有组件已成功清理"
    else
        warn "发现 $errors 个清理问题"
    fi
    
    return $errors
}

# 主清理函数
cleanup() {
    echo -e "\n\033[1;35m===== HTTPD目录树服务器清理脚本 =====\033[0m\n"
    
    check_root || return 1
    
    uninstall_httpd
    remove_tree_script
    remove_cron_job
    restore_security
    clean_document_root
    clean_logs    
    verify_cleanup    
    echo -e "\n\033[1;33m清理完成！系统已恢复到安装前的状态\033[0m"
    return 0
}

# 确保从主函数执行
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cleanup "$@"
    exit $?
fi