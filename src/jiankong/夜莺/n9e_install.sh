#!/bin/bash
set -euo pipefail

# Nightingale 6.0 安装脚本 (CentOS 7.9 专用) - 全路径安装到 /data/n9e
N9E_VERSION="6.0.1"
BASE_DIR="/data/n9e"
INSTALL_DIR="${BASE_DIR}/install"
CONFIG_DIR="${BASE_DIR}/etc"
DATA_DIR="${BASE_DIR}/data"
LOG_DIR="${BASE_DIR}/logs"
SUPERVISOR_CONF="${CONFIG_DIR}/supervisor.conf"

# 环境检查
function check_env() {
    echo "🔍 检查系统环境..."
    # 内核版本检查
    if [[ $(uname -r | cut -d. -f1) -lt 3 ]]; then
        echo "❌ 内核版本需 ≥3.10 (当前: $(uname -r))"
        exit 1
    fi

    # 内存检查
    local mem=$(free -m | awk '/Mem:/{print $2}')
    if [[ $mem -lt 4096 ]]; then
        echo "⚠️ 推荐内存 ≥4GB (当前: ${mem}MB)"
    fi

    # 磁盘空间检查
    local disk_needed=1024 # MB
    local disk_free=$(df -m ${BASE_DIR} | awk 'NR==2{print $4}')
    if [[ $disk_free -lt $disk_needed ]]; then
        echo "❌ ${BASE_DIR} 需要至少 1GB 可用空间 (当前: ${disk_free}MB)"
        exit 1
    fi
}

# 安装基础依赖
function install_deps() {
    echo "🔧 安装系统依赖..."
    yum install -y epel-release
    yum install -y wget tar jq sqlite unzip openssl-devel
}

# 配置自定义 supervisor
function setup_supervisor() {
    echo "📋 配置自定义 Supervisor..."
    # 下载独立的 supervisor
    wget https://github.com/Supervisor/supervisor/archive/refs/tags/4.2.5.tar.gz -O /tmp/supervisor.tar.gz
    tar zxf /tmp/supervisor.tar.gz -C /tmp
    cd /tmp/supervisor-4.2.5 && python setup.py install
    
    # 创建配置文件
    mkdir -p ${CONFIG_DIR}/supervisor
    cat << EOF > ${SUPERVISOR_CONF}
[unix_http_server]
file=${BASE_DIR}/supervisor.sock

[supervisord]
logfile=${LOG_DIR}/supervisord.log
logfile_maxbytes=50MB
logfile_backups=10
loglevel=info
pidfile=${BASE_DIR}/supervisord.pid
nodaemon=false
minfds=1024
minprocs=200

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix://${BASE_DIR}/supervisor.sock

[include]
files = ${CONFIG_DIR}/supervisor/*.conf
EOF

    # 创建启动脚本
    cat << EOF > /etc/systemd/system/supervisord.service
[Unit]
Description=Supervisor process control system
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/bin/supervisord -c ${SUPERVISOR_CONF}
ExecStop=/usr/local/bin/supervisorctl -c ${SUPERVISOR_CONF} shutdown
ExecReload=/usr/local/bin/supervisorctl -c ${SUPERVISOR_CONF} reload
KillMode=process
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    systemctl daemon-reload
    systemctl enable supervisord
    systemctl start supervisord
}

# 创建目录结构
function create_dirs() {
    echo "📁 创建目录结构..."
    mkdir -p ${BASE_DIR}
    mkdir -p ${INSTALL_DIR}/bin
    mkdir -p ${CONFIG_DIR}/{heartbeat,index,metrics,pushgw,server,webapi}
    mkdir -p ${CONFIG_DIR}/supervisor
    mkdir -p ${DATA_DIR}/{sqlite,tsdb}
    mkdir -p ${LOG_DIR}
    chmod -R 755 ${BASE_DIR}
}

# 下载安装包
function download_n9e() {
    echo "📦 下载 Nightingale v${N9E_VERSION}..."
    local download_url="https://github.com/ccfos/nightingale/releases/download/v${N9E_VERSION}/n9e-${N9E_VERSION}.linux-amd64.tar.gz"
    
    wget -qO /tmp/n9e.tar.gz ${download_url} || {
        echo "⚠️ 主镜像下载失败，尝试备用镜像..."
        wget -qO /tmp/n9e.tar.gz "https://n9e-download.oss-cn-beijing.aliyuncs.com/v${N9E_VERSION}/n9e-${N9E_VERSION}.linux-amd64.tar.gz" || {
            echo "❌ 备用镜像下载失败，请手动下载后放置到 /tmp/n9e.tar.gz"
            exit 1
        }
    }

    echo "📂 解压安装文件..."
    tar -zxf /tmp/n9e.tar.gz -C ${INSTALL_DIR}/bin --strip-components=1
    rm -f /tmp/n9e.tar.gz
}

# 生成配置文件
function generate_configs() {
    echo "⚙️ 生成配置文件..."
    # 生成证书
    openssl req -x509 -newkey rsa:4096 -keyout ${CONFIG_DIR}/server/key.pem -out ${CONFIG_DIR}/server/cert.pem -days 365 -nodes -subj "/CN=n9e"

    # 主配置模板
    cat << EOF > ${CONFIG_DIR}/config.toml
[Global]
Listen = ":17000"
LogLevel = "info"
RunMode = "prod"

[HTTP]
Enable = true
Host = "0.0.0.0"
Port = 17000
CertFile = "${CONFIG_DIR}/server/cert.pem"
KeyFile = "${CONFIG_DIR}/server/key.pem"

[DB]
DBType = "sqlite"
DSN = "${DATA_DIR}/sqlite/n9e.db?cache=shared&_journal_mode=WAL"

[SMTP]
Host = "smtp.example.com"
Port = 587
User = "user@example.com"
Pass = "your-password"
From = "alert@n9e.example.com"

[Clusters]
Default = 1

[[Clusters.Nodes]]
Name = "n9e-server"
Address = "http://127.0.0.1:17000"
EOF

    # 组件配置
    for component in heartbeat index metrics pushgw server webapi; do
        cp ${INSTALL_DIR}/bin/etc/${component}.toml ${CONFIG_DIR}/${component}/
        sed -i "s|/opt/n9e|${CONFIG_DIR}|g" ${CONFIG_DIR}/${component}/${component}.toml
    done

    # 初始化数据库
    echo "💾 初始化数据库..."
    sqlite3 ${DATA_DIR}/sqlite/n9e.db < ${INSTALL_DIR}/bin/sql/n9e.sql
}

# 创建 Supervisor 服务配置
function create_supervisor_configs() {
    echo "🛠️ 创建 Supervisor 服务配置..."
    # 创建进程组配置
    cat << EOF > ${CONFIG_DIR}/supervisor/n9e-server.conf
[program:n9e-server]
command = ${INSTALL_DIR}/bin/n9e server
directory = ${INSTALL_DIR}/bin
autostart = true
autorestart = true
startsecs = 3
startretries = 3
user = root
redirect_stderr = true
stdout_logfile = ${LOG_DIR}/server.log
stdout_logfile_maxbytes = 50MB
stdout_logfile_backups = 5
environment = N9E_CONFIG_FILE="${CONFIG_DIR}/server/server.toml"
EOF

    cat << EOF > ${CONFIG_DIR}/supervisor/n9e-webapi.conf
[program:n9e-webapi]
command = ${INSTALL_DIR}/bin/n9e webapi
directory = ${INSTALL_DIR}/bin
autostart = true
autorestart = true
startsecs = 3
startretries = 3
user = root
redirect_stderr = true
stdout_logfile = ${LOG_DIR}/webapi.log
stdout_logfile_maxbytes = 50MB
stdout_logfile_backups = 5
environment = N9E_CONFIG_FILE="${CONFIG_DIR}/webapi/webapi.toml"
EOF

    cat << EOF > ${CONFIG_DIR}/supervisor/n9e-pushgw.conf
[program:n9e-pushgw]
command = ${INSTALL_DIR}/bin/n9e pushgw
directory = ${INSTALL_DIR}/bin
autostart = true
autorestart = true
startsecs = 3
startretries = 3
user = root
redirect_stderr = true
stdout_logfile = ${LOG_DIR}/pushgw.log
stdout_logfile_maxbytes = 50MB
stdout_logfile_backups = 5
environment = N9E_CONFIG_FILE="${CONFIG_DIR}/pushgw/pushgw.toml"
EOF

    # 重新加载配置
    supervisorctl -c ${SUPERVISOR_CONF} reread
    supervisorctl -c ${SUPERVISOR_CONF} update
}

# 防火墙配置
function configure_firewall() {
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        echo "🔥 配置防火墙规则..."
        firewall-cmd --permanent --add-port=17000/tcp
        firewall-cmd --reload
    fi
}

# 创建管理脚本
function create_management_scripts() {
    echo "📝 创建管理脚本..."
    # 创建启动脚本
    cat << EOF > ${BASE_DIR}/n9e-start.sh
#!/bin/bash
systemctl start supervisord
supervisorctl -c ${SUPERVISOR_CONF} start all
EOF

    # 创建停止脚本
    cat << EOF > ${BASE_DIR}/n9e-stop.sh
#!/bin/bash
supervisorctl -c ${SUPERVISOR_CONF} stop all
systemctl stop supervisord
EOF

    # 创建状态检查脚本
    cat << EOF > ${BASE_DIR}/n9e-status.sh
#!/bin/bash
systemctl status supervisord
supervisorctl -c ${SUPERVISOR_CONF} status
EOF

    # 创建日志查看脚本
    cat << EOF > ${BASE_DIR}/n9e-logs.sh
#!/bin/bash
tail -f ${LOG_DIR}/*.log
EOF

    # 设置权限
    chmod +x ${BASE_DIR}/*.sh
}

# 安装后检查
function post_install_check() {
    echo "🔄 启动服务 (约需30秒)..."
    sleep 30

    # 检查服务状态
    supervisorctl -c ${SUPERVISOR_CONF} status
    
    local status=$(curl -sIk "https://localhost:17000" 2>/dev/null | head -n1 | cut -d' ' -f2)
    if [[ "$status" == "200" ]]; then
        echo -e "\n✅ 安装成功！"
        echo -e "---------------------------------------------"
        echo -e "控制台地址: \e[34mhttps://$(hostname -I | awk '{print $1}'):17000\e[0m"
        echo -e "初始账号: \e[32mroot\e[0m"
        echo -e "初始密码: \e[32mroot.2020\e[0m"
        echo -e "---------------------------------------------"
        echo -e "安装目录: ${INSTALL_DIR}"
        echo -e "配置目录: ${CONFIG_DIR}"
        echo -e "数据目录: ${DATA_DIR}"
        echo -e "日志目录: ${LOG_DIR}"
        echo -e "---------------------------------------------"
        echo -e "管理脚本:"
        echo -e "启动服务:    \e[32m${BASE_DIR}/n9e-start.sh\e[0m"
        echo -e "停止服务:    \e[32m${BASE_DIR}/n9e-stop.sh\e[0m"
        echo -e "查看状态:    \e[32m${BASE_DIR}/n9e-status.sh\e[0m"
        echo -e "查看日志:    \e[32m${BASE_DIR}/n9e-logs.sh\e[0m"
    else
        echo "❌ 服务启动失败，检查日志:"
        echo "Supervisor 日志: ${LOG_DIR}/supervisord.log"
        echo "Server 日志: ${LOG_DIR}/server.log"
        exit 1
    fi
}

# 主流程
function main() {
    check_env
    install_deps
    create_dirs
    setup_supervisor
    download_n9e
    generate_configs
    create_supervisor_configs
    create_management_scripts
    configure_firewall
    post_install_check
    
    echo -e "\n安装完成，所有组件已安装在 \e[34m${BASE_DIR}\e[0m"
}

main