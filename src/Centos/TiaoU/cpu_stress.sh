#!/bin/bash
# CPU压力测试脚本 v2.1
# 功能：执行渐进式CPU压力测试并生成可视化报告
# 使用方法：./cpu_stress_test.sh [测试时长(分钟)] [最大线程倍数]
# sudo yum install -y epel-release
# sudo yum install -y stress-ng sysstat gnuplot coreutils

set -eo pipefail

# 配置参数
TEST_DURATION=${1:-5}          # 默认测试5分钟
MAX_THREAD_MULTIPLIER=${2:-4}  # 默认测试到4倍CPU核心数
REPORT_FILE="cpu_stress_report_$(date +%Y%m%d_%H%M%S).html"
TEMP_DATA_FILE="/tmp/cpu_stress_data.csv"

# 初始化环境
init_test() {
    echo "🛠️ 初始化测试环境..."
    trap cleanup EXIT ERR
    
    # 安装必要工具
    command -v stress-ng &>/dev/null || {
        echo "安装stress-ng..."
        sudo yum install -y epel-release && sudo yum install -y stress-ng sysstat gnuplot
    }
    
    # 创建数据文件头
    echo "Time,Load1,Load5,Load15,CPU%,Sys%,User%,CtxSw,Processes" > "$TEMP_DATA_FILE"
}

# 清理函数
cleanup() {
    echo "🧹 清理测试环境..."
    pkill -9 stress-ng &>/dev/null || true
    rm -f "$TEMP_DATA_FILE" &>/dev/null
}

# 执行单次压力测试
run_stress_test() {
    local threads=$1
    local duration=$2
    
    echo "🔥 开始测试: ${threads}线程 ${duration}分钟"
    
    # 启动stress-ng
    stress-ng --cpu "$threads" --timeout "${duration}m" --metrics-brief &
    local stress_pid=$!
    
    # 监控循环
    for ((i=1; i<=duration*60; i++)); do
        # 收集系统指标
        local loadavg=($(awk '{print $1,$2,$3}' /proc/loadavg))
        local cpu_stats=($(mpstat 1 1 | awk '/Average/ {print $3,$5,$12}'))
        local ctx_switches=$(awk '/^ctxt/ {print $2}' /proc/stat)
        local processes=$(ps -e --no-headers | wc -l)
        
        # 记录数据
        echo "$(date +%T),${loadavg[0]},${loadavg[1]},${loadavg[2]},${cpu_stats[0]},${cpu_stats[1]},${cpu_stats[2]},$ctx_switches,$processes" >> "$TEMP_DATA_FILE"
        sleep 1
    done
    
    wait "$stress_pid"
}

# 生成HTML报告
generate_report() {
    echo "📊 生成测试报告..."
    
    # 创建gnuplot图表
    gnuplot <<-EOF
        set terminal pngcairo size 1000,600 enhanced font 'Verdana,10'
        set output '/tmp/cpu_load.png'
        set title "CPU负载趋势"
        set xdata time
        set timefmt "%H:%M:%S"
        set format x "%H:%M"
        set xlabel "时间"
        set ylabel "负载"
        set grid
        plot "$TEMP_DATA_FILE" using 1:2 with lines title "1分钟负载", \
             "" using 1:3 with lines title "5分钟负载", \
             "" using 1:4 with lines title "15分钟负载"
        
        set output '/tmp/cpu_usage.png'
        set title "CPU使用率"
        set ylabel "百分比"
        plot "$TEMP_DATA_FILE" using 1:5 with lines title "总使用率", \
             "" using 1:6 with lines title "系统态", \
             "" using 1:7 with lines title "用户态"
        
        set output '/tmp/context_switches.png'
        set title "上下文切换"
        set ylabel "次数"
        set logscale y
        plot "$TEMP_DATA_FILE" using 1:8 with lines title "切换次数"
    EOF

    # 生成HTML
    cat > "$REPORT_FILE" <<-EOF
    <!DOCTYPE html>
    <html>
    <head>
        <title>CPU压力测试报告</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            .container { max-width: 1200px; margin: 0 auto; }
            .chart { margin-bottom: 30px; border: 1px solid #ddd; padding: 10px; }
            table { width: 100%; border-collapse: collapse; margin-top: 20px; }
            th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
            th { background-color: #f2f2f2; }
            .summary { background-color: #f9f9f9; padding: 15px; margin: 20px 0; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>CPU压力测试报告</h1>
            <p>生成时间: $(date)</p>
            <div class="summary">
                <h2>测试概要</h2>
                <p><strong>系统信息:</strong> $(uname -a)</p>
                <p><strong>CPU核心数:</strong> $(nproc) 逻辑核心</p>
                <p><strong>测试配置:</strong> 最大 ${MAX_THREAD_MULTIPLIER}倍核心数($(( $(nproc) * MAX_THREAD_MULTIPLIER ))线程), 总时长 ${TEST_DURATION}分钟</p>
            </div>
            
            <div class="chart">
                <h2>CPU负载趋势</h2>
                <img src="data:image/png;base64,$(base64 -w0 /tmp/cpu_load.png)" alt="CPU负载图表">
            </div>
            
            <div class="chart">
                <h2>CPU使用率</h2>
                <img src="data:image/png;base64,$(base64 -w0 /tmp/cpu_usage.png)" alt="CPU使用率图表">
            </div>
            
            <div class="chart">
                <h2>上下文切换</h2>
                <img src="data:image/png;base64,$(base64 -w0 /tmp/context_switches.png)" alt="上下文切换图表">
            </div>
            
            <h2>详细数据</h2>
            <table>
                <tr>
                    <th>时间</th>
                    <th>1分钟负载</th>
                    <th>5分钟负载</th>
                    <th>15分钟负载</th>
                    <th>CPU总使用率</th>
                    <th>系统态%</th>
                    <th>用户态%</th>
                    <th>上下文切换</th>
                </tr>
                $(awk -F, 'NR>1 {print "<tr><td>"$1"</td><td>"$2"</td><td>"$3"</td><td>"$4"</td><td>"$5"</td><td>"$6"</td><td>"$7"</td><td>"$8"</td></tr>"}' "$TEMP_DATA_FILE")
            </table>
        </div>
    </body>
    </html>
    EOF

    echo "✅ 测试报告已生成: $(pwd)/$REPORT_FILE"
}

# 主执行流程
main() {
    init_test
    
    local cpu_cores=$(nproc)
    echo "🖥️ 检测到系统有 ${cpu_cores} 个逻辑CPU核心"
    
    # 渐进式压力测试
    for multiplier in $(seq 1 $MAX_THREAD_MULTIPLIER); do
        threads=$(( cpu_cores * multiplier ))
        run_stress_test "$threads" "$(( TEST_DURATION / MAX_THREAD_MULTIPLIER ))"
    done
    
    generate_report
    cleanup
}

main