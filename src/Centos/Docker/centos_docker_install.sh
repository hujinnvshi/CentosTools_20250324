#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 日志文件
LOG_FILE="/var/log/docker_install_$(date +%Y%m%d_%H%M%S).log"

# 输出函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a ${LOG_FILE}
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a ${LOG_FILE}
}

handle_error() {
    log_error "错误发生在第 $2 行，错误代码：$1"
    exit 1
}

# 在脚本开头添加
set -e  # 遇到错误立即退出
trap 'handle_error $? $LINENO' ERR

# 检查系统版本
check_system() {
    log_info "检查系统版本..."
    if ! grep -qs "CentOS Linux release 7" /etc/redhat-release; then
        log_error "此脚本仅支持 CentOS 7.x"
        exit 1
    fi
}

# 安装依赖
install_deps() {
    log_info "安装依赖包..."
    yum install -y yum-utils device-mapper-persistent-data lvm2
}

# 配置 Docker 目录
setup_docker_dirs() {
    log_info "创建 Docker 目录..."
    mkdir -p /data/docker/images || log_error "创建目录失败"
    mkdir -p /etc/docker || log_error "创建配置目录失败"
    chmod 755 /data/docker/images || log_error "设置目录权限失败"
}

# 配置 Docker 仓库
setup_docker_repo() {
    log_info "配置 Docker 仓库..."
    yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
}

# 配置 Docker daemon
setup_docker_daemon() {
    log_info "配置 Docker daemon..."
    cat > /etc/docker/daemon.json << EOF
{
    "registry-mirrors": [
        "https://mirror.ccs.tencentyun.com",
        "https://registry.docker-cn.com",
        "https://docker.mirrors.ustc.edu.cn",
        "https://dockerhub.azk8s.cn"
    ],
    "data-root": "/data/docker/images",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "exec-opts": ["native.cgroupdriver=systemd"],
    "live-restore": true
}
EOF
}

# 安装 Docker
install_docker() {
    log_info "安装 Docker..."
    yum install -y docker-ce docker-ce-cli containerd.io
}

# 启动 Docker
start_docker() {
    log_info "启动 Docker 服务..."
    
    # 重置 Docker 服务状态
    systemctl reset-failed docker.service || log_error "重置 Docker 服务状态失败"
    
    # 启用并启动服务
    systemctl enable docker || log_error "Docker 服务启用失败"
    systemctl start docker || {
        log_error "Docker 服务启动失败"
        log_info "获取详细错误信息..."
        journalctl -u docker.service -n 50 --no-pager >> ${LOG_FILE}
        systemctl status docker -l >> ${LOG_FILE}
        exit 1
    }
    
    # 等待服务完全启动
    sleep 5
    
    # 验证服务状态
    if ! systemctl is-active docker >/dev/null 2>&1; then
        log_error "Docker 服务未能正常运行"
        log_info "服务状态："
        systemctl status docker -l >> ${LOG_FILE}
        exit 1
    fi
}

# 验证安装
verify_install() {
    log_info "验证 Docker 安装..."
    if ! docker version &>/dev/null; then
        log_error "Docker 安装失败"
        exit 1
    fi
}

show_completion_info() {
    log_info "Docker 安装信息："
    docker_version=$(docker --version 2>/dev/null) || log_error "无法获取 Docker 版本"
    docker_status=$(systemctl status docker 2>/dev/null | grep Active) || log_error "无法获取 Docker 状态"
    
    log_info "- 版本：${docker_version}"
    log_info "- 存储路径：/data/docker/images"
    log_info "- 配置文件：/etc/docker/daemon.json"
    log_info "- 服务状态：${docker_status}"
}

# 主函数
main() {
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 用户执行此脚本"
        exit 1
    fi

    # 执行安装步骤
    check_system
    install_deps
    setup_docker_dirs
    setup_docker_repo
    setup_docker_daemon
    install_docker
    start_docker
    verify_install
    show_completion_info
}

# 执行主函数
main