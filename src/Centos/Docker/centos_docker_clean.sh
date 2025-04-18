#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 日志文件
LOG_FILE="/var/log/docker_uninstall_$(date +%Y%m%d_%H%M%S).log"

# 输出函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a ${LOG_FILE}
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a ${LOG_FILE}
}

# 停止所有容器
stop_containers() {
    log_info "停止所有运行中的容器..."
    docker ps -aq | xargs -r docker stop
}

# 删除所有容器
remove_containers() {
    log_info "删除所有容器..."
    docker ps -aq | xargs -r docker rm -f
}

# 删除所有镜像
remove_images() {
    log_info "删除所有 Docker 镜像..."
    docker images -q | xargs -r docker rmi -f
}

# 删除所有卷
remove_volumes() {
    log_info "删除所有 Docker 卷..."
    docker volume ls -q | xargs -r docker volume rm -f
}

# 删除所有网络
remove_networks() {
    log_info "删除所有自定义网络..."
    docker network ls -q | xargs -r docker network rm
}

# 停止 Docker 服务
stop_docker() {
    log_info "停止 Docker 服务..."
    systemctl stop docker
    systemctl disable docker
}

# 卸载 Docker
uninstall_docker() {
    log_info "卸载 Docker 相关包..."
    yum remove -y docker-ce docker-ce-cli containerd.io docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine
}

# 清理 Docker 文件
cleanup_files() {
    log_info "清理 Docker 相关文件..."
    rm -rf /data/docker
    rm -rf /etc/docker
    rm -rf /var/lib/docker
    rm -rf /var/run/docker
    rm -f /etc/yum.repos.d/docker-ce.repo
}

# 主函数
main() {
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 用户执行此脚本"
        exit 1
    fi

    log_info "开始清理 Docker..."

    # 检查 Docker 是否在运行
    if systemctl is-active docker &>/dev/null; then
        stop_containers
        remove_containers
        remove_images
        remove_volumes
        remove_networks
    fi

    stop_docker
    uninstall_docker
    cleanup_files

    log_info "Docker 清理完成！"
    log_info "清理日志：${LOG_FILE}"
    log_info "如需重新安装，请执行 centos_docker_install.sh"
}

# 执行主函数
main