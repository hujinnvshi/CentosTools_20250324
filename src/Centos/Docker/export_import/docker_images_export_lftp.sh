#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 设置全局路径变量
BASE_DIR="/data/docker"                           # 基础目录
BACKUP_DIR="${BASE_DIR}/images_copy"             # 备份目录
TRANSFER_LOG="${BACKUP_DIR}/transfer.log"        # 传输日志
CHECKPOINT_FILE="${BACKUP_DIR}/.export_point"    # 导出检查点

# FTP服务器配置
REMOTE_IP="172.16.48.191"
REMOTE_USER="ftp_user1"
REMOTE_PASSWORD="Secsmart#612"

# 日志函数
log() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# 检查系统环境
check_environment() {
    # 检查 Docker 是否安装
    if ! command -v docker &>/dev/null; then
        error "Docker 未安装，请先安装 Docker"
    fi

    # 检查 Docker 服务是否运行
    if ! docker info &>/dev/null; then
        error "Docker 服务未运行，请先启动 Docker 服务"
    fi

    # 检查 lftp 是否安装
    if ! command -v lftp &>/dev/null; then
        log "lftp 未安装，yum 安装 lftp"
        yum install -y lftp
    fi

    # 检查目标目录
    mkdir -p "$BACKUP_DIR" || error "无法创建备份目录: $BACKUP_DIR"

    # 检查磁盘空间
    local available_space=$(df -P "$BACKUP_DIR" | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 5242880 ]; then  # 5GB in KB
        error "磁盘空间不足，至少需要 5GB 可用空间"
    fi
}

# 清理函数
cleanup() {
    log "正在清理..."
    [ -f "$CHECKPOINT_FILE" ] && rm -f "$CHECKPOINT_FILE"
    exit "${1:-0}"
}

# 设置信号处理
trap 'cleanup 1' INT TERM

# 检查导出文件完整性
check_export_integrity() {
    local FILENAME=$1
    local TEMP_DIR=$(mktemp -d)
    
    # 尝试解压文件
    if tar -tzf "$FILENAME" &>/dev/null; then
        rm -rf "$TEMP_DIR"
        return 0
    else
        rm -rf "$TEMP_DIR"
        warn "文件 $FILENAME 解压测试失败"
        return 1
    fi
}

# 上传到FTP服务器
upload_to_ftp() {
    log "正在将镜像上传到FTP服务器: $REMOTE_IP..."
    
    # 创建 lftp 配置
    local lftp_cmd="set xfer:clobber off;
                    set xfer:log yes;
                    set xfer:log-file $TRANSFER_LOG;
                    set net:max-retries 3;
                    set net:reconnect-interval-base 5;
                    set net:timeout 600;
                    set ftp:ssl-allow false;
                    mirror -R --only-newer --continue --parallel=5 \"$BACKUP_DIR\" .;
                    quit"
    
    if ! lftp -u "$REMOTE_USER,$REMOTE_PASSWORD" "$REMOTE_IP" -e "$lftp_cmd"; then
        warn "FTP上传失败，请检查网络连接和FTP服务器状态"
        return 1
    fi
    return 0
}

# 主函数
main() {
    # 检查环境
    check_environment
    
    # 获取镜像列表（排除特定镜像）
    local IMAGES=$(docker images | grep -v 'kubesphere\|other-keyword' | awk 'NR>1 {print $1":"$2}')
    
    if [ -z "$IMAGES" ]; then
        error "未找到需要备份的 Docker 镜像"
    fi
    
    # 开始时间
    local start_time=$(date +%s)
    local total_images=$(echo "$IMAGES" | wc -l)
    local current=0
    local success_count=0
    local fail_count=0
    
    log "共发现 $total_images 个镜像待导出"
    
    # 导出镜像
    for IMAGE in $IMAGES; do
        ((current++))
        local FILENAME=$(echo "$IMAGE" | tr '/' '_' | tr ':' '_').tar.gz
        local progress=$((current * 100 / total_images))
        
        log "正在处理 [$current/$total_images] ($progress%): $IMAGE"
        
        if [ -f "$BACKUP_DIR/$FILENAME" ]; then
            log "检查已存在镜像的完整性: $BACKUP_DIR/$FILENAME"
            if check_export_integrity "$BACKUP_DIR/$FILENAME"; then
                log "镜像 $IMAGE 已存在且完整性验证通过，跳过导出"
                ((success_count++))
                continue
            else
                warn "镜像 $IMAGE 完整性验证失败，重新导出"
            fi
        fi
        
        log "正在导出镜像: $IMAGE -> $BACKUP_DIR/$FILENAME"
        if docker save "$IMAGE" | gzip > "$BACKUP_DIR/$FILENAME"; then
            if check_export_integrity "$BACKUP_DIR/$FILENAME"; then
                log "镜像 $IMAGE 导出成功并通过完整性验证"
                ((success_count++))
            else
                warn "镜像 $IMAGE 导出后完整性验证失败"
                ((fail_count++))
                rm -f "$BACKUP_DIR/$FILENAME"
            fi
        else
            warn "导出镜像 $IMAGE 失败"
            ((fail_count++))
            rm -f "$BACKUP_DIR/$FILENAME"
        fi
        
        # 计算进度和预估剩余时间
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local rate=$(echo "scale=2; $current/$elapsed" | bc)
        local remaining=$((total_images - current))
        local eta=$(echo "scale=0; $remaining/$rate" | bc)
        
        log "当前进度: $current/$total_images ($progress%) (成功: $success_count, 失败: $fail_count, 预计剩余时间: ${eta}秒)"
    done
    
    # 计算总耗时
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    
    # 输出导出统计信息
    log "----------------------------------------"
    log "镜像导出完成！"
    log "总耗时: $total_time 秒"
    log "成功: $success_count"
    log "失败: $fail_count"
    log "备份路径: $BACKUP_DIR"
    
    # 上传到FTP服务器
    if [ $success_count -gt 0 ]; then
        if upload_to_ftp; then
            log "FTP上传完成"
        else
            error "FTP上传失败"
        fi
    else
        warn "没有成功导出的镜像，跳过FTP上传"
    fi
    
    # 清理并退出
    cleanup 0
}

# 执行主函数
main