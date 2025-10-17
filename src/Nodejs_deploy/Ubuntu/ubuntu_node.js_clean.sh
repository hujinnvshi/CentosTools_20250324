#!/bin/bash

# =============================================
# Node.js 生产环境一键清理脚本 (Root专用)
# 版本：1.0
# 功能：完全移除Node.js生产环境
# =============================================

# 检查是否以root运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本必须使用root权限运行！"
    exit 1
fi

# 全局配置（与安装脚本一致）
NODE_USER="nodeapp"  # 专用运行用户
APP_DIR="/opt/nodeapp"  # 应用目录
NVM_DIR="/usr/local/nvm"  # 系统级nvm目录
PNPM_HOME="/usr/local/pnpm"  # 系统级pnpm目录

echo "============================================="
echo "开始清理 Node.js 生产环境 - $(date)"
echo "============================================="

# 函数：停止并移除服务
clean_services() {
    echo -e "\n\033[34m[1/5] 正在停止并移除服务...\033[0m"
    
    if systemctl is-active --quiet pm2; then
        echo "▶ 停止PM2服务..."
        systemctl stop pm2
    fi
    
    if systemctl is-enabled --quiet pm2; then
        echo "▶ 禁用PM2服务..."
        systemctl disable pm2
    fi
    
    echo "▶ 移除服务文件..."
    rm -f /etc/systemd/system/pm2.service
    systemctl daemon-reload
    systemctl reset-failed
    
    echo "✓ 服务清理完成"
}

# 函数：移除用户和目录
clean_directories() {
    echo -e "\n\033[34m[2/5] 正在移除用户和目录...\033[0m"
    
    echo "▶ 移除应用目录: $APP_DIR..."
    rm -rf "$APP_DIR"
    
    echo "▶ 移除NVM目录: $NVM_DIR..."
    rm -rf "$NVM_DIR"
    
    echo "▶ 移除PNPM目录: $PNPM_HOME..."
    rm -rf "$PNPM_HOME"
    
    echo "▶ 删除专用用户: $NODE_USER..."
    if id "$NODE_USER" &>/dev/null; then
        userdel -r "$NODE_USER" 2>/dev/null || {
            echo "⚠ 警告：用户删除失败，可能存在关联进程"
            echo "▶ 强制终止用户进程..."
            pkill -u "$NODE_USER" || true
            userdel -r "$NODE_USER" || true
        }
    fi
    
    echo "✓ 目录和用户清理完成"
}

# 函数：移除环境配置
clean_environment() {
    echo -e "\n\033[34m[3/5] 正在移除环境配置...\033[0m"
    
    echo "▶ 移除环境变量文件..."
    rm -f /etc/profile.d/nvm.sh
    rm -f /etc/profile.d/pnpm.sh
    
    echo "▶ 移除系统链接..."
    rm -f /usr/local/bin/node
    rm -f /usr/local/bin/npm
    rm -f /usr/local/bin/pnpm
    rm -f /usr/local/bin/pnpx
    
    echo "▶ 清理系统优化配置..."
    sed -i '/fs.inotify.max_user_watches/d' /etc/sysctl.conf
    sed -i '/NODE_OPTIONS/d' /etc/profile
    
    echo "✓ 环境配置清理完成"
}

# 函数：清理依赖和缓存
clean_dependencies() {
    echo -e "\n\033[34m[4/5] 正在清理依赖和缓存...\033[0m"
    
    echo "▶ 清理npm缓存..."
    npm cache clean --force >/dev/null 2>&1 || true
    
    echo "▶ 清理pnpm缓存..."
    pnpm store prune >/dev/null 2>&1 || true
    
    echo "▶ 移除全局npm包..."
    for package in $(npm ls -g --parseable --depth=0 | awk -F/ '{print $NF}'); do
        [ "$package" != "npm" ] && npm uninstall -g "$package" >/dev/null 2>&1
    done
    
    echo "✓ 依赖和缓存清理完成"
}

# 函数：恢复防火墙设置
clean_firewall() {
    echo -e "\n\033[34m[5/5] 正在恢复防火墙设置...\033[0m"
    
    echo "▶ 移除防火墙规则..."
    ufw delete allow 80 >/dev/null 2>&1 || true
    ufw delete allow 443 >/dev/null 2>&1 || true
    
    echo "✓ 防火墙设置恢复完成"
}

# 主清理流程
main() {
    clean_services
    clean_directories
    clean_environment
    clean_dependencies
    clean_firewall
    
    echo "============================================="
    echo "Node.js 生产环境清理完成！"
    echo "============================================="
    echo -e "\033[32m[清理结果]\033[0m"
    echo "已移除:"
    echo "  - 用户: $NODE_USER"
    echo "  - 目录: $APP_DIR"
    echo "  - NVM: $NVM_DIR"
    echo "  - PNPM: $PNPM_HOME"
    echo "  - 系统服务: pm2"
    echo ""
    echo -e "\033[32m[注意事项]\033[0m"
    echo "1. 部分全局配置可能需要重新登录生效"
    echo "2. 如需完全清理，请手动检查以下位置:"
    echo "   - /root/.npm"
    echo "   - /root/.pm2"
    echo "   - /var/log/ 中的相关日志"
    echo "3. 运行 'source /etc/profile' 刷新环境"
    echo "============================================="
}

# 启动清理流程
main