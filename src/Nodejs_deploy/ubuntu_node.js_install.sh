#!/bin/bash

# =============================================
# Node.js 生产环境一键部署脚本 (Root专用优化版)
# 版本：3.1
# 更新：修复环境加载、增强错误处理、优化服务配置
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

# 步骤1：系统准备
echo -e "\n\033[34m[1/7] 正在准备系统环境...\033[0m"
apt update -y && apt upgrade -y
apt install -y build-essential libssl-dev curl git python3 make gcc

# 创建专用用户
if ! id "$NODE_USER" &>/dev/null; then
    useradd -r -m -d "$APP_DIR" -s /bin/bash "$NODE_USER"
    echo "已创建专用用户: $NODE_USER"
fi

# 步骤2：安装系统级nvm
echo -e "\n\033[34m[2/7] 正在安装系统级Node版本管理器(nvm)...\033[0m"

# 下载安装nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# 迁移到系统目录
mkdir -p "$NVM_DIR"
cp -r ~/.nvm/* "$NVM_DIR"
chmod -R 755 "$NVM_DIR"
rm -rf ~/.nvm

# 配置全局环境
cat > /etc/profile.d/nvm.sh <<EOF
export NVM_DIR="$NVM_DIR"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && \. "\$NVM_DIR/bash_completion"
EOF

# 立即生效（增强加载）
set -a
source /etc/profile.d/nvm.sh
set +a

# 步骤3：安装Node.js（系统级）
echo -e "\n\033[34m[3/7] 正在安装系统级Node.js运行时...\033[0m"

# 安装最新LTS和稳定版
nvm install --lts || {
    echo "Node.js LTS 安装失败！"
    exit 1
}
nvm install node || {
    echo "Node.js 最新版安装失败！"
    exit 1
}

# 获取最新LTS版本（增强健壮性）
LTS_VERSION=$(nvm ls-remote --lts | grep -Po 'v[0-9]+\.[0-9]+\.[0-9]+' | sort -t. -k1,1nr -k2,2nr -k3,3nr | head -1)
[ -z "$LTS_VERSION" ] && LTS_VERSION="--lts"  # 备用方案

# 设置默认版本
nvm alias default "$LTS_VERSION"
nvm use default

# 创建系统级链接
ln -sf "$NVM_DIR/versions/node/$(nvm current)/bin/node" /usr/local/bin/node || {
    echo "创建 node 链接失败！"
    exit 1
}
ln -sf "$NVM_DIR/versions/node/$(nvm current)/bin/npm" /usr/local/bin/npm || {
    echo "创建 npm 链接失败！"
    exit 1
}

# 步骤4：安装系统级pnpm
echo -e "\n\033[34m[4/7] 正在安装系统级pnpm包管理器...\033[0m"

# 安装pnpm
curl -fsSL https://get.pnpm.io/install.sh | sh - || {
    echo "pnpm 安装失败！"
    exit 1
}

# 迁移到系统目录
mkdir -p "$PNPM_HOME"
if [ -d ~/.local/share/pnpm ]; then
    mv ~/.local/share/pnpm/* "$PNPM_HOME" || {
        echo "pnpm 迁移失败！"
        exit 1
    }
fi
chmod -R 755 "$PNPM_HOME"

# 配置全局环境
cat > /etc/profile.d/pnpm.sh <<EOF
export PNPM_HOME="$PNPM_HOME"
export PATH="\$PNPM_HOME:\$PATH"
EOF

# 创建系统链接
ln -sf "$PNPM_HOME/pnpm" /usr/local/bin/pnpm || {
    echo "创建 pnpm 链接失败！"
    exit 1
}
ln -sf "$PNPM_HOME/pnpx" /usr/local/bin/pnpx || {
    echo "创建 pnpx 链接失败！"
    exit 1
}

# 立即生效（增强加载）
set -a
source /etc/profile.d/pnpm.sh
set +a

# 步骤5：安装生产工具链
echo -e "\n\033[34m[5/7] 正在安装生产工具链...\033[0m"

# 安装核心工具
pnpm add -g pm2 typescript ts-node || {
    echo "工具链安装失败！"
    exit 1
}

# 安全配置
npm config set unsafe-perm false
chmod 755 /usr/local/bin/node
chmod 755 /usr/local/bin/npm

# 步骤6：系统优化与安全加固
echo -e "\n\033[34m[6/7] 正在优化系统配置...\033[0m"

# 文件监控优化
echo "fs.inotify.max_user_watches=524288" >> /etc/sysctl.conf
sysctl -p

# 内存优化
echo 'export NODE_OPTIONS="--max-old-space-size=4096"' >> /etc/profile

# 防火墙规则
ufw allow 22
ufw allow 80
ufw allow 443
ufw --force enable || echo "警告：防火墙启用失败，请手动检查！"

# 步骤7：配置生产服务
echo -e "\n\033[34m[7/7] 正在配置生产服务...\033[0m"

# 创建应用目录
mkdir -p "$APP_DIR"
chown -R "$NODE_USER":"$NODE_USER" "$APP_DIR"

# 配置用户环境
sudo -u "$NODE_USER" bash -c "echo 'source /etc/profile.d/nvm.sh' >> ~/.bashrc"
sudo -u "$NODE_USER" bash -c "echo 'source /etc/profile.d/pnpm.sh' >> ~/.bashrc"

# 创建PM2系统服务（增强服务依赖）
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

# 启用服务
systemctl daemon-reload
systemctl enable pm2.service

# 创建示例应用
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

# 设置权限
chown -R "$NODE_USER":"$NODE_USER" "$APP_DIR"

# 初始化PM2
sudo -u "$NODE_USER" pm2 start "$APP_DIR/app.js" --name "node-api" || {
    echo "PM2启动失败！"
    exit 1
}

# 保存PM2配置
sudo -u "$NODE_USER" pm2 save || {
    echo "PM2配置保存失败！"
    exit 1
}

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