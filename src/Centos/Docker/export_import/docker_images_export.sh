#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 日志函数
log() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 检查 Docker 是否安装
if ! command -v docker &>/dev/null; then
    error "Docker 未安装，请先安装 Docker"
fi

# 定义目标路径
BACKUP_DIR="/data/docker/images_copy"
mkdir -p "$BACKUP_DIR" || error "无法创建备份目录: $BACKUP_DIR"

# 获取镜像列表（排除特定镜像）
IMAGES=$(docker images | grep -v 'kubesphere\|other-keyword' | awk 'NR>1 {print $1":"$2}')

if [ -z "$IMAGES" ]; then
    error "未找到需要备份的 Docker 镜像"
fi

# 导出镜像
log "开始导出 Docker 镜像..."
for IMAGE in $IMAGES; do
    FILENAME=$(echo "$IMAGE" | tr '/' '_' | tr ':' '_').tar.gz
    log "正在导出镜像: $IMAGE -> $BACKUP_DIR/$FILENAME"
    docker save "$IMAGE" | gzip > "$BACKUP_DIR/$FILENAME" || error "导出镜像 $IMAGE 失败"
done

# 拷贝到远程服务器
REMOTE_IP="172.16.48.191"
REMOTE_USER="root"
REMOTE_PASSWORD="Secsmart#612"

log "正在将镜像拷贝到远程服务器: $REMOTE_IP..."
scp -r "$BACKUP_DIR" "$REMOTE_USER@$REMOTE_IP:/data/docker/" || error "拷贝镜像到远程服务器失败"

log "Docker 镜像导出完成！备份路径: $BACKUP_DIR"