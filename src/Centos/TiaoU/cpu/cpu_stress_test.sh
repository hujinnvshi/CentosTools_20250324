#!/bin/bash
# CPU压力测试脚本 v2.3
# 功能：执行渐进式CPU压力测试并生成CSV报告
# 输出：包含上下文切换详细数据的CSV文件
# 使用方法：./cpu_stress_test.sh [测试时长(分钟)] [最大线程倍数]

set -eo pipefail

# 配置参数
TEST_DURATION=${1:-5}          # 默认测试5分钟
MAX_THREAD_MULTIPLIER=${2:-4}  # 默认测试到4倍CPU核心数
CSV_REPORT="cpu_stress_report_$(date +%Y%m%d_%H%M%S).csv"
TEMP_DATA_FILE="/tmp/cpu_stress_data.csv"
STRESS_PID=""

# 初始化环境
init_test() {
    echo "🛠️ 初始化测试环境..."
    trap cleanup EXIT ERR
    
    # 检查并安装必要工具
    local required_tools=(stress-ng mpstat pidstat)
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            echo "安装$tool..."
            sudo yum install -y epel-release && \
            sudo yum install -y stress-ng sysstat
            break
        fi
    done
    
    # 创建CSV文件头
    echo "Timestamp,Threads,Load1,Load5,Load15,CPU%,Sys%,User%,TotalCtxSw,VoluntaryCtxSw,NonVoluntaryCtxSw,Processes" > "$CSV_REPORT"
}

# 清理函数
cleanup() {
    echo "🧹 清理测试环境..."
    if [[ -n "$STRESS_PID" ]]; then
        if kill -0 "$STRESS_PID" &>/dev/null; then
            pkill -P "$STRESS_PID"
            kill "$STRESS_PID" &>/dev/null
        fi
    fi
    [[ -f "$TEMP_DATA_FILE" ]] && rm -f "$TEMP_DATA_FILE"
}

# 获取上下文切换详情
get_context_switches() {
    # 获取系统级上下文切换
    local total_ctx=$(awk '/^ctxt/ {print $2}' /proc/stat)
    
    # 获取自愿/非自愿切换（需要pidstat）
    local ctx_stats=$(pidstat -w -p $STRESS_PID 1 1 | awk '/Average/ {print $4,$5}' | tr ' ' ',')
    
    echo "$total_ctx,$ctx_stats"
}

# 执行单次压力测试
run_stress_test() {
    local threads=$1
    local duration=$2
    
    echo "🔥 开始测试: ${threads}线程 ${duration}分钟"
    
    # 启动stress-ng
    stress-ng --cpu "$threads" --timeout "${duration}m" --metrics-brief &
    STRESS_PID=$!
    [[ -z "$STRESS_PID" ]] && { echo "❌ 无法启动stress-ng"; exit 1; }
    
    # 监控循环
    local start_time=$(date +%s)
    while [[ $(($(date +%s) - start_time)) -lt $((duration * 60)) ]]; do
        # 收集系统指标
        local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
        local loadavg=($(awk '{print $1,$2,$3}' /proc/loadavg))
        local cpu_stats=($(mpstat 1 1 | awk '/Average/ {print $3,$5,$12}' || echo "0 0 0"))
        local processes=$(ps -e --no-headers | wc -l)
        
        # 获取上下文切换详情
        local ctx_switches=$(get_context_switches)
        
        # 记录数据到CSV
        echo "$timestamp,$threads,${loadavg[0]},${loadavg[1]},${loadavg[2]},${cpu_stats[0]},${cpu_stats[1]},${cpu_stats[2]},$ctx_switches,$processes" >> "$CSV_REPORT"
        sleep 1
    done
    
    wait "$STRESS_PID" || echo "⚠️ stress-ng非正常退出"
    STRESS_PID=""
}

# 主执行流程
main() {
    init_test
    
    local cpu_cores=$(nproc)
    echo "🖥️ 检测到系统有 ${cpu_cores} 个逻辑CPU核心"
    
    # 渐进式压力测试
    for multiplier in $(seq 1 "$MAX_THREAD_MULTIPLIER"); do
        local threads=$(( cpu_cores * multiplier ))
        local duration=$(( TEST_DURATION / MAX_THREAD_MULTIPLIER ))
        
        run_stress_test "$threads" "$duration"
    done
    
    echo "✅ 测试完成，CSV报告已生成: $(pwd)/$CSV_REPORT"
    echo "=== 报告预览 ==="
    column -t -s ',' "$CSV_REPORT" | head -5
    echo "..."
    cleanup
}

main "$@"