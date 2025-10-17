#!/bin/bash

# =============================================
# Node.js 生产环境一键部署脚本 (Root专用优化版)
# 版本：4.0
# 更新：模块化设计、增强状态提示、完善进度反馈
# =============================================

# 检查是否以root运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本必须使用root权限运行！"
    exit 1
fi

# 全局配置
LOG_FILE="/var/log/nodejs_install_$(date +%Y%m%d_%H%M%S).log"
NODE_USER="nodeapp"  # 专用运行用户
APP_DIR="/opt/nodeapp"  # 应用目录
NVM_DIR="/usr/local/nvm"  # 系统级nvm目录
PNPM_HOME="/usr/local/pnpm"  # 系统级pnpm目录

exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================="
echo "开始部署 Node.js 生产环境 - $(date)"
echo "安装日志：$LOG_FILE"
echo "============================================="

# 函数定义区域
# --------------------------------------------------
# 函数：准备系统环境
prepare_system() {
    echo -e "\n\033[34m[1/7] 正在准备系统环境...\033[0m"
    echo "▶ 更新系统包列表..."
    apt update -y
    echo "▶ 升级系统组件..."
    apt upgrade -y
    echo "▶ 安装必要依赖..."
    apt install -y build-essential libssl-dev curl git python3 make gcc
    
    # 创建专用用户
    if ! id "$NODE_USER" &>/dev/null; then
        echo "▶ 创建专用用户: $NODE_USER..."
        useradd -r -m -d "$APP_DIR" -s /bin/bash "$NODE_USER"
        echo "✓ 用户创建成功"
    else
        echo "✓ 用户已存在: $NODE_USER"
    fi
    echo "✓ 系统环境准备完成"
}

# --------------------------------------------------
# 函数：安装nvm
install_nvm() {
    echo -e "\n\033[34m[2/7] 正在安装Node版本管理器(nvm)...\033[0m"
    echo "▶ 下载nvm安装脚本..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    
    echo "▶ 迁移到系统目录: $NVM_DIR..."
    mkdir -p "$NVM_DIR"
    cp -r ~/.nvm/* "$NVM_DIR"
    chmod -R 755 "$NVM_DIR"
    rm -rf ~/.nvm
    
    echo "▶ 配置全局环境变量..."
    cat > /etc/profile.d/nvm.sh <<EOF
export NVM_DIR="$NVM_DIR"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && \. "\$NVM_DIR/bash_completion"
EOF
    
    echo "▶ 加载环境配置..."
    set -a
    source /etc/profile.d/nvm.sh
    set +a
    echo "✓ nvm安装完成"
}

# --------------------------------------------------
# 函数：安装Node.js
install_nodejs() {
    echo -e "\n\033[34m[3/7] 正在安装Node.js运行时...\033[0m"
    
    echo "▶ 安装最新LTS版本..."
    nvm install --lts || {
        echo "✗ Node.js LTS 安装失败！"
        exit 1
    }
    
    echo "▶ 安装最新稳定版..."
    nvm install node || {
        echo "✗ Node.js 最新版安装失败！"
        exit 1
    }
    
    echo "▶ 确定LTS版本..."
    LTS_VERSION=$(nvm ls-remote --lts | grep -Po 'v[0-9]+\.[0-9]+\.[0-9]+' | sort -t. -k1,1nr -k2,2nr -k3,3nr | head -1)
    [ -z "$LTS_VERSION" ] && LTS_VERSION="--lts"
    echo "✓ 使用LTS版本: $LTS_VERSION"
    
    echo "▶ 设置默认版本..."
    nvm alias default "$LTS_VERSION"
    nvm use default
    
    echo "▶ 创建系统链接..."
    ln -sf "$NVM_DIR/versions/node/$(nvm current)/bin/node" /usr/local/bin/node || {
        echo "✗ 创建 node 链接失败！"
        exit 1
    }
    ln -sf "$NVM_DIR/versions/node/$(nvm current)/bin/npm" /usr/local/bin/npm || {
        echo "✗ 创建 npm 链接失败！"
        exit 1
    }
    echo "✓ Node.js安装完成"
}

# --------------------------------------------------
# 函数：安装pnpm
install_pnpm() {
    echo -e "\n\033[34m[4/7] 正在安装pnpm包管理器...\033[0m"
    
    echo "▶ 下载pnpm安装脚本..."
    curl -fsSL https://get.pnpm.io/install.sh | sh - || {
        echo "✗ pnpm 安装失败！"
        exit 1
    }
    
    echo "▶ 迁移到系统目录: $PNPM_HOME..."
    mkdir -p "$PNPM_HOME"
    if [ -d ~/.local/share/pnpm ]; then
        mv ~/.local/share/pnpm/* "$PNPM_HOME" || {
            echo "✗ pnpm 迁移失败！"
            exit 1
        }
    fi
    chmod -R 755 "$PNPM_HOME"
    
    echo "▶ 配置全局环境..."
    cat > /etc/profile.d/pnpm.sh <<EOF
export PNPM_HOME="$PNPM_HOME"
export PATH="\$PNPM_HOME:\$PATH"
EOF
    
    echo "▶ 创建系统链接..."
    ln -sf "$PNPM_HOME/pnpm" /usr/local/bin/pnpm || {
        echo "✗ 创建 pnpm 链接失败！"
        exit 1
    }
    ln -sf "$PNPM_HOME/pnpx" /usr/local/bin/pnpx || {
        echo "✗ 创建 pnpx 链接失败！"
        exit 1
    }
    
    echo "▶ 加载环境配置..."
    set -a
    source /etc/profile.d/pnpm.sh
    set +a
    echo "✓ pnpm安装完成"
}

# --------------------------------------------------
# 函数：安装工具链
install_toolchain() {
    echo -e "\n\033[34m[5/7] 正在安装生产工具链...\033[0m"
    
    echo "▶ 安装PM2进程管理器..."
    pnpm add -g pm2 || {
        echo "✗ PM2安装失败！"
        exit 1
    }
    
    echo "▶ 安装TypeScript工具链..."
    pnpm add -g typescript ts-node || {
        echo "✗ TypeScript工具链安装失败！"
        exit 1
    }
    
    echo "▶ 配置安全权限..."
    npm config set unsafe-perm false
    chmod 755 /usr/local/bin/node
    chmod 755 /usr/local/bin/npm
    echo "✓ 工具链安装完成"
}

# --------------------------------------------------
# 函数：系统优化
optimize_system() {
    echo -e "\n\033[34m[6/7] 正在优化系统配置...\033[0m"
    
    echo "▶ 优化文件监控限制..."
    echo "fs.inotify.max_user_watches=524288" >> /etc/sysctl.conf
    sysctl -p
    
    echo "▶ 配置内存优化..."
    echo 'export NODE_OPTIONS="--max-old-space-size=4096"' >> /etc/profile
    
    echo "▶ 配置防火墙规则..."
    ufw allow 22
    ufw allow 80
    ufw allow 443
    ufw --force enable || echo "⚠ 警告：防火墙启用失败，请手动检查！"
    echo "✓ 系统优化完成"
}

# --------------------------------------------------
# 函数：配置生产服务
configure_services() {
    echo -e "\n\033[34m[7/7] 正在配置生产服务...\033[0m"
    
    echo "▶ 创建应用目录: $APP_DIR..."
    mkdir -p "$APP_DIR"
    chown -R "$NODE_USER":"$NODE_USER" "$APP_DIR"
    
    echo "▶ 配置用户环境..."
    sudo -u "$NODE_USER" bash -c "echo 'source /etc/profile.d/nvm.sh' >> ~/.bashrc"
    sudo -u "$NODE_USER" bash -c "echo 'source /etc/profile.d/pnpm.sh' >> ~/.bashrc"
    
    echo "▶ 创建PM2系统服务..."
    cat > /etc/systemd/system/pm2.service <<EOF
[Unit]
Description=PM2 Process Manager
After=network.target network-online.target
Wants=network-online.target

[Service]
User=$NODE_USER
Environment=NODE_ENV=production
WorkingDirectory=$APP_DIR
ExecStart=$(which pm2) resurrect
ExecReload=$(which pm2) reload all
ExecStop=$(which pm2) kill

Restart=always
RestartSec=3
StartLimitInterval=0

[Install]
WantedBy=multi-user.target
EOF
    
    echo "▶ 启用PM2服务..."
    systemctl daemon-reload
    systemctl enable pm2.service
    
    echo "▶ 创建示例应用..."
    cat > "$APP_DIR/app.js" <<EOF
const http = require('http');
const server = http.createServer((req, res) => {
  res.writeHead(200, {'Content-Type': 'text/plain'});
  res.end('✅ Node.js生产环境部署成功！\n');
});
server.listen(3000, () => {
  console.log('生产服务运行在: http://localhost:3000');
});
EOF
    
    echo "▶ 设置目录权限..."
    chown -R "$NODE_USER":"$NODE_USER" "$APP_DIR"
    
    echo "▶ 启动示例应用..."
    sudo -u "$NODE_USER" pm2 start "$APP_DIR/app.js" --name "node-api" || {
        echo "✗ PM2启动失败！"
        exit 1
    }
    
    echo "▶ 保存PM2配置..."
    sudo -u "$NODE_USER" pm2 save || {
        echo "✗ PM2配置保存失败！"
        exit 1
    }
    
    echo "✓ 服务配置完成"
}

# --------------------------------------------------
# 函数：显示部署摘要
show_summary() {
    echo "============================================="
    echo "Node.js 生产环境部署完成！"
    echo "============================================="
    echo -e "\033[32m[系统信息]\033[0m"
    echo "Node版本: $(node -v)"
    echo "NPM版本: $(npm -v)"
    echo "PNPM版本: $(pnpm -v)"
    echo "运行用户: $NODE_USER"
    echo "应用目录: $APP_DIR"
    echo "NVM目录: $NVM_DIR"
    echo "PNPM目录: $PNPM_HOME"
    echo ""
    echo -e "\033[32m[管理命令]\033[0m"
    echo "启动服务: systemctl start pm2"
    echo "停止服务: systemctl stop pm2"
    echo "查看日志: journalctl -u pm2 -f"
    echo "应用目录: cd $APP_DIR"
    echo ""
    echo -e "\033[32m[验证命令]\033[0m"
    echo "用户验证: sudo -u $NODE_USER node -v"
    echo "服务状态: curl -I http://localhost:3000"
    echo ""
    echo -e "\033[32m[安全建议]\033[0m"
    echo "1. 定期执行: npm audit"
    echo "2. 配置SSH密钥登录"
    echo "3. 启用防火墙: ufw enable"
    echo "4. 定期更新: nvm install --lts"
    echo "============================================="
}

# --------------------------------------------------
# 主执行流程
# --------------------------------------------------
main() {
    # 执行所有步骤
    prepare_system
    install_nvm
    install_nodejs
    install_pnpm
    install_toolchain
    optimize_system
    configure_services
    
    # 显示部署摘要
    show_summary
}

# 启动主流程
main