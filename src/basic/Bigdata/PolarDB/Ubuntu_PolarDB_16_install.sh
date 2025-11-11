#!/bin/bash

# PolarDB for PostgreSQL 16 一键安装脚本
# 版本: 16.1.0.0
# 适用于 Ubuntu 24.04
# 支持与 PolarDB 15 并行安装

# 检查是否为 root 用户
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 sudo 或以 root 用户运行此脚本"
    exit 1
fi

# 安装信息 - PolarDB 16 版本
VERSION="16.1.0.0"
DEB_FILE="PolarDB_16.1.0.0-b4011ae4-ubuntu24.04_amd64.deb"
DOWNLOAD_URL="https://github.com/ApsaraDB/PolarDB-for-PostgreSQL/releases/download/v16.1.0.0/$DEB_FILE"

# PolarDB 16 特定配置
INSTANCE_NAME="polardb16"  # 实例名称，与 15 区分
PORT="38529"               # 使用不同端口，避免冲突
DATA_DIR="/var/lib/polardb16/data"  # 不同的数据目录
SERVICE_NAME="polardb16"   # 不同的服务名称

# 检查是否已安装 PolarDB 15
check_existing_installation() {
    echo "检查现有 PolarDB 安装..."
    
    # 检查 PolarDB 15 服务
    if systemctl is-active --quiet polardb 2>/dev/null; then
        echo "✓ 检测到正在运行的 PolarDB 15 实例"
        POLARDB15_PORT=$(sudo -u polar psql -d postgres -p 38528 -t -c "SHOW port;" 2>/dev/null | tr -d ' ' || echo "38528")
        echo "  - PolarDB 15 运行端口: $POLARDB15_PORT"
    fi
    
    # 检查 PolarDB 16 是否已安装
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo "❌ PolarDB 16 实例已在运行，请先停止或卸载"
        exit 1
    fi
    
    if [ -d "$DATA_DIR" ] && [ -f "$DATA_DIR/postgresql.conf" ]; then
        echo "⚠️  检测到现有的 PolarDB 16 数据目录: $DATA_DIR"
        read -p "是否要覆盖现有数据？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "安装中止"
            exit 1
        fi
        # 备份现有数据
        backup_dir="/var/backups/polardb16_$(date +%Y%m%d_%H%M%S)"
        echo "备份现有数据到: $backup_dir"
        mv "$DATA_DIR" "$backup_dir" 2>/dev/null || true
    fi
}

# 安装依赖
install_dependencies() {
    echo "安装依赖库..."
    apt update
    apt install -y wget lsb-release libreadline-dev zlib1g-dev libssl-dev libicu-dev libxml2-dev libxslt1-dev libperl-dev
    
    # 检查是否已安装 PolarDB 15 的依赖，避免重复安装
    echo "依赖检查完成"
}

# 下载 PolarDB 16
download_polardb() {
    # 检查是否已存在 DEB 文件
    if [ -f "$DEB_FILE" ]; then
        echo "检测到本地已存在 $DEB_FILE 文件，跳过下载"
        return 0
    fi

    echo "下载 PolarDB $VERSION..."
    if ! wget "$DOWNLOAD_URL"; then
        echo "尝试备用下载源..."
        # 尝试其他镜像源
        MIRROR_URL="https://mirrors.aliyun.com/polardb/$DEB_FILE"
        if ! wget "$MIRROR_URL"; then
            echo "下载失败，请检查网络连接或下载链接是否有效"
            exit 1
        fi
    fi

    if [ ! -f "$DEB_FILE" ]; then
        echo "下载失败，文件不存在"
        exit 1
    fi
}

# 安装 PolarDB 16
install_polardb() {
    echo "安装 PolarDB $VERSION..."
    
    # 检查是否已安装
    if dpkg -l | grep -q "polardb"; then
        echo "⚠️  检测到已安装的 PolarDB 包，尝试升级安装..."
        dpkg -i --force-overwrite "$DEB_FILE" || {
            echo "安装失败，尝试修复依赖..."
            apt -f install -y
        }
    else
        dpkg -i "$DEB_FILE"
    fi
    
    # 解决可能的依赖问题
    apt -f install -y
}

# 查找 PolarDB 安装路径
find_polardb_home() {
    echo "查找 PolarDB $VERSION 安装位置..."
    
    POLARDB_PATHS=(
        "/usr/local/polardb16"
        "/usr/local/polardb"
        "/opt/polardb16" 
        "/opt/polardb"
        "/usr/polardb16"
        "/usr/polardb"
        "/polardb16"
        "/polardb"
    )

    POLARDB_HOME=""
    for path in "${POLARDB_PATHS[@]}"; do
        if [ -d "$path" ] && [ -f "$path/bin/initdb" ]; then
            # 检查版本是否匹配
            if [ -f "$path/bin/postgres" ]; then
                version_output=$("$path/bin/postgres" --version 2>/dev/null || echo "")
                if echo "$version_output" | grep -q "16"; then
                    POLARDB_HOME="$path"
                    echo "✓ 找到 PolarDB 16 安装目录: $POLARDB_HOME"
                    break
                fi
            fi
        fi
    done

    if [ -z "$POLARDB_HOME" ]; then
        echo "警告: 未找到 PolarDB 16 安装目录，尝试搜索二进制文件..."
        # 尝试查找二进制文件（优先找 16 版本）
        INITDB_PATH=$(find / -name "initdb" -type f 2>/dev/null | xargs -I {} sh -c '{} --version 2>/dev/null | grep -q "16" && echo {}' | head -1)
        if [ -n "$INITDB_PATH" ]; then
            POLARDB_HOME=$(dirname $(dirname "$INITDB_PATH"))
            echo "通过二进制文件找到 PolarDB 16 目录: $POLARDB_HOME"
        else
            echo "错误: 无法找到 PolarDB 16 安装目录"
            echo "尝试查找所有 PolarDB 相关目录:"
            find / -name "*polar*" -type d 2>/dev/null | head -10
            exit 1
        fi
    fi
}

# 配置环境变量
setup_environment() {
    # 添加 PolarDB 16 到 PATH（不覆盖 15 的配置）
    if ! grep -q "$POLARDB_HOME/bin" /etc/profile; then
        echo "export POLARDB16_HOME=$POLARDB_HOME" >> /etc/profile
        echo "export PATH=\$PATH:$POLARDB_HOME/bin" >> /etc/profile
    fi
    
    # 创建别名便于区分版本
    if ! grep -q "alias psql16" /etc/profile; then
        echo "alias psql16='$POLARDB_HOME/bin/psql -p $PORT'" >> /etc/profile
        echo "alias pg_ctl16='$POLARDB_HOME/bin/pg_ctl -D $DATA_DIR'" >> /etc/profile
    fi
    
    source /etc/profile
}

# 创建专用用户（可选）
create_user() {
    # 使用现有的 polar 用户，或创建新用户
    if ! id "polar" &>/dev/null; then
        echo "创建 polar 用户..."
        useradd -r -m -s /bin/bash polar
    else
        echo "使用现有 polar 用户"
    fi
    
    # 可选：为 PolarDB 16 创建专用用户
    if ! id "polar16" &>/dev/null; then
        read -p "是否为 PolarDB 16 创建专用用户 (polar16)? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            useradd -r -m -s /bin/bash polar16
            echo "已创建 polar16 用户"
        fi
    fi
}

# 初始化数据库集群
init_database() {
    echo "创建数据目录..."
    mkdir -p "$DATA_DIR"
    chown polar:polar "$DATA_DIR"
    
    echo "初始化 PolarDB 16 数据库集群..."
    
    # 检查数据目录是否非空
    if [ "$(ls -A $DATA_DIR 2>/dev/null)" ]; then
        echo "⚠️  数据目录非空，尝试备份现有数据..."
        backup_dir="/var/backups/${INSTANCE_NAME}_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "/var/backups"
        cp -r "$DATA_DIR" "$backup_dir" 2>/dev/null || true
        echo "现有数据已备份到: $backup_dir"
        
        # 清空数据目录
        rm -rf "$DATA_DIR"/*
    fi
    
    # 初始化数据库
    sudo -u polar $POLARDB_HOME/bin/initdb -D "$DATA_DIR" -U polar --pwprompt

    if [ $? -eq 0 ]; then
        echo "✓ 数据库初始化成功"
    else
        echo "尝试无密码初始化..."
        sudo -u polar $POLARDB_HOME/bin/initdb -D "$DATA_DIR" -U polar
        if [ $? -ne 0 ]; then
            echo "❌ 数据库初始化失败"
            exit 1
        fi
    fi
}

# 配置数据库
configure_database() {
    echo "配置 PolarDB 16..."
    
    # 修改 postgresql.conf
    CONFIG_FILE="$DATA_DIR/postgresql.conf"
    
    # 备份原始配置
    cp "$CONFIG_FILE" "$CONFIG_FILE.backup"
    
    # 应用配置
    sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$CONFIG_FILE"
    sed -i "s/#port = 5432/port = $PORT/" "$CONFIG_FILE"
    
    # PolarDB 16 特定优化配置
    cat >> "$CONFIG_FILE" << EOF

# ===========================================
# PolarDB 16 特定配置
# ===========================================
max_connections = 1000
shared_buffers = 128MB
dynamic_shared_memory_type = posix
max_wal_size = 2GB
min_wal_size = 1GB
log_timezone = 'Asia/Shanghai'
datestyle = 'iso, ymd'
timezone = 'Asia/Shanghai'
lc_messages = 'en_US.UTF-8'
lc_monetary = 'en_US.UTF-8'
lc_numeric = 'en_US.UTF-8'
lc_time = 'en_US.UTF-8'
default_text_search_config = 'pg_catalog.english'

# 性能优化
random_page_cost = 1.1
effective_io_concurrency = 200
maintenance_io_concurrency = 200

# 监控和日志
log_destination = 'stderr'
logging_collector = on
log_directory = '/var/log/polardb16'
log_filename = 'postgresql-%a.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_min_duration_statement = 1000

# PolarDB 特定配置
# shared_preload_libraries = 'polar_vfs'
EOF

    # 配置客户端认证
    AUTH_FILE="$DATA_DIR/pg_hba.conf"
    cat >> "$AUTH_FILE" << EOF

# ===========================================
# PolarDB 16 客户端认证配置
# ===========================================
# 允许远程连接
host    all             all             0.0.0.0/0               md5
host    all             all             ::/0                    md5

# 复制连接（用于高可用）
host    replication     all             0.0.0.0/0               md5
host    replication     all             ::/0                    md5
EOF
}

# 创建 systemd 服务
create_service() {
    echo "创建 systemd 服务..."
    
    # 创建日志目录
    mkdir -p "/var/log/polardb16"
    chown polar:polar "/var/log/polardb16"
    
    # 创建服务文件
    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=PolarDB for PostgreSQL 16
After=network.target
Wants=network.target

[Service]
Type=forking
User=polar
Group=polar
Environment=PGDATA=$DATA_DIR
Environment=PGPORT=$PORT
OOMScoreAdjust=-1000

ExecStart=$POLARDB_HOME/bin/pg_ctl -D $DATA_DIR -l /var/log/polardb16/postgresql.log -w start
ExecStop=$POLARDB_HOME/bin/pg_ctl -D $DATA_DIR -m fast -w stop
ExecReload=$POLARDB_HOME/bin/pg_ctl -D $DATA_DIR reload
TimeoutSec=300

# 资源限制
LimitNOFILE=65536
LimitNPROC=65536

# 安全设置
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$DATA_DIR /var/log/polardb16

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载 systemd
    systemctl daemon-reload
}

# 启动和测试服务
start_service() {
    echo "启动 PolarDB 16 服务..."
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
    
    # 等待服务启动
    for i in {1..30}; do
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            break
        fi
        sleep 1
    done
    
    # 检查服务状态
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "✓ PolarDB 16 服务运行正常"
        
        # 等待数据库完全启动
        sleep 3
        
        # 测试连接
        if sudo -u polar $POLARDB_HOME/bin/psql -p $PORT -d postgres -c "SELECT version();" &>/dev/null; then
            echo "✓ 数据库连接测试成功"
        else
            echo "⚠️  数据库连接测试失败，但服务正在运行"
        fi
    else
        echo "❌ PolarDB 16 服务启动失败"
        journalctl -u "$SERVICE_NAME" -n 20 --no-pager
        echo "尝试手动启动..."
        sudo -u polar $POLARDB_HOME/bin/pg_ctl -D "$DATA_DIR" -l "/var/log/polardb16/postgresql.log" start
    fi
}

# 创建默认数据库和用户
setup_defaults() {
    echo "创建默认数据库和用户..."
    
    # 等待数据库就绪
    sleep 5
    
    # 创建数据库
    sudo -u polar $POLARDB_HOME/bin/createdb -p $PORT "polardb16" 2>/dev/null || 
    sudo -u polar $POLARDB_HOME/bin/psql -p $PORT -d postgres -c "CREATE DATABASE polardb16;" 2>/dev/null || 
    echo "⚠️  无法创建数据库 polardb16"
    
    # 创建管理员用户
    sudo -u polar $POLARDB_HOME/bin/psql -p $PORT -d postgres -c \
        "CREATE USER polaradmin16 WITH PASSWORD 'PolarDB16@123';" 2>/dev/null || 
    echo "⚠️  无法创建用户 polaradmin16"
    
    # 设置权限
    sudo -u polar $POLARDB_HOME/bin/psql -p $PORT -d postgres -c \
        "ALTER USER polaradmin16 WITH SUPERUSER;" 2>/dev/null || 
    echo "⚠️  无法设置超级用户权限"
    
    # 为 polaradmin16 用户授予数据库权限
    sudo -u polar $POLARDB_HOME/bin/psql -p $PORT -d postgres -c \
        "GRANT ALL PRIVILEGES ON DATABASE polardb16 TO polaradmin16;" 2>/dev/null || true
}

# 显示安装信息
show_installation_info() {
    echo ""
    echo "================================================"
    echo " PolarDB for PostgreSQL 16 安装完成！"
    echo "================================================"
    echo ""
    echo "安装信息："
    echo "版本: PolarDB $VERSION"
    echo "安装目录: $POLARDB_HOME"
    echo "数据目录: $DATA_DIR"
    echo "日志目录: /var/log/polardb16"
    echo "服务名称: $SERVICE_NAME"
    echo ""
    echo "连接信息："
    echo "主机: localhost"
    echo "端口: $PORT"
    echo "超级用户: polar"
    echo "应用用户: polaradmin16"
    echo "密码: PolarDB16@123"
    echo "默认数据库: polardb16"
    echo ""
    echo "管理命令："
    echo "启动: systemctl start $SERVICE_NAME"
    echo "停止: systemctl stop $SERVICE_NAME"
    echo "重启: systemctl restart $SERVICE_NAME"
    echo "状态: systemctl status $SERVICE_NAME"
    echo "日志: journalctl -u $SERVICE_NAME -f"
    echo ""
    echo "数据库连接示例："
    echo "本地连接: $POLARDB_HOME/bin/psql -U polar -p $PORT -d postgres"
    echo "应用连接: $POLARDB_HOME/bin/psql -U polaradmin16 -p $PORT -d polardb16"
    echo ""
    echo "多版本管理："
    echo "PolarDB 15: psql -U polar -p 38528"
    echo "PolarDB 16: psql16 -U polar -p $PORT"
    echo ""
    if systemctl is-active --quiet polardb; then
        echo "当前运行的实例："
        echo "✓ PolarDB 15 (端口: 38528)"
        echo "✓ PolarDB 16 (端口: $PORT)"
    fi
    echo ""
    echo "重要提示："
    echo "1. 请立即修改默认密码！"
    echo "2. 生产环境请配置适当的 pg_hba.conf 规则"
    echo "3. 定期备份重要数据"
    echo "================================================"
}

# 主安装流程
main() {
    echo "开始安装 PolarDB for PostgreSQL 16"
    echo "================================================"
    
    # 检查现有安装
    check_existing_installation
    
    # 执行安装步骤
    install_dependencies
    download_polardb
    install_polardb
    find_polardb_home
    setup_environment
    create_user
    init_database
    configure_database
    create_service
    start_service
    setup_defaults
    
    # 显示最终信息
    show_installation_info
    
    # 显示服务状态
    echo ""
    echo "服务状态："
    systemctl status "$SERVICE_NAME" --no-pager
    
    # 测试连接
    echo ""
    echo "连接测试："
    if sudo -u polar $POLARDB_HOME/bin/psql -p $PORT -d postgres -c "SELECT version();" &>/dev/null; then
        echo "✓ PolarDB 16 连接测试成功"
        sudo -u polar $POLARDB_HOME/bin/psql -p $PORT -d postgres -c "SELECT version();" | head -5
    else
        echo "❌ 连接测试失败"
    fi
}

# 卸载功能（可选）
uninstall() {
    echo "你确定要卸载 PolarDB 16 吗？这将删除所有数据！"
    read -p "输入 'YES' 确认卸载: " -r
    if [[ $REPLY != "YES" ]]; then
        echo "卸载已取消"
        exit 0
    fi
    
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    systemctl daemon-reload
    
    # 备份数据而不是立即删除
    if [ -d "$DATA_DIR" ]; then
        backup_dir="/var/backups/polardb16_uninstall_$(date +%Y%m%d_%H%M%S)"
        echo "备份数据到: $backup_dir"
        mv "$DATA_DIR" "$backup_dir" 2>/dev/null || true
    fi
    
    # 删除日志目录
    rm -rf "/var/log/polardb16" 2>/dev/null || true
    
    echo "PolarDB 16 已卸载（数据已备份）"
}

# 参数处理
case "${1:-}" in
    uninstall|remove)
        uninstall
        ;;
    help|--help|-h)
        echo "用法: $0 [command]"
        echo ""
        echo "命令:"
        echo "  (无参数)   安装 PolarDB 16"
        echo "  uninstall 卸载 PolarDB 16"
        echo "  help      显示此帮助信息"
        echo ""
        echo "此脚本将在已安装 PolarDB 15 的系统上并行安装 PolarDB 16"
        echo "PolarDB 16 将使用不同的端口($PORT)和数据目录"
        ;;
    *)
        main
        ;;
esac