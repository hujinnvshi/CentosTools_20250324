#!/bin/bash

# ClickHouse 单机部署脚本
# 适用于 CentOS 7.9 系统（已配置 YUM 源）
# 作者: 应用开发工程师
# 版本: 2.0
# 日期: $(date +%Y-%m-%d)

set -e  # 遇到错误退出脚本

# 配置参数
CLICKHOUSE_VERSION=""  # 留空以安装最新版本
USER="clickhouse"      # 运行用户

# 配置文件内容
CONFIG_XML_CONTENT='
<?xml version="1.0"?>
<yandex>
    <logger>
        <level>trace</level>
        <log>/var/log/clickhouse-server/clickhouse-server.log</log>
        <errorlog>/var/log/clickhouse-server/clickhouse-server.err.log</errorlog>
        <size>1000M</size>
        <count>10</count>
    </logger>

    <listen_host>0.0.0.0</listen_host>
    
    <http_port>8123</http_port>
    <tcp_port>9000</tcp_port>
    <interserver_http_port>9009</interserver_http_port>

    <path>/var/lib/clickhouse/</path>
    <tmp_path>/var/lib/clickhouse/tmp/</tmp_path>
    <user_files_path>/var/lib/clickhouse/user_files/</user_files_path>

    <users_config>users.xml</users_config>
    <default_profile>default</default_profile>
    <default_database>default</default_database>
    
    <timezone>UTC</timezone>
    <umask>022</umask>
    
    <mark_cache_size>5368709120</mark_cache_size>
    
    <!-- 禁用分布式表功能 -->
    <distributed_ddl>
        <path>/clickhouse/task_queue/ddl</path>
    </distributed_ddl>
    
    <!-- 禁用 ZooKeeper -->
    <!-- <zookeeper> -->
        <!-- <node> -->
            <!-- <host>localhost</host> -->
            <!-- <port>2181</port> -->
        <!-- </node> -->
    <!-- </zookeeper> -->
</yandex>
'

USERS_XML_CONTENT='<?xml version="1.0"?>
<yandex>
    <!-- 用户配置文件 - 简化版本 -->    
    <!-- 用户列表 -->
    <users>
        <!-- 默认用户 -->
        <default>
            <!-- 密码配置 -->
            <password>default</password>
            
            <!-- 允许从任何IP地址连接 -->
            <networks>
                <ip>::/0</ip>
            </networks>
            
            <!-- 使用默认权限配置 -->
            <profile>default</profile>
            <quota>default</quota>
        </default>
        
        <!-- 只读用户 -->
        <readonly>
            <password>readonly</password>
            <networks>
                <ip>::/0</ip>
            </networks>
            <profile>readonly</profile>
            <quota>default</quota>
        </readonly>
    </users>
    
    <!-- 权限配置文件 -->
    <profiles>
        <!-- 默认权限配置 -->
        <default>
            <!-- 最大内存使用限制 -->
            <max_memory_usage>10000000000</max_memory_usage>
            
            <!-- 查询超时时间（秒） -->
            <max_execution_time>300</max_execution_time>
            
            <!-- 允许所有操作 -->
            <readonly>0</readonly>
        </default>
        
        <!-- 只读权限配置 -->
        <readonly>
            <max_memory_usage>5000000000</max_memory_usage>
            <max_execution_time>180</max_execution_time>
            
            <!-- 只允许读操作 -->
            <readonly>1</readonly>
        </readonly>
    </profiles>
    
    <!-- 配额配置 -->
    <quotas>
        <!-- 默认配额 -->
        <default>
            <!-- 每小时配额 -->
            <interval>
                <duration>360极</duration>
                <queries>0</queries>
                <errors>0</errors>
                <result_rows>0</result_rows>
                <read_rows>极</read_rows>
                <execution_time>0</execution_time>
            </interval>
        </default>
    </quotas>
</yandex>'

# 颜色输出函数
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]极NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查是否以root用户运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本必须以root权限运行"
        exit 1
    fi
}

# 检查系统版本
check_os_version() {
    if [[ ! -f /etc/centos-release ]]; then
        print_error "此脚本仅适用于CentOS系统"
        exit 1
    fi
    
    local version=$(grep -oE '[0-9]+\.[0-9]+' /etc/centos-release)
    if [[ "$version" != "7.9" ]]; then
        print_warning "此脚本专为CentOS 7.9设计，当前版本: $version"
    fi
    
    print_info "检测到系统版本: $(cat /etc/centos-release)"
}

# 检查YUM源配置
check_yum_repo() {
    print_step "检查ClickHouse YUM源配置..."
    
    if ! yum repolist enabled | grep -q clickhouse; then
        print_error "未找到启用的ClickHouse YUM源"
        print_info "请确保已正确配置ClickHouse YUM源"
        exit 1
    fi
    
    print_info "ClickHouse YUM源已配置"
}

# 安装ClickHouse
install_clickhouse() {
    print_step "安装ClickHouse..."
    
    # 安装ClickHouse包
    if [[ -n "$CLICKHOUSE_VERSION" ]]; then
        print_info "安装指定版本: $CLICKHOUSE_VERSION"
        yum install -y "clickhouse-server-$CLICKHOUSE_VERSION" "clickhouse-client-$CLICKHOUSE_VERSION"
    else
        print_info "安装最新版本"
        yum install -y clickhouse-server clickhouse-client
    fi
    
    # 获取实际安装的版本
    INSTALLED_VERSION=$(rpm -q clickhouse-server --queryformat '%{VERSION}')
    print_info "已安装版本: $INSTALLED_VERSION"
}

# 配置ClickHouse
configure_clickhouse() {
    print_step "配置ClickHouse..."
    
    # 备份原始配置文件
    local timestamp=$(date +%Y%m%d%H%M%S)
    cp /etc/clickhouse-server/config.xml /etc/clickhouse-server/config.xml.bak.$timestamp
    cp /etc/clickhouse-server/users.xml /etc/clickhouse-server/users.xml.bak.$timestamp
    
    # 写入新的配置文件
    echo "$CONFIG_XML_CONTENT" > /etc/clickhouse-server/config.xml
    echo "$USERS_XML_CONTENT" > /etc/clickhouse-server/users.xml
    
    # 设置正确的权限
    chown clickhouse:clickhouse /etc/clickhouse-server/config.xml
    chown clickhouse:clickhouse /etc/clickhouse-server/users.xml
    chmod 644 /etc/clickhouse-server/config.xml
    chmod 644 /etc/clickhouse-server/users.xml
    
    print_info "ClickHouse配置文件已更新"
}

# 创建必要目录并设置权限
setup_directories() {
    print_step "设置目录权限..."
    
    # 创建必要的目录
    mkdir -p /var/lib/clickhouse/tmp
    mkdir -p /极lib/clickhouse/user_files
    
    # 设置目录权限
    chown -R clickhouse:clickhouse /var/lib/clickhouse/
    chown -R clickhouse:clickhouse /var/log/clickhouse-server/
    chmod -R 755 /var/lib/clickhouse/
    
    print_info "目录权限设置完成"
}

# 配置防火墙
configure_firewall() {
    print_step "配置防火墙..."
    
    # 检查防火墙状态
    if systemctl is-active firewalld >/dev/null 2>&1; then
        # 开放TCP端口（默认9000）和HTTP端口（8123）
        firewall-cmd --permanent --add-port=9000/tcp
        firewall-cmd --permanent --add-port=8123/tcp
        firewall-cmd --reload
        print_info "防火墙已配置，开放端口9000和8123"
    else
        print_warning "防火墙未运行，跳过端口配置"
        print_info "如需外部访问，请手动开放端口: 9000(TCP), 8123(TCP)"
    fi
}

# 启动ClickHouse服务
start_clickhouse() {
    print_step "启动ClickHouse服务..."
    
    # 启动服务
    systemctl enable clickhouse-server
    systemctl start clickhouse-server
    
    # 检查服务状态
    local max_attempts=10
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if systemctl is-active --quiet clickhouse-server; then
            print_info "ClickHouse服务已成功启动"
            return 0
        fi
        print_info "等待服务启动 ($attempt/$max_attempts)..."
        sleep 3
        attempt=$((attempt + 1))
    done
    
    print_error "ClickHouse服务启动失败"
    journalctl -u clickhouse-server --no-pager -n 20
    return 1
}

# 验证安装
verify_installation() {
    print_step "验证ClickHouse安装..."
    
    local max_attempts=10
    local attempt=1
    
    # 等待服务完全启动
    while [[ $attempt -le $max_attempts ]]; do
        if clickhouse-client --user default --password default --query "SELECT version()" 2>/dev/null; then
            print_info "ClickHouse安装验证成功"
            return 0
        fi
        print_info "等待ClickHouse就绪 ($attempt/$max_attempts)..."
        sleep 3
        attempt=$((attempt + 1))
    done
    
    print_error "ClickHouse安装验证失败"
    journalctl -u clickhouse-server --no-pager -n 20
    return 1
}

# 显示连接信息和使用方法
show_connection_info() {
    local ip_address=$(hostname -I | awk '{print $1}')
    
    echo ""
    print_info "ClickHouse 安装完成!"
    echo "=============================================="
    print_info "版本: ${INSTALLED_VERSION}"
    print_info "数据目录: /var/lib/clickhouse/"
    print_info "日志目录: /var/log/clickhouse-server/"
    print_info "配置文件: /etc/clickhouse-server/config.xml"
    echo ""
    print_info "连接信息:"
    print_info "TCP 连接: clickhouse-client -h ${ip_address} --port 9000 --user default --password default"
    print_info "TCP 连接(只读): clickhouse-client -h ${ip_address} --port 9000 --user readonly --password readonly"
    print_info "HTTP连接: curl 'http://${ip_address}:8123?user=default&password=default&query=SELECT%201'"
    print_info "HTTP连接(只读): curl 'http://${ip_address}:8123?user=readonly&password=readonly&query=SELECT%201'"
    echo ""
    print_info "可用用户:"
    print_info "默认用户: default / default (完全权限)"
    print_info "只读用户: readonly / readonly (只读权限)"
    echo ""
    print_info "基本使用方法:"
    print_info "1. 连接数据库: clickhouse-client --user default --password default"
    print_info "2. 创建数据库: CREATE DATABASE mydb;"
    print_info "3. 使用数据库: USE mydb;"
    print_info "4. 创建表: CREATE TABLE mytable (id Int32, name String) ENGINE = MergeTree ORDER BY id;"
    print_info "5. 插入数据: INSERT INTO mytable VALUES (1, 'Alice'), (2, 'Bob');"
    print_info "6. 查询数据: SELECT * FROM mytable;"
    echo ""
    print_info "管理命令:"
    print_info "启动: systemctl start clickhouse-server"
    print_info "停止: systemctl stop clickhouse-server"
    print_info "状态: systemctl status clickhouse-server"
    print_info "日志: journalctl -u clickhouse-server -f"
    print_info "错误日志: tail -f /var/log/clickhouse-server/clickhouse-server.err.log"
    print_info "标准日志: tail -f /var/log/clickhouse-server/clickhouse-server.log"
    echo "=============================================="
}

# 主函数
main() {
    print_info "开始安装 ClickHouse"
    echo ""
    
    # 记录开始时间
    local start_time=$(date +%s)
    
    # 执行安装步骤
    check_root
    check_os_version
    check_yum_repo
    install_clickhouse
    configure_clickhouse
    setup_directories
    configure_firewall
    start_clickhouse
    verify_installation
    show_connection_info
    
    # 计算安装时间
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    print_info "安装完成，总耗时: ${duration} 秒"
}

# 异常处理
trap 'print_error "脚本执行被中断"; exit 1' INT TERM

# 执行主函数
main "$@"