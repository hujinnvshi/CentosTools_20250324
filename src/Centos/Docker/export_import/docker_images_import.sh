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

# 定义备份路径
BACKUP_DIR="/data/docker/images_copy"

if [ ! -d "$BACKUP_DIR" ]; then
    error "备份目录不存在: $BACKUP_DIR"
fi

# 获取备份文件列表
IMAGES=$(find "$BACKUP_DIR" -type f -name '*.tar.gz')

if [ -z "$IMAGES" ]; then
    error "未找到需要导入的 Docker 镜像"
fi

# 导入镜像
log "开始导入 Docker 镜像..."
for IMAGE in $IMAGES; do
    log "正在导入镜像: $IMAGE"
    docker load -i "$IMAGE" || error "导入镜像 $IMAGE 失败"
    log "镜像 $IMAGE 导入成功"
done

# 验证导入
log "验证导入的 Docker 镜像..."
docker images | grep -v 'kubesphere\|other-keyword'

log "Docker 镜像导入完成！"