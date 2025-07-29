#!/bin/bash
set -euo pipefail

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo "❌ 此脚本必须使用 root 权限运行" >&2
    exit 1
fi

# 配置参数
N9E_VERSION="8.1.0"
BASE_DIR="/opt/n9e"  # 官方推荐目录
INSTALL_DIR="${BASE_DIR}"
CONFIG_DIR="${BASE_DIR}/etc"
DATA_DIR="${BASE_DIR}/data"
LOG_DIR="${BASE_DIR}/logs"
RUN_USER="n9e"  # 专用运行用户

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
        read -p "是否继续? (y/N)" -n 1 -r
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
}

# 安装基础依赖
function install_deps() {
    echo "🔧 安装系统依赖..."
    yum install -y epel-release
    yum install -y wget tar jq sqlite unzip openssl-devel gcc python-devel python2-pip make
    
    # 创建专用用户
    if ! id -u "${RUN_USER}" >/dev/null 2>&1; then
        useradd -r -s /sbin/nologin -d "${BASE_DIR}" "${RUN_USER}"
    fi
}

# 安装系统级 Supervisor
function install_system_supervisor() {
    echo "📋 安装系统级 Supervisor..."
    
    # 安装系统包
    yum install -y supervisor
    
    # 创建必要的目录
    mkdir -p /var/run/supervisor
    mkdir -p /var/log/supervisor
    chown root:root /var/run/supervisor
    chown root:root /var/log/supervisor
    chmod 755 /var/run/supervisor
    chmod 755 /var/log/supervisor
    
    # 创建自定义配置目录
    mkdir -p /etc/supervisor.d
    
    # 修改主配置文件
    cat << EOF > /etc/supervisord.conf
[unix_http_server]
file=/var/run/supervisor/supervisor.sock
chmod=0770
chown=root:root

[supervisord]
logfile=/var/log/supervisor/supervisord.log
logfile_maxbytes=50MB
logfile_backups=10
loglevel=info
pidfile=/var/run/supervisord.pid
nodaemon=false
minfds=1024
minprocs=200
user=root

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run/supervisor/supervisor.sock

[include]
files = /etc/supervisor.d/*.conf
EOF

    # 创建服务文件
    cat << EOF > /etc/systemd/system/supervisord.service
[Unit]
Description=Supervisor process control system
After=network.target

[Service]
Type=forking
ExecStart=/usr/bin/supervisord -c /etc/supervisord.conf
ExecStop=/usr/bin/supervisorctl shutdown
ExecReload=/usr/bin/supervisorctl reload
KillMode=process
Restart=on-failure
RestartSec=5s
User=root
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

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
    mkdir -p "${BASE_DIR}"
    mkdir -p "${INSTALL_DIR}/bin"
    mkdir -p "${CONFIG_DIR}"/{heartbeat,index,metrics,pushgw,server,webapi}
    mkdir -p "${DATA_DIR}"/{sqlite,tsdb}
    mkdir -p "${LOG_DIR}"
    # 设置所有权
    chown -R ${RUN_USER}:${RUN_USER} "${BASE_DIR}"
    chmod -R 750 "${BASE_DIR}"
}

# 下载安装包
function download_n9e() {
    echo "📦 下载 Nightingale v${N9E_VERSION}..."
    cp /tmp/n9e-v${N9E_VERSION}-linux-amd64.tar.gz /tmp/n9e.tar.gz
    
    echo "📂 解压安装文件..."
    # 创建临时解压目录
    mkdir -p "${INSTALL_DIR}/temp"
    tar -zxf /tmp/n9e.tar.gz -C "${INSTALL_DIR}/temp"
    
    # 查找实际文件位置
    local bin_dir=$(find "${INSTALL_DIR}/temp" -name bin -type d)
    local sql_dir=$(find "${INSTALL_DIR}/temp" -name sql -type d)
    
    # 移动文件到正确位置
    if [[ -d "${bin_dir}" ]]; then
        mv "${bin_dir}" "${INSTALL_DIR}/bin"
    fi
    
    if [[ -d "${sql_dir}" ]]; then
        mv "${sql_dir}" "${INSTALL_DIR}/sql"
    fi
    
    # 清理临时目录
    rm -rf "${INSTALL_DIR}/temp"
    rm -f /tmp/n9e.tar.gz
}

# 生成配置文件
function generate_configs() {
    echo "⚙️ 生成配置文件..."
    # 生成证书
    openssl req -x509 -newkey rsa:4096 -keyout "${CONFIG_DIR}/server/key.pem" \
        -out "${CONFIG_DIR}/server/cert.pem" -days 365 -nodes -subj "/CN=n9e"
    chown ${RUN_USER}:${RUN_USER} "${CONFIG_DIR}"/server/*.pem

    # 数据库选择
    read -p "选择数据库类型 [1] SQLite (测试) [2] MySQL (生产): " db_choice
    case $db_choice in
        1)
            DB_TYPE="sqlite"
            DSN="${DATA_DIR}/sqlite/n9e.db?cache=shared&_journal_mode=WAL"
            ;;
        2)
            DB_TYPE="mysql"
            read -p "MySQL 地址 (host:port): " mysql_host
            read -p "MySQL 用户名: " mysql_user
            read -s -p "MySQL 密码: " mysql_pass
            echo
            read -p "数据库名: " mysql_db
            DSN="${mysql_user}:${mysql_pass}@tcp(${mysql_host})/${mysql_db}?charset=utf8mb4&parseTime=True"
            ;;
        *)
            echo "无效选择，使用默认SQLite"
            DB_TYPE="sqlite"
            DSN="${DATA_DIR}/sqlite/n9e.db?cache=shared&_journal_mode=WAL"
            ;;
    esac

    # Redis配置
    read -p "Redis 地址 (host:port): " redis_host
    read -s -p "Redis 密码 (若无则回车): " redis_pass
    echo

    # 主配置模板 (适配 v8.1.0)
    cat << EOF > "${CONFIG_DIR}/config.toml"
[Global]
RunMode = "prod"
LogLevel = "info"
HTTPPort = 17000
HTTPSPort = 17000
CertFile = "${CONFIG_DIR}/server/cert.pem"
KeyFile = "${CONFIG_DIR}/server/key.pem"

[DB]
DBType = "${DB_TYPE}"
DSN = "${DSN}"

[Redis]
Address = "${redis_host}"
Password = "${redis_pass}"
RedisType = "standalone"

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
        config_path="${CONFIG_DIR}/${component}/${component}.toml"
        # 查找配置文件
        local src_config=$(find "${INSTALL_DIR}" -name "${component}.toml" -print -quit)
        
        if [[ -f "${src_config}" ]]; then
            cp -fr "${src_config}" "${config_path}"
            sed -i "s|/opt/n9e|${CONFIG_DIR}|g" "${config_path}"
            chown ${RUN_USER}:${RUN_USER} "${config_path}"
        else
            echo "⚠️ 缺少组件配置: ${component}.toml，创建空文件"
            touch "${config_path}"
            chown ${RUN_USER}:${RUN_USER} "${config_path}"
        fi
    done

    # 初始化数据库
    echo "💾 初始化数据库..."
    # 查找SQL文件
    local sql_file=$(find "${INSTALL_DIR}" -name "n9e.sql" -print -quit)
    
    if [[ -f "${sql_file}" ]]; then
        if [[ "${DB_TYPE}" == "sqlite" ]]; then
            sqlite3 "${DATA_DIR}/sqlite/n9e.db" < "${sql_file}"
            chown ${RUN_USER}:${RUN_USER} "${DATA_DIR}/sqlite/n9e.db"
        else
            echo "请手动执行MySQL初始化:"
            echo "mysql -h${mysql_host%%:*} -P${mysql_host##*:} -u${mysql_user} -p${mysql_pass} ${mysql_db} < ${sql_file}"
            echo "按回车继续..."
            read
        fi
    else
        echo "❌ 未找到SQL初始化文件: n9e.sql"
        exit 1
    fi
}

# 边缘模式配置
function setup_edge_mode() {
    read -p "是否部署边缘模式? (y/N): " edge_choice
    if [[ $edge_choice =~ ^[Yy]$ ]]; then
        echo "🛰️ 配置边缘模式..."
        read -p "中心节点地址 (http://host:port): " center_url
        read -p "边缘引擎名称 (默认: edge): " engine_name
        engine_name=${engine_name:-edge}
        
        mkdir -p "${CONFIG_DIR}/edge"
        cat << EOF > "${CONFIG_DIR}/edge/edge.toml"
[Center]
Address = "${center_url}"
EngineName = "${engine_name}"
EOF
        
        # 创建边缘服务配置
        cat << EOF > /etc/supervisor.d/n9e-edge.conf
[program:n9e-edge]
command=${INSTALL_DIR}/bin/n9e-edge --configs ${CONFIG_DIR}/edge
directory=${INSTALL_DIR}/bin
autostart=true
autorestart=true
startsecs=3
startretries=3
user=${RUN_USER}
redirect_stderr=true
stdout_logfile=${LOG_DIR}/edge.log
stdout_logfile_maxbytes=50MB
stdout_logfile_backups=5
EOF
    fi
}

# 创建 Supervisor 服务配置
function create_supervisor_configs() {
    echo "🛠️ 创建 Supervisor 服务配置..."
    # 创建进程组配置
    for component in server webapi pushgw; do
        cat << EOF > /etc/supervisor.d/n9e-${component}.conf
[program:n9e-${component}]
command=${INSTALL_DIR}/bin/n9e ${component}
directory=${INSTALL_DIR}/bin
autostart=true
autorestart=true
startsecs=3
startretries=3
user=${RUN_USER}
redirect_stderr=true
stdout_logfile=${LOG_DIR}/${component}.log
stdout_logfile_maxbytes=50MB
stdout_logfile_backups=5
environment=N9E_CONFIG_FILE="${CONFIG_DIR}/${component}/${component}.toml"
EOF
    done

    # 边缘模式配置
    setup_edge_mode

    # 重新加载配置
    supervisorctl reread
    supervisorctl update
}

# 防火墙配置
function configure_firewall() {
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        echo "🔥 配置防火墙规则..."
        firewall-cmd --permanent --add-port=17000/tcp
        firewall-cmd --permanent --add-port=19000/tcp  # 边缘模式端口
        firewall-cmd --reload
    else
        echo "⚠️ firewalld 未运行，跳过端口配置"
    fi
}

# 创建管理脚本
function create_management_scripts() {
    echo "📝 创建管理脚本..."
    # 创建启动脚本
    cat << EOF > "${BASE_DIR}/n9e-start.sh"
#!/bin/bash
systemctl start supervisord
supervisorctl start n9e-*
EOF

    # 创建停止脚本
    cat << EOF > "${BASE_DIR}/n9e-stop.sh"
#!/bin/bash
supervisorctl stop n9e-*
systemctl stop supervisord
EOF

    # 创建状态检查脚本
    cat << EOF > "${BASE_DIR}/n9e-status.sh"
#!/bin/bash
systemctl status supervisord
supervisorctl status
EOF

    # 创建日志查看脚本
    cat << EOF > "${BASE_DIR}/n9e-logs.sh"
#!/bin/bash
tail -f ${LOG_DIR}/*.log
EOF

    # 设置权限
    chmod +x "${BASE_DIR}"/*.sh
    chown ${RUN_USER}:${RUN_USER} "${BASE_DIR}"/*.sh
}

# 安装后检查
function post_install_check() {
    echo "🔄 检查服务状态..."
    # 确保服务启动
    if ! systemctl is-active --quiet supervisord; then
        echo "❌ supervisord 服务未运行"
        systemctl status supervisord
        exit 1
    fi
    
    # 检查进程状态
    supervisorctl status
    
    echo "⏳ 等待服务初始化 (15秒)..."
    sleep 15

    local status
    if command -v curl &> /dev/null; then
        # 使用API端点检查服务状态
        status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:17000/api/n9e/self/version")
    else
        echo "⚠️ curl 不可用，跳过 HTTP 检查"
        status="000"
    fi

    if [[ "${status}" == "200" ]]; then
        echo -e "\n✅ 安装成功！"
        echo -e "---------------------------------------------"
        echo -e "控制台地址: \e[34mhttps://$(hostname -I | awk '{print $1}'):17000\e[0m"
        echo -e "初始账号: \e[32mroot\e[0m"
        echo -e "初始密码: \e[32mroot.2020\e[0m"
        echo -e "运行用户: \e[33m${RUN_USER}\e[0m"
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
        echo "❌ 服务检查失败 (HTTP状态码: ${status:-未知})"
        echo "检查日志:"
        echo "Supervisor 日志: /var/log/supervisor/supervisord.log"
        echo "Server 日志: ${LOG_DIR}/server.log"
        exit 1
    fi
}

# 主流程
function main() {
    check_env
    install_deps
    install_system_supervisor
    create_dirs
    download_n9e
    generate_configs
    create_supervisor_configs
    create_management_scripts
    configure_firewall
    post_install_check
    echo -e "\n安装完成，所有组件已安装在 \e[34m${BASE_DIR}\e[0m"
    echo -e "Supervisor 已作为系统服务安装"
}

main