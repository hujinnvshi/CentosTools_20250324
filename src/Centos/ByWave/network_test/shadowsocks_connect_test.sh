#!/bin/bash
# Shadowsocks 节点连通性测试脚本 (优化版)
# 版本: 2.0
# 作者: 网络性能专家
# 最后更新: 2023-10-15

# 配置参数
CONFIG_DIR="/etc/shadowsocks-libev/configs"
TEST_URLS=(
    "https://www.google.com"
    "https://www.youtube.com"
    "https://www.github.com"
)
TIMEOUT=15
REPORT_FILE="ss_connectivity_report_$(date +%Y%m%d_%H%M%S).csv"
SUMMARY_FILE="ss_summary_report_$(date +%Y%m%d_%H%M%S).txt"
TMP_DIR=$(mktemp -d)
PORT_BASE=10000
MAX_RETRIES=2
LOG_LEVEL="info"  # debug, info, warning, error

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # 无颜色

# 日志函数
log() {
    local level=$1
    local message=$2
    local color=$3
    
    if [[ "$LOG_LEVEL" == "debug" ]] || 
       [[ "$LOG_LEVEL" == "info" && "$level" != "debug" ]] || 
       [[ "$LOG_LEVEL" == "warning" && ! "$level" =~ debug|info ]] || 
       [[ "$LOG_LEVEL" == "error" && "$level" == "error" ]]; then
        
        case $level in
            debug) echo -e "${CYAN}[DEBUG] $message${NC}" ;;
            info) echo -e "${color:-$BLUE}[INFO] $message${NC}" ;;
            warning) echo -e "${YELLOW}[WARNING] $message${NC}" ;;
            error) echo -e "${RED}[ERROR] $message${NC}" ;;
        esac
    fi
}

# 清理函数
cleanup() {
    log info "🛑 清理临时进程..." $PURPLE
    pkill -f "ss-local -c $CONFIG_DIR"
    rm -rf "$TMP_DIR"
    log info "✅ 清理完成" $PURPLE
}
trap cleanup EXIT

# 测试单个URL
test_url() {
    local url=$1
    local port=$2
    local retry=$3
    
    local domain=$(echo "$url" | awk -F/ '{print $3}')
    local result=""
    local http_code=""
    local latency=99999
    
    for ((attempt=1; attempt<=retry; attempt++)); do
        log debug "测试 $domain (尝试 $attempt/$retry)..." $CYAN
        
        # 使用curl测试
        start_time=$(date +%s%N)
        http_code=$(curl -x "socks5h://127.0.0.1:$port" -I -s -o /dev/null -w "%{http_code}" "$url" --max-time $TIMEOUT 2>/dev/null)
        end_time=$(date +%s%N)
        latency=$(( (end_time - start_time) / 1000000 ))  # 毫秒
        
        # 检查结果
        if [[ "$http_code" =~ ^2|3 ]]; then
            result="成功"
            break
        elif [[ -z "$http_code" ]]; then
            http_code="超时"
            result="失败"
        else
            result="失败"
        fi
        
        # 如果不是最后一次尝试，等待后重试
        if [[ $attempt -lt $retry ]]; then
            sleep 1
        fi
    done
    
    echo "$result:$http_code:$latency"
}

# 测试节点连通性
test_node_connectivity() {
    local config=$1
    local port=$2
    local node_name=$(basename "$config" .json)
    local results=()
    local pid=""
    
    # 启动 Shadowsocks 代理
    log info "🚀 启动节点: $node_name..." $BLUE
    ss-local -c "$config" -l $port -u -v > "$TMP_DIR/$node_name.log" 2>&1 &
    pid=$!
    
    # 等待代理启动
    local wait_time=0
    while [[ $wait_time -lt 5 ]]; do
        if ss -tuln | grep -q ":$port"; then
            break
        fi
        sleep 1
        ((wait_time++))
    done
    
    if ! ss -tuln | grep -q ":$port"; then
        log error "❌ 代理启动失败 (端口 $port)" $RED
        kill $pid 2>/dev/null
        return 1
    fi
    
    # 测试每个URL
    for url in "${TEST_URLS[@]}"; do
        local domain=$(echo "$url" | awk -F/ '{print $3}')
        log info "  测试 $domain ... " $CYAN
        
        # 测试URL
        local test_result=$(test_url "$url" "$port" $MAX_RETRIES)
        IFS=':' read -r result http_code latency <<< "$test_result"
        
        # 记录结果
        results+=("$domain:$result:$http_code:$latency")
        
        # 打印结果
        if [[ "$result" == "成功" ]]; then
            log info "成功 (HTTP $http_code, ${latency}ms)" $GREEN
        else
            log info "失败 (HTTP $http_code, ${latency}ms)" $RED
        fi
    done
    
    # 停止代理
    kill $pid
    wait $pid 2>/dev/null
    
    # 返回结果数组
    echo "${results[@]}"
    return 0
}

# 生成详细报告
generate_detailed_report() {
    local report_file=$1
    local config_files=("$@")
    
    # CSV 头部
    echo "节点名称,测试网站,状态,状态码,延迟(ms)" > "$report_file"
    
    # 添加所有结果
    for config in "${config_files[@]}"; do
        local node_name=$(basename "$config" .json)
        
        if [[ -f "$TMP_DIR/$node_name.results" ]]; then
            while IFS= read -r line; do
                IFS=':' read -r domain result http_code latency <<< "$line"
                echo "$node_name,$domain,$result,$http_code,$latency" >> "$report_file"
            done < "$TMP_DIR/$node_name.results"
        else
            for url in "${TEST_URLS[@]}"; do
                local domain=$(echo "$url" | awk -F/ '{print $3}')
                echo "$node_name,$domain,启动失败,,99999" >> "$report_file"
            done
        fi
    done
}

# 生成摘要报告
generate_summary_report() {
    local summary_file=$1
    local detailed_report=$2
    
    # 汇总统计
    local total_nodes=0
    local success_nodes=0
    local google_success=0
    local youtube_success=0
    local github_success=0
    
    # 读取详细报告
    while IFS=',' read -r node domain status code latency; do
        # 跳过标题行
        [[ "$node" == "节点名称" ]] && continue
        
        # 统计节点总数
        if [[ "$domain" == "${TEST_URLS[0]##*/}" ]]; then
            ((total_nodes++))
            if [[ "$status" == "成功" ]]; then
                ((success_nodes++))
            fi
        fi
        
        # 统计各网站成功率
        case $domain in
            www.google.com)
                [[ "$status" == "成功" ]] && ((google_success++))
                ;;
            www.youtube.com)
                [[ "$status" == "成功" ]] && ((youtube_success++))
                ;;
            www.github.com)
                [[ "$status" == "成功" ]] && ((github_success++))
                ;;
        esac
    done < "$detailed_report"
    
    # 计算成功率
    local node_success_rate=0
    [[ $total_nodes -gt 0 ]] && node_success_rate=$((success_nodes * 100 / total_nodes))
    
    local google_rate=0
    [[ $total_nodes -gt 0 ]] && google_rate=$((google_success * 100 / total_nodes))
    
    local youtube_rate=0
    [[ $total_nodes -gt 0 ]] && youtube_rate=$((youtube_success * 100 / total_nodes))
    
    local github_rate=0
    [[ $total_nodes -gt 0 ]] && github_rate=$((github_success * 100 / total_nodes))
    
    # 生成报告
    cat > "$summary_file" <<EOF
===== Shadowsocks 节点测试摘要报告 =====
测试时间: $(date)
测试节点数: $total_nodes
成功启动节点: $success_nodes ($node_success_rate%)
------------------------------
网站连通性成功率:
  Google:   $google_success/$total_nodes ($google_rate%)
  YouTube:  $youtube_success/$total_nodes ($youtube_rate%)
  GitHub:   $github_success/$total_nodes ($github_rate%)
------------------------------
推荐节点:
EOF

    # 添加最佳节点
    local best_node=""
    local best_latency=99999
    
    while IFS=',' read -r node domain status code latency; do
        [[ "$node" == "节点名称" ]] && continue
        [[ "$domain" != "www.google.com" ]] && continue
        
        if [[ "$status" == "成功" && $latency -lt $best_latency ]]; then
            best_latency=$latency
            best_node=$node
        fi
    done < "$detailed_report"
    
    if [[ -n "$best_node" ]]; then
        echo "  ✅ $best_node (延迟: ${best_latency}ms)" >> "$summary_file"
    else
        echo "  ❌ 无可用节点" >> "$summary_file"
    fi
    
    echo "------------------------------" >> "$summary_file"
    echo "详细报告: $detailed_report" >> "$summary_file"
}

# 主函数
main() {
    log info "===== Shadowsocks 节点连通性测试 =====" $PURPLE
    log info "开始时间: $(date)" $PURPLE
    
    # 检查配置目录
    if [ ! -d "$CONFIG_DIR" ]; then
        log error "❌ 配置目录不存在: $CONFIG_DIR" $RED
        exit 1
    fi
    
    # 获取所有配置文件
    local config_files=("$CONFIG_DIR"/node*.json)
    if [ ${#config_files[@]} -eq 0 ]; then
        log error "❌ 未找到节点配置文件" $RED
        exit 1
    fi
    
    log info "🔍 找到 ${#config_files[@]} 个节点配置文件" $BLUE
    
    # 测试每个节点
    local port=$PORT_BASE
    for config in "${config_files[@]}"; do
        local node_name=$(basename "$config" .json)
        log info "\n${BLUE}===== 测试节点: $node_name (端口 $port) =====${NC}" $BLUE
        
        # 测试节点连通性
        local test_results=$(test_node_connectivity "$config" "$port")
        if [[ $? -eq 0 ]]; then
            # 保存结果
            echo "$test_results" | tr ' ' '\n' > "$TMP_DIR/$node_name.results"
        else
            log error "节点测试失败" $RED
        fi
        
        ((port++))
    done
    
    # 生成报告
    generate_detailed_report "$REPORT_FILE" "${config_files[@]}"
    generate_summary_report "$SUMMARY_FILE" "$REPORT_FILE"
    
    log info "\n${GREEN}✅ 测试完成!${NC}" $GREEN
    log info "📊 详细报告: $REPORT_FILE" $CYAN
    log info "📝 摘要报告: $SUMMARY_FILE" $CYAN
    
    # 显示摘要
    echo -e "\n${YELLOW}===== 测试摘要 =====${NC}"
    cat "$SUMMARY_FILE"
}

# 执行主函数
main