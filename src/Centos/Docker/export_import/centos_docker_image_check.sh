#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

    # 检查目标目录是否存在
    if [ ! -d "$IMAGES_DIR" ]; then
        error "镜像目录不存在: $IMAGES_DIR"
    fi

    # 检查磁盘空间
    local available_space=$(df -P "$IMAGES_DIR" | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 5242880 ]; then  # 5GB in KB
        error "磁盘空间不足，至少需要 5GB 可用空间"
    fi
}

# 清理函数
cleanup() {
    log "正在清理..."
    # 清理所有未标记的镜像
    docker images --quiet --filter "dangling=true" | xargs -r docker rmi &>/dev/null
    # 清理检查点文件
    [ -f "$CHECKPOINT_FILE" ] && rm -f "$CHECKPOINT_FILE"
    exit "${1:-0}"
}

# 设置信号处理
trap 'cleanup 1' INT TERM

# 检查镜像完整性
check_image_integrity() {
    local image_file=$1
    local report_file=$2
    local current=$3
    local total=$4
    
    log "正在检查 [$current/$total]: $(basename "$image_file")"
    echo "检查镜像文件: $image_file" >> "$report_file"
    
    # 检查文件大小 - 根据操作系统使用不同的 stat 命令
    local file_size
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        file_size=$(stat -f %z "$image_file")
    else
        # Linux
        file_size=$(stat -c %s "$image_file")
    fi

    if [ -z "$file_size" ] || [ "$file_size" -eq 0 ]; then
        echo "镜像文件大小为0或无法读取: $(basename "$image_file")" >> "$report_file"
        warn "镜像文件大小为0或无法读取: $(basename "$image_file")"
        return 1
    fi

    # 计算文件大小（MB）
    local size_in_mb=$(echo "scale=2; $file_size/1024/1024" | bc)
    echo "文件大小: ${size_in_mb}MB" >> "$report_file"

    # 设置超时时间（10分钟）
    local TIMEOUT=600
    
    # 使用 timeout 命令运行 docker load
    if timeout $TIMEOUT docker load -i "$image_file" &>> "$report_file"; then
        # 获取最近加载的镜像信息
        local image_info=$(docker images --format "{{.ID}} {{.Repository}}:{{.Tag}}" | head -n 1)
        if [ -n "$image_info" ]; then
            echo "镜像加载成功，信息: $image_info" >> "$report_file"
            log "镜像加载成功: $(basename "$image_file")"
            # 删除测试用的镜像
            docker rmi $(echo $image_info | awk '{print $1}') &>> "$report_file" || {
                error "删除测试镜像失败: $image_info"
                return 1
            }
            return 0
        fi
    fi

    # 处理失败情况
    local exit_code=$?
    if [ $exit_code -eq 124 ]; then
        echo "镜像加载超时" >> "$report_file"
        warn "镜像加载超时: $(basename "$image_file")"
    else
        echo "镜像加载失败，错误码: $exit_code" >> "$report_file"
        warn "镜像加载失败: $(basename "$image_file")"
    fi
    return 1
}

# 主函数
main() {
    # 定义变量
    IMAGES_DIR="/data/docker/images_copy"
    REPORT_FILE="$IMAGES_DIR/docker_images_check.rpt"
    CHECKPOINT_FILE="$IMAGES_DIR/.check_point"
    
    # 检查环境
    check_environment
    
    # 创建新的报告文件
    echo "Docker 镜像检查报告" > "$REPORT_FILE"
    echo "检查时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
    echo "系统信息：" >> "$REPORT_FILE"
    echo "操作系统：$(uname -s)" >> "$REPORT_FILE"
    echo "Docker 版本：$(docker --version)" >> "$REPORT_FILE"
    echo "----------------------------------------" >> "$REPORT_FILE"
    
    # 检查报告文件权限
    if [ -f "$REPORT_FILE" ] && [ ! -w "$REPORT_FILE" ]; then
        error "无法写入报告文件: $REPORT_FILE"
    fi

    # 计算总文件数
    local total_files=0
    for ext in "tar.gz" "tar"; do
        for image_file in "$IMAGES_DIR"/*.$ext; do
            if [ -f "$image_file" ] && [ "$image_file" != "$IMAGES_DIR/*.$ext" ]; then
                ((total_files++))
            fi
        done
    done
    
    if [ $total_files -eq 0 ]; then
        error "未找到任何镜像文件"
    fi
    
    log "共发现 $total_files 个镜像文件待检查"
    
    # 检查所有镜像文件
    local current_file=0
    local success_count=0
    local fail_count=0
    
    # 如果存在检查点文件，从上次中断处继续
    if [ -f "$CHECKPOINT_FILE" ]; then
        current_file=$(cat "$CHECKPOINT_FILE")
        log "从检查点继续: $current_file"
    fi
    
    # 开始时间
    local start_time=$(date +%s)
    
    # 修改文件查找逻辑
    for ext in "tar.gz" "tar"; do
        for image_file in "$IMAGES_DIR"/*.$ext; do
            # 检查文件是否存在且不是通配符本身
            if [ -f "$image_file" ] && [ "$image_file" != "$IMAGES_DIR/*.$ext" ]; then
                ((current_file++))
                
                # 如果是从检查点继续，跳过已检查的文件
                if [ -f "$CHECKPOINT_FILE" ] && [ $current_file -le $(cat "$CHECKPOINT_FILE") ]; then
                    continue
                fi
                
                echo "" >> "$REPORT_FILE"
                if check_image_integrity "$image_file" "$REPORT_FILE" "$current_file" "$total_files"; then
                    ((success_count++))
                else
                    ((fail_count++))
                fi
                
                # 保存检查点
                echo "$current_file" > "$CHECKPOINT_FILE"
                
                # 计算进度和预估剩余时间
                local progress=$((current_file * 100 / total_files))
                local current_time=$(date +%s)
                local elapsed=$((current_time - start_time))
                local rate=$(echo "scale=2; $current_file/$elapsed" | bc)
                local remaining=$((total_files - current_file))
                local eta=$(echo "scale=0; $remaining/$rate" | bc)
                
                log "当前进度: $current_file/$total_files ($progress%) (成功: $success_count, 失败: $fail_count, 预计剩余时间: ${eta}秒)"
            fi
        done
    done
    
    # 计算总耗时
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    
    # 输出统计信息
    echo "" >> "$REPORT_FILE"
    echo "----------------------------------------" >> "$REPORT_FILE"
    echo "检查完成！" >> "$REPORT_FILE"
    echo "总耗时: $total_time 秒" >> "$REPORT_FILE"
    echo "成功: $success_count" >> "$REPORT_FILE"
    echo "失败: $fail_count" >> "$REPORT_FILE"
    
    # 输出报告位置
    log "检查完成！报告已保存到: $REPORT_FILE"
    log "总耗时: $total_time 秒"
    
    # 清理并退出
    cleanup 0
}

# 执行主函数
main