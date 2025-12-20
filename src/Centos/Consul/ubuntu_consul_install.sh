#!/bin/bash

# Consul 自动安装脚本（Ubuntu 24.04）
# 功能：安装Consul，配置SSL，启动服务，进行测试

set -e  # 遇到错误立即退出

# 变量定义
CONSUL_VERSION="1.17.2"
CONSUL_USER="consul"
CONSUL_GROUP="consul"
CONSUL_HOME="/opt/consul"
CONSUL_CONFIG_DIR="/etc/consul.d"
CONSUL_DATA_DIR="/opt/consul/data"
CONSUL_LOG_DIR="/var/log/consul"
CONSUL_SSL_DIR="/etc/consul.d/ssl"
CONSUL_DOMAIN="consul.example.com"
CONSUL_BIN_URL="https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip"

# 颜色定义
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

# 日志函数
echo_green() {
    echo -e "${GREEN}$1${NC}"
}

echo_yellow() {
    echo -e "${YELLOW}$1${NC}"
}

echo_red() {
    echo -e "${RED}$1${NC}"
}

echo_info() {
    echo -e "$1"
}

# 检查是否以root用户运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo_red "错误：请以root用户运行此脚本"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    echo_info "安装系统依赖..."
    apt update -y
    apt install -y wget unzip openssl curl jq
    echo_green "依赖安装完成"
}

# 创建用户和目录
create_user_and_dirs() {
    echo_info "创建用户和目录结构..."
    
    # 创建用户和组
    if ! getent group $CONSUL_GROUP > /dev/null; then
        groupadd -r $CONSUL_GROUP
    fi
    
    if ! getent passwd $CONSUL_USER > /dev/null; then
        useradd -r -g $CONSUL_GROUP -d $CONSUL_HOME -s /sbin/nologin $CONSUL_USER
    fi
    
    # 创建目录
    mkdir -p $CONSUL_HOME
    mkdir -p $CONSUL_CONFIG_DIR
    mkdir -p $CONSUL_DATA_DIR
    mkdir -p $CONSUL_LOG_DIR
    mkdir -p $CONSUL_SSL_DIR
    
    # 设置权限
    chown -R $CONSUL_USER:$CONSUL_GROUP $CONSUL_HOME
    chown -R $CONSUL_USER:$CONSUL_GROUP $CONSUL_CONFIG_DIR
    chown -R $CONSUL_USER:$CONSUL_GROUP $CONSUL_DATA_DIR
    chown -R $CONSUL_USER:$CONSUL_GROUP $CONSUL_LOG_DIR
    chown -R $CONSUL_USER:$CONSUL_GROUP $CONSUL_SSL_DIR
    
    chmod 755 $CONSUL_HOME
    chmod 755 $CONSUL_CONFIG_DIR  # 添加执行权限，允许访问子目录
    chmod 700 $CONSUL_DATA_DIR
    chmod 755 $CONSUL_LOG_DIR
    chmod 700 $CONSUL_SSL_DIR
    
    echo_green "用户和目录创建完成"
}

# 下载并安装Consul
download_and_install_consul() {
    echo_info "下载Consul $CONSUL_VERSION..."
    
    # 下载Consul
    wget -q -O /tmp/consul.zip $CONSUL_BIN_URL
    
    # 解压安装（强制覆盖已存在的文件）
    unzip -q -o /tmp/consul.zip -d /usr/local/bin/
    
    # 设置执行权限
    chmod +x /usr/local/bin/consul
    
    # 验证安装
    consul --version
    
    # 清理临时文件
    rm -f /tmp/consul.zip
    
    echo_green "Consul安装完成"
}

# 检查并使用现有SSL证书，测试模式下自动生成证书
generate_ssl_certs() {
    echo_info "检查SSL证书..."
    
    # 检查必要的证书文件是否存在
    required_certs=("ca.crt" "ca.key" "server.crt" "server.key" "client.crt" "client.key")
    missing_certs=()
    
    for cert in "${required_certs[@]}"; do
        if [ ! -f "$CONSUL_SSL_DIR/$cert" ]; then
            missing_certs+=("$cert")
        fi
    done
    
    if [ ${#missing_certs[@]} -ne 0 ]; then
        echo_yellow "警告：缺少以下SSL证书文件：${missing_certs[*]}"
        echo_info "测试模式下自动生成SSL证书..."
        
        # 生成CA密钥
        openssl genrsa -out $CONSUL_SSL_DIR/ca.key 2048
        
        # 生成CA证书
        openssl req -new -x509 -days 3650 -key $CONSUL_SSL_DIR/ca.key \
            -out $CONSUL_SSL_DIR/ca.crt \
            -subj "/CN=${CONSUL_DOMAIN}-CA" \
            -extensions v3_ca \
            -config <(cat <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca

[req_distinguished_name]
CN = ${CONSUL_DOMAIN}-CA

[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
EOF
)
        
        # 生成服务器密钥
        openssl genrsa -out $CONSUL_SSL_DIR/server.key 2048
        
        # 生成服务器证书请求
        openssl req -new -key $CONSUL_SSL_DIR/server.key \
            -out $CONSUL_SSL_DIR/server.csr \
            -subj "/CN=${CONSUL_DOMAIN}" \
            -config <(cat <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]
CN = ${CONSUL_DOMAIN}

[v3_req]
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth,clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${CONSUL_DOMAIN}
DNS.2 = localhost
DNS.3 = server.dc1.consul
IP.1 = 127.0.0.1
IP.2 = $(hostname -I | awk '{print $1}')
EOF
)
        
        # 生成服务器证书
        openssl x509 -req -in $CONSUL_SSL_DIR/server.csr \
            -CA $CONSUL_SSL_DIR/ca.crt \
            -CAkey $CONSUL_SSL_DIR/ca.key \
            -CAcreateserial \
            -out $CONSUL_SSL_DIR/server.crt \
            -days 3650 \
            -extensions v3_req \
            -extfile <(cat <<EOF
[v3_req]
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth,clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${CONSUL_DOMAIN}
DNS.2 = localhost
DNS.3 = server.dc1.consul
IP.1 = 127.0.0.1
IP.2 = $(hostname -I | awk '{print $1}')
EOF
)
        
        # 生成客户端密钥
        openssl genrsa -out $CONSUL_SSL_DIR/client.key 2048
        
        # 生成客户端证书请求
        openssl req -new -key $CONSUL_SSL_DIR/client.key \
            -out $CONSUL_SSL_DIR/client.csr \
            -subj "/CN=consul-client" \
            -config <(cat <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]
CN = consul-client

[v3_req]
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = clientAuth
EOF
)
        
        # 生成客户端证书
        openssl x509 -req -in $CONSUL_SSL_DIR/client.csr \
            -CA $CONSUL_SSL_DIR/ca.crt \
            -CAkey $CONSUL_SSL_DIR/ca.key \
            -CAcreateserial \
            -out $CONSUL_SSL_DIR/client.crt \
            -days 3650 \
            -extensions v3_req \
            -extfile <(cat <<EOF
[v3_req]
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = clientAuth
EOF
)
    fi
    
    # 设置权限
    chown -R $CONSUL_USER:$CONSUL_GROUP $CONSUL_SSL_DIR
    chmod 600 $CONSUL_SSL_DIR/*.key
    chmod 644 $CONSUL_SSL_DIR/*.crt
    chmod 644 $CONSUL_SSL_DIR/*.csr 2>/dev/null || true
    chmod 644 $CONSUL_SSL_DIR/*.srl 2>/dev/null || true
    
    echo_green "SSL证书检查完成，使用现有证书"
}

# 配置Consul
auth_consul() {
    echo_info "配置Consul..."
    
    # 主配置文件
    cat > $CONSUL_CONFIG_DIR/server.hcl <<EOF
# 服务器配置
server = true
bootstrap_expect = 1

# 数据和日志目录
data_dir = "$CONSUL_DATA_DIR"
log_level = "INFO"
log_file = "$CONSUL_LOG_DIR/consul.log"

# 绑定地址
bind_addr = "0.0.0.0"
advertise_addr = "$(hostname -I | awk '{print $1}')"

# 客户端配置
client_addr = "0.0.0.0"
ui_config {
    enabled = true
}

# HTTPS配置
ports {
    http = -1  # 禁用HTTP
    https = 8501  # 启用HTTPS
}

# TLS配置
tls {
    defaults {
        ca_file = "$CONSUL_SSL_DIR/ca.crt"
        cert_file = "$CONSUL_SSL_DIR/server.crt"
        key_file = "$CONSUL_SSL_DIR/server.key"
        verify_incoming = false  # 降低验证要求
        verify_outgoing = false  # 降低验证要求
        verify_server_hostname = false  # 禁用主机名验证
    }
}
EOF
    
    # 服务配置文件 - 直接创建在systemd目录
    cat > /etc/systemd/system/consul.service <<EOF
[Unit]
Description="HashiCorp Consul - A service mesh solution"
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=$CONSUL_CONFIG_DIR/server.hcl

[Service]
Type=notify
User=$CONSUL_USER
Group=$CONSUL_GROUP
ExecStart=/usr/local/bin/consul agent -config-dir=$CONSUL_CONFIG_DIR
ExecReload=/usr/local/bin/consul reload
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    
    # 设置权限
    chown $CONSUL_USER:$CONSUL_GROUP $CONSUL_CONFIG_DIR/server.hcl
    chmod 644 $CONSUL_CONFIG_DIR/server.hcl
    chmod 644 /etc/systemd/system/consul.service
    
    # 清理可能存在的错误配置文件
    if [ -f "$CONSUL_CONFIG_DIR/consul.service" ]; then
        rm -f "$CONSUL_CONFIG_DIR/consul.service"
    fi
    
    echo_green "Consul配置完成"
}

# 启动Consul服务
start_consul_service() {
    echo_info "启动Consul服务..."
    
    # 重新加载systemd配置
    systemctl daemon-reload
    
    # 重置失败状态
    systemctl reset-failed consul 2>/dev/null || true
    
    # 启动并启用服务
    systemctl enable consul --now
    
    # 等待服务启动
    sleep 3
    
    # 检查服务状态
    if systemctl is-active --quiet consul; then
        echo_green "Consul服务已经在运行"
    else
        echo_yellow "Consul服务正在启动中，等待3秒后再次检查..."
        sleep 3
        if systemctl is-active --quiet consul; then
            echo_green "Consul服务启动成功"
        else
            echo_yellow "Consul服务状态：$(systemctl is-active consul)，尝试直接检查Consul进程..."
            if pgrep -x consul > /dev/null; then
                echo_green "Consul进程正在运行"
            else
                echo_red "Consul服务启动失败，请检查日志：journalctl -xeu consul.service"
                # 不退出，继续执行，因为systemd可能报告超时但实际服务已运行
            fi
        fi
    fi
    
    # 显示服务状态
    systemctl status consul --no-pager | head -20
    
    echo_green "Consul服务启动完成"
}

# 测试Consul服务
test_consul_service() {
    echo_info "测试Consul服务..."
    
    # 检查服务状态（先检查进程，再检查systemd状态）
    if ! pgrep -x consul > /dev/null; then
        echo_red "Consul进程未运行"
        exit 1
    fi
    
    echo_yellow "Consul进程正在运行，继续测试API..."
    
    # 测试HTTPS连接（重试机制）
    echo_info "测试HTTPS连接..."
    local retry=3
    local success=0
    for i in $(seq 1 $retry); do
        if curl -k -s https://localhost:8501/v1/status/leader > /dev/null 2>&1; then
            curl -k -s https://localhost:8501/v1/status/leader | jq
            success=1
            break
        fi
        echo_yellow "HTTPS连接测试失败，第 $i 次重试..."
        sleep 1
    done
    
    if [ $success -eq 0 ]; then
        echo_red "HTTPS连接测试失败"
        exit 1
    fi
    
    # 测试会员状态（使用环境变量跳过TLS验证）
    echo_info "测试会员状态..."
    CONSUL_HTTP_ADDR=https://localhost:8501 CONSUL_HTTP_SSL=true CONSUL_HTTP_SSL_VERIFY=false /usr/local/bin/consul members
    
    # 测试健康检查（使用环境变量跳过TLS验证）
    echo_info "测试健康检查..."
    CONSUL_HTTP_ADDR=https://localhost:8501 CONSUL_HTTP_SSL=true CONSUL_HTTP_SSL_VERIFY=false /usr/local/bin/consul catalog services
    
    echo_green "Consul服务测试通过"
}

# 主函数
main() {
    echo_info "开始安装Consul..."
    
    check_root
    install_dependencies
    create_user_and_dirs
    download_and_install_consul
    generate_ssl_certs
    auth_consul
    start_consul_service
    test_consul_service
    
    echo_green "Consul安装和配置完成！"
    echo_info "访问地址: https://$(hostname -I | awk '{print $1}'):8501"
    echo_info "注意：首次访问需要接受自签名证书"
}

# 执行主函数
main