#!/bin/bash
# CentOS Node.js 生产环境一键部署脚本（修复版）
# 包含专用用户创建、PM2 进程管理和应用部署
# 支持 CentOS 7/8/9
# 作者：您的名字
# 日期：$(date +%Y-%m-%d)

# 检查是否以root运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本必须以root权限运行"
    exit 1
fi

# 安装日志文件
LOG_FILE="/var/log/nodejs_production_deploy.log"
echo "Node.js 生产环境部署日志 - $(date)" > $LOG_FILE

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 安装成功消息
success_msg() {
    echo -e "${GREEN}$1${NC}"
    echo "$1" >> $LOG_FILE
}

# 警告消息
warn_msg() {
    echo -e "${YELLOW}$1${NC}"
    echo "$1" >> $LOG_FILE
}

# 错误消息
error_msg() {
    echo -e "${RED}$1${NC}"
    echo "$1" >> $LOG_FILE
    exit 1
}

# 安装依赖
install_dependencies() {
    echo "安装系统依赖..." | tee -a $LOG_FILE
    yum install -y curl gcc-c++ make git tar >> $LOG_FILE 2>&1
    if [ $? -eq 0 ]; then
        success_msg "系统依赖安装成功"
    else
        error_msg "系统依赖安装失败"
    fi
}

# 安装 Node.js (修复版)
install_nodejs() {
    echo "安装 Node.js 和 npm..." | tee -a $LOG_FILE
    
    # 方法1: 使用 NodeSource 安装
    install_via_nodesource() {
        # 获取最新的 LTS 版本号
        NODE_VERSION=$(curl -s https://nodejs.org/dist/index.json | grep -o '"lts":"[^"]*"' | head -1 | cut -d'"' -f4)
        
        if [ -z "$NODE_VERSION" ]; then
            warn_msg "无法获取最新 LTS 版本，使用默认版本"
            NODE_VERSION="18.x" # 默认版本
        fi
        
        # 安装 NodeSource 仓库
        curl -fsSL https://rpm.nodesource.com/setup_${NODE_VERSION} | bash - >> $LOG_FILE 2>&1
        if [ $? -ne 0 ]; then
            return 1
        fi
        
        # 安装 Node.js
        yum install -y nodejs >> $LOG_FILE 2>&1
        return $?
    }
    
    # 方法2: 使用 EPEL 安装
    install_via_epel() {
        # 安装 EPEL 仓库
        yum install -y epel-release >> $LOG_FILE 2>&1
        if [ $? -ne 0 ]; then
            return 1
        fi
        
        # 安装 Node.js
        yum install -y nodejs >> $LOG_FILE 2>&1
        return $?
    }
    
    # 尝试 NodeSource 安装
    install_via_nodesource
    if [ $? -eq 0 ]; then
        success_msg "Node.js 和 npm 安装成功 (NodeSource)"
        echo "Node.js 版本: $(node -v)" | tee -a $LOG_FILE
        echo "npm 版本: $(npm -v)" | tee -a $LOG_FILE
        return 0
    else
        warn_msg "NodeSource 安装失败，尝试 EPEL 安装"
    fi
    
    # 尝试 EPEL 安装
    install_via_epel
    if [ $? -eq 0 ]; then
        success_msg "Node.js 和 npm 安装成功 (EPEL)"
        echo "Node.js 版本: $(node -v)" | tee -a $LOG_FILE
        echo "npm 版本: $(npm -v)" | tee -a $LOG_FILE
        return 0
    else
        error_msg "Node.js 和 npm 安装失败"
        return 1
    fi
}

# 创建专用用户
create_node_user() {
    echo "创建专用 Node.js 用户..." | tee -a $LOG_FILE
    
    # 默认用户名
    NODE_USER="nodeapp"
    
    # 检查用户是否存在
    if id "$NODE_USER" &>/dev/null; then
        warn_msg "用户 $NODE_USER 已存在，跳过创建"
    else
        # 创建用户和组
        useradd -r -m -s /bin/bash -d /home/$NODE_USER $NODE_USER
        echo "为 $NODE_USER 设置密码:"
        passwd $NODE_USER
        
        # 创建应用目录
        mkdir -p /opt/node-apps
        chown $NODE_USER:$NODE_USER /opt/node-apps
        
        success_msg "用户 $NODE_USER 创建成功"
    fi
}

# 安装 PM2 进程管理器
install_pm2() {
    echo "安装 PM2 进程管理器..." | tee -a $LOG_FILE
    
    # 全局安装 PM2
    npm install -g pm2 >> $LOG_FILE 2>&1
    
    if [ $? -eq 0 ]; then
        success_msg "PM2 安装成功"
        
        # 设置 PM2 开机自启
        pm2 startup systemd -u $NODE_USER --hp /home/$NODE_USER >> $LOG_FILE 2>&1
        if [ $? -eq 0 ]; then
            success_msg "PM2 开机自启配置成功"
        else
            warn_msg "PM2 开机自启配置失败"
        fi
    else
        error_msg "PM2 安装失败"
    fi
}

# 部署示例应用
deploy_sample_app() {
    echo "部署示例 Node.js 应用..." | tee -a $LOG_FILE
    
    APP_NAME="node-sample-app"
    APP_DIR="/opt/node-apps/$APP_NAME"
    
    # 创建应用目录
    mkdir -p $APP_DIR
    chown $NODE_USER:$NODE_USER $APP_DIR
    
    # 切换到应用目录
    cd $APP_DIR
    
    # 创建 package.json
    cat > package.json <<EOF
{
  "name": "$APP_NAME",
  "version": "1.0.0",
  "description": "Node.js 示例应用",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF
    
    # 创建应用文件
    cat > app.js <<EOF
const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.send(`
    <h1>Node.js 生产环境部署成功!</h1>
    <p>服务器时间: \${new Date()}</p>
    <p>Node.js 版本: \${process.version}</p>
    <p>运行用户: \${process.env.USER}</p>
    <p>PM2 状态: <a href="/status">查看</a></p>
  `);
});

app.get('/status', (req, res) => {
  res.json({
    status: 'running',
    server: process.env.HOSTNAME || 'unknown',
    memory: process.memoryUsage(),
    uptime: process.uptime()
  });
});

app.listen(PORT, () => {
  console.log(\`服务器运行在 http://localhost:\${PORT}\`);
});
EOF
    
    # 安装依赖
    sudo -u $NODE_USER npm install >> $LOG_FILE 2>&1
    
    if [ $? -eq 0 ]; then
        success_msg "应用依赖安装成功"
    else
        warn_msg "应用依赖安装失败"
    fi
    
    # 使用 PM2 启动应用
    sudo -u $NODE_USER pm2 start app.js --name $APP_NAME >> $LOG_FILE 2>&1
    
    if [ $? -eq 0 ]; then
        success_msg "应用启动成功"
        
        # 保存 PM2 配置
        sudo -u $NODE_USER pm2 save >> $LOG_FILE 2>&1
        
        # 获取应用信息
        APP_URL=$(curl -s ifconfig.me)
        echo ""
        success_msg "示例应用已部署:"
        echo -e "访问地址: ${GREEN}http://$APP_URL:3000${NC}"
        echo -e "状态检查: ${GREEN}http://$APP_URL:3000/status${NC}"
        echo -e "PM2 管理: ${GREEN}pm2 monit${NC} (以 $NODE_USER 用户运行)"
    else
        error_msg "应用启动失败"
    fi
}

# 配置防火墙
configure_firewall() {
    echo "配置防火墙..." | tee -a $LOG_FILE
    
    # 检查防火墙状态
    if systemctl is-active --quiet firewalld; then
        # 开放 Node.js 端口
        firewall-cmd --permanent --add-port=3000/tcp >> $LOG_FILE 2>&1
        firewall-cmd --reload >> $LOG_FILE 2>&1
        success_msg "防火墙已配置，开放端口 3000"
    else
        warn_msg "防火墙未运行，跳过配置"
    fi
}

# 设置环境优化
optimize_environment() {
    echo "优化系统环境..." | tee -a $LOG_FILE
    
    # 增加文件描述符限制
    echo "* soft nofile 65536" >> /etc/security/limits.conf
    echo "* hard nofile 65536" >> /etc/security/limits.conf
    
    # 增加进程限制
    echo "vm.max_map_count=262144" >> /etc/sysctl.conf
    sysctl -p >> $LOG_FILE 2>&1
    
    # 设置时区为上海
    timedatectl set-timezone Asia/Shanghai
    
    success_msg "系统环境优化完成"
}

# 主安装函数
main_install() {
    echo "开始部署 Node.js 生产环境..."
    install_dependencies
    install_nodejs
    create_node_user
    install_pm2
    deploy_sample_app
    configure_firewall
    optimize_environment
    
    echo ""
    success_msg "Node.js 生产环境部署完成!"
    echo "安装日志: $LOG_FILE"
    echo "专用用户: $NODE_USER"
    echo "应用目录: /opt/node-apps"
    echo "PM2 命令: sudo -u $NODE_USER pm2 [list|monit|start|stop]"
    echo ""
    echo -e "${YELLOW}下一步建议:${NC}"
    echo "1. 配置您自己的应用代码到 /opt/node-apps"
    echo "2. 使用 'sudo -u $NODE_USER pm2 start your-app.js' 启动应用"
    echo "3. 配置 Nginx 反向代理和 HTTPS"
}

# 执行主安装函数
main_install