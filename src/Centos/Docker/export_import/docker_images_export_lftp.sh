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

# 检查镜像完整性
check_image_integrity() {
    local IMAGE=$1
    local FILENAME=$2
    
    # 计算原始镜像的 SHA256 校验和
    local ORIGINAL_SHA256=$(docker inspect --format='{{.Id}}' "$IMAGE" | cut -d':' -f2)
    
    # 计算导出文件的 SHA256 校验和
    local EXPORTED_SHA256=$(gunzip -c "$FILENAME" | sha256sum | cut -d' ' -f1)
    
    # 比较校验和
    if [ "$ORIGINAL_SHA256" = "$EXPORTED_SHA256" ]; then
        return 0
    else
        return 1
    fi
}

# 导出镜像
log "开始导出 Docker 镜像..."
for IMAGE in $IMAGES; do
    FILENAME=$(echo "$IMAGE" | tr '/' '_' | tr ':' '_').tar.gz
    if [ -f "$BACKUP_DIR/$FILENAME" ]; then
        log "检查已存在镜像的完整性: $BACKUP_DIR/$FILENAME"
        if check_image_integrity "$IMAGE" "$BACKUP_DIR/$FILENAME"; then
            log "镜像 $IMAGE 已存在且完整性验证通过，跳过导出"
            continue
        else
            log "镜像 $IMAGE 完整性验证失败，重新导出"
        fi
    fi
    
    log "正在导出镜像: $IMAGE -> $BACKUP_DIR/$FILENAME"
    docker save "$IMAGE" | gzip > "$BACKUP_DIR/$FILENAME" || error "导出镜像 $IMAGE 失败"
    
    # 验证新导出镜像的完整性
    if check_image_integrity "$IMAGE" "$BACKUP_DIR/$FILENAME"; then
        log "镜像 $IMAGE 导出成功并通过完整性验证"
    else
        error "镜像 $IMAGE 导出后完整性验证失败"
    fi
done

# 拷贝到远程服务器
REMOTE_IP="172.16.48.191"
REMOTE_USER="ftp_user1"
REMOTE_PASSWORD="Secsmart#612"

log "正在将镜像拷贝到远程服务器: $REMOTE_IP..."
lftp -u $REMOTE_USER,$REMOTE_PASSWORD $REMOTE_IP << EOF
set xfer:clobber off
set xfer:log yes
set xfer:log-file $BACKUP_DIR/transfer.log
mirror -R --only-newer --continue --parallel=3 "$BACKUP_DIR" /
quit
EOF

log "Docker 镜像导出完成！备份路径: $BACKUP_DIR"