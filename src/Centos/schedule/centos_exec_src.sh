#!/usr/bin/env bash

# 循环运行脚本任意次数的工具
# 优化版本：增强健壮性、错误处理和日志记录
# 用法: ./loop-runner.sh <脚本路径> <循环次数> [参数1] [参数2] ...

set -euo pipefail  # 启用严格模式：出错退出、未定义变量报错、管道错误处理

# 显示帮助信息
show_help() {
    echo "循环运行脚本工具 - 优化版"
    echo "用法: $0 <脚本路径> <循环次数> [参数...]"
    echo "选项:"
    echo "  -q, --quiet    静默模式（不显示进度）"
    echo "  -i, --interval <秒> 设置循环间隔时间（默认0.5秒）"
    echo "  -l, --log <文件> 将输出记录到日志文件"
    echo "  -h, --help     显示此帮助信息"
    exit 0
}

# 初始化变量
QUIET_MODE=false
INTERVAL=0.5
LOG_FILE=""

# 解析命令行选项
while [[ $# -gt 0 ]]; do
    case "$1" in
        -q|--quiet)
            QUIET_MODE=true
            shift
            ;;
        -i|--interval)
            INTERVAL="$2"
            if ! [[ "$INTERVAL" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                echo "错误：间隔时间必须是数字" >&2
                exit 1
            fi
            shift 2
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "错误：未知选项 $1" >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# 检查剩余参数数量
if [[ $# -lt 2 ]]; then
    echo "错误：缺少参数" >&2
    show_help
fi

SCRIPT="$1"     # 要运行的脚本
TIMES="$2"      # 循环次数
shift 2         # 移除前两个参数，剩余的是要传递给脚本的参数

# 检查脚本是否存在且可读
if [[ ! -f "$SCRIPT" ]]; then
    echo "错误：脚本 '$SCRIPT' 不存在" >&2
    exit 1
elif [[ ! -r "$SCRIPT" ]]; then
    echo "错误：脚本 '$SCRIPT' 不可读" >&2
    exit 1
fi

# 检查循环次数是否为有效正整数
if ! [[ "$TIMES" =~ ^[0-9]+$ ]]; then
    echo "错误：循环次数必须是正整数" >&2
    exit 1
elif [[ "$TIMES" -lt 1 ]]; then
    echo "错误：循环次数必须大于0" >&2
    exit 1
fi

# 设置日志输出
exec_log() {
    if [[ -n "$LOG_FILE" ]]; then
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi
}

# 显示带时间戳的消息
log_message() {
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $*"
}

# 主运行函数
run_script() {
    local exit_code=0
    local success_count=0
    local fail_count=0
    
    # 初始化日志
    exec_log
    
    # 开始信息
    if ! "$QUIET_MODE"; then
        log_message "开始运行: 脚本 '$SCRIPT' 将执行 $TIMES 次"
        log_message "=========================================="
    fi
    
    # 主循环
    for ((i=1; i<=TIMES; i++)); do
        if ! "$QUIET_MODE"; then
            log_message "▶▶ 第 $i/$TIMES 次运行"
            log_message "------------------------"
        fi
        
        # 运行脚本并捕获退出状态
        if bash "$SCRIPT" "$@"; then
            exit_code=0
            ((success_count++))
        else
            exit_code=$?
            ((fail_count++))
        fi
        
        if ! "$QUIET_MODE"; then
            log_message "退出代码: $exit_code"
            log_message "------------------------"
        fi
        
        # 处理失败情况
        if [[ $exit_code -ne 0 ]]; then
            if ! "$QUIET_MODE"; then
                log_message "⚠️ 警告：脚本在第 $i 次运行时失败（退出代码 $exit_code）"
                read -rp "是否继续运行？(y/n) " -n 1 response
                echo
                if [[ ! "$response" =~ ^[Yy]$ ]]; then
                    log_message "⏹ 用户终止运行"
                    break
                fi
            else
                log_message "⚠️ 警告：脚本在第 $i 次运行时失败（退出代码 $exit_code），继续运行..."
            fi
        fi
        
        # 添加间隔（最后一次不等待）
        if [[ $i -lt $TIMES ]] && [[ $INTERVAL != "0" ]]; then
            sleep "$INTERVAL"
        fi
    done
    
    # 结束信息
    if ! "$QUIET_MODE"; then
        log_message "=========================================="
        log_message "✅ 完成：总共运行 $TIMES 次"
        log_message "  成功: $success_count 次"
        log_message "  失败: $fail_count 次"
        
        if [[ $fail_count -gt 0 ]]; then
            log_message "⚠️ 警告：有 $fail_count 次运行失败"
            exit 1
        fi
    fi
}

# 执行主函数
run_script