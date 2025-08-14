#!/bin/bash
# 网络连通性综合测试脚本
# 版本: 1.0
# 作者: 网络性能专家
# 最后更新: 2023-10-15

# 配置参数
PROXY_ADDRESS="socks5h://127.0.0.1:1080"
TEST_URL="https://www.google.com"
TEST_FILE_URL="https://www.google.com/images/branding/googlelogo/2x/googlelogo_color_272x92dp.png"
TEST_COUNT=5
TIMEOUT=10
OUTPUT_FILE="network_test_$(date +%Y%m%d_%H%M%S).log"

# 初始化结果数组
declare -A results

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 测试函数：基本网络连通性
test_basic_connectivity() {
    echo -e "${BLUE}[1/6] 测试基本网络连通性${NC}"
    
    # 测试本地网络
    ping -c 3 127.0.0.1 >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 本地环回地址 (127.0.0.1) 可达${NC}"
        results["local_loopback"]="✓"
    else
        echo -e "${RED}✗ 本地环回地址不可达 - 严重问题${NC}"
        results["local_loopback"]="✗"
    fi
    
    # 测试网关
    gateway=$(ip route | awk '/default/ {print $3}')
    if [ -n "$gateway" ]; then
        ping -c 3 $gateway >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ 网关 ($gateway) 可达${NC}"
            results["gateway"]="✓"
        else
            echo -e "${YELLOW}⚠ 网关 ($gateway) 不可达${NC}"
            results["gateway"]="⚠"
        fi
    else
        echo -e "${YELLOW}⚠ 未检测到默认网关${NC}"
        results["gateway"]="⚠"
    fi
    
    # 测试公共DNS
    dns_servers=("8.8.8.8" "1.1.1.1" "208.67.222.222")
    for dns in "${dns_servers[@]}"; do
        ping -c 3 $dns >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ DNS服务器 ($dns) 可达${NC}"
            results["dns_$dns"]="✓"
        else
            echo -e "${YELLOW}⚠ DNS服务器 ($dns) 不可达${NC}"
            results["dns_$dns"]="⚠"
        fi
    done
}

# 测试函数：DNS解析能力
test_dns_resolution() {
    echo -e "${BLUE}[2/6] 测试DNS解析能力${NC}"
    
    domains=("google.com" "baidu.com" "cloudflare.com")
    
    for domain in "${domains[@]}"; do
        # 不使用代理
        dig +short $domain >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ 直接解析 $domain 成功${NC}"
            results["dns_direct_$domain"]="✓"
        else
            echo -e "${YELLOW}⚠ 直接解析 $domain 失败${NC}"
            results["dns_direct_$domain"]="⚠"
        fi
        
        # 使用代理
        dig +short @127.0.0.1 -p 1080 $domain >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ 代理解析 $domain 成功${NC}"
            results["dns_proxy_$domain"]="✓"
        else
            echo -e "${YELLOW}⚠ 代理解析 $domain 失败${NC}"
            results["dns_proxy_$domain"]="⚠"
        fi
    done
}

# 测试函数：代理连接测试
test_proxy_connection() {
    echo -e "${BLUE}[3/6] 测试代理连接${NC}"
    
    # 测试HTTP连接
    response=$(curl -x $PROXY_ADDRESS -I -s -o /dev/null -w "%{http_code}" $TEST_URL --max-time $TIMEOUT)
    if [[ $response == 200 ]]; then
        echo -e "${GREEN}✓ 代理HTTP连接成功 (HTTP 200)${NC}"
        results["proxy_http"]="✓"
    else
        echo -e "${RED}✗ 代理HTTP连接失败 (HTTP $response)${NC}"
        results["proxy_http"]="✗"
    fi
    
    # 测试HTTPS连接
    response=$(curl -x $PROXY_ADDRESS -I -s -o /dev/null -w "%{http_code}" -k $TEST_URL --max-time $TIMEOUT)
    if [[ $response == 200 ]]; then
        echo -e "${GREEN}✓ 代理HTTPS连接成功 (HTTP 200)${NC}"
        results["proxy_https"]="✓"
    else
        echo -e "${RED}✗ 代理HTTPS连接失败 (HTTP $response)${NC}"
        results["proxy_https"]="✗"
    fi
}

# 测试函数：代理延迟测试
test_proxy_latency() {
    echo -e "${BLUE}[4/6] 测试代理延迟${NC}"
    
    total_time=0
    success_count=0
    
    for ((i=1; i<=$TEST_COUNT; i++)); do
        response_time=$(curl -x $PROXY_ADDRESS -s -o /dev/null -w "%{time_total}" $TEST_URL --max-time $TIMEOUT)
        
        if [ $? -eq 0 ]; then
            printf "${GREEN}测试 %d/%d: %.3f 秒${NC}\n" $i $TEST_COUNT $response_time
            total_time=$(echo "$total_time + $response_time" | bc)
            success_count=$((success_count+1))
        else
            echo -e "${RED}测试 $i/$TEST_COUNT: 失败${NC}"
        fi
    done
    
    if [ $success_count -gt 0 ]; then
        avg_time=$(echo "scale=3; $total_time / $success_count" | bc)
        echo -e "${GREEN}平均延迟: ${avg_time} 秒 (基于 $success_count 次成功测试)${NC}"
        results["proxy_latency"]="$avg_time"
    else
        echo -e "${RED}所有延迟测试均失败${NC}"
        results["proxy_latency"]="失败"
    fi
}

# 测试函数：下载速度测试
test_download_speed() {
    echo -e "${BLUE}[5/6] 测试下载速度${NC}"
    
    # 使用wget测试下载速度
    echo -e "${YELLOW}使用wget测试下载速度...${NC}"
    wget_time=$( (time -p wget -q -e use_proxy=yes -e http_proxy=$PROXY_ADDRESS $TEST_FILE_URL -O /dev/null) 2>&1 | grep real | awk '{print $2}')
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}wget下载完成时间: ${wget_time} 秒${NC}"
        results["download_wget"]="$wget_time"
    else
        echo -e "${RED}wget下载失败${NC}"
        results["download_wget"]="失败"
    fi
    
    # 使用curl测试下载速度
    echo -e "${YELLOW}使用curl测试下载速度...${NC}"
    curl_speed=$(curl -x $PROXY_ADDRESS -o /dev/null -s -w "%{speed_download}" $TEST_FILE_URL --max-time $TIMEOUT)
    
    if [ $? -eq 0 ]; then
        # 转换字节/秒为KB/s
        speed_kbs=$(echo "scale=2; $curl_speed / 1024" | bc)
        echo -e "${GREEN}curl下载速度: ${speed_kbs} KB/s${NC}"
        results["download_curl"]="${speed_kbs} KB/s"
    else
        echo -e "${RED}curl下载失败${NC}"
        results["download_curl"]="失败"
    fi
}

# 测试函数：综合网络测试
test_comprehensive() {
    echo -e "${BLUE}[6/6] 综合网络测试${NC}"
    
    # 测试Traceroute
    echo -e "${YELLOW}测试到Google的路由路径...${NC}"
    traceroute -T -n -q 1 -w 1 www.google.com > traceroute.log 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Traceroute测试完成 (结果保存到 traceroute.log)${NC}"
        results["traceroute"]="✓"
    else
        echo -e "${YELLOW}⚠ Traceroute测试失败${NC}"
        results["traceroute"]="⚠"
    fi
    
    # 测试MTR
    if command -v mtr &> /dev/null; then
        echo -e "${YELLOW}运行MTR测试...${NC}"
        mtr -c 10 -r -n www.google.com > mtr.log 2>&1
        echo -e "${GREEN}✓ MTR测试完成 (结果保存到 mtr.log)${NC}"
        results["mtr"]="✓"
    else
        echo -e "${YELLOW}⚠ mtr未安装，跳过MTR测试${NC}"
        results["mtr"]="未安装"
    fi
    
    # 测试带宽
    if command -v iperf3 &> /dev/null; then
        echo -e "${YELLOW}寻找iperf3服务器...${NC}"
        iperf_server="iperf.he.net"
        ping -c 1 $iperf_server >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${YELLOW}测试带宽到 $iperf_server...${NC}"
            iperf3 -c $iperf_server -p 5201 -P 4 -t 5 -J > iperf.json
            echo -e "${GREEN}✓ 带宽测试完成 (结果保存到 iperf.json)${NC}"
            results["bandwidth"]="✓"
        else
            echo -e "${YELLOW}⚠ iperf服务器不可达，跳过带宽测试${NC}"
            results["bandwidth"]="服务器不可达"
        fi
    else
        echo -e "${YELLOW}⚠ iperf3未安装，跳过带宽测试${NC}"
        results["bandwidth"]="未安装"
    fi
}

# 生成测试报告
generate_report() {
    echo -e "\n${BLUE}===== 网络测试报告 =====${NC}"
    echo -e "测试时间: $(date)"
    echo -e "代理地址: $PROXY_ADDRESS"
    echo -e "测试URL: $TEST_URL"
    echo -e "测试次数: $TEST_COUNT"
    echo -e "超时设置: ${TIMEOUT}秒"
    echo -e "输出文件: $OUTPUT_FILE"
    echo -e "------------------------------"
    
    # 显示关键结果
    echo -e "${YELLOW}关键指标:${NC}"
    echo -e "本地网络: ${results["local_loopback"]} | 网关: ${results["gateway"]}"
    echo -e "代理HTTP: ${results["proxy_http"]} | 代理HTTPS: ${results["proxy_https"]}"
    echo -e "平均延迟: ${results["proxy_latency"]} | 下载速度: ${results["download_curl"]}"
    
    echo -e "\n${YELLOW}详细结果:${NC}"
    for key in "${!results[@]}"; do
        printf "%-25s: %s\n" "$key" "${results[$key]}"
    done
    
    # 保存到文件
    {
        echo "===== 网络测试报告 ====="
        echo "测试时间: $(date)"
        echo "代理地址: $PROXY_ADDRESS"
        echo "测试URL: $TEST_URL"
        echo "测试次数: $TEST_COUNT"
        echo "超时设置: ${TIMEOUT}秒"
        echo "------------------------------"
        echo "关键指标:"
        echo "本地网络: ${results["local_loopback"]} | 网关: ${results["gateway"]}"
        echo "代理HTTP: ${results["proxy_http"]} | 代理HTTPS: ${results["proxy_https"]}"
        echo "平均延迟: ${results["proxy_latency"]} | 下载速度: ${results["download_curl"]}"
        echo "------------------------------"
        echo "详细结果:"
        for key in "${!results[@]}"; do
            printf "%-25s: %s\n" "$key" "${results[$key]}"
        done
    } > "$OUTPUT_FILE"
    
    echo -e "\n${GREEN}测试报告已保存到 $OUTPUT_FILE${NC}"
}

# 主函数
main() {
    clear
    echo -e "${BLUE}===== 网络连通性综合测试 =====${NC}"
    echo -e "开始时间: $(date)\n"
    
    # 执行所有测试
    test_basic_connectivity
    echo ""
    test_dns_resolution
    echo ""
    test_proxy_connection
    echo ""
    test_proxy_latency
    echo ""
    test_download_speed
    echo ""
    test_comprehensive
    
    # 生成报告
    generate_report
}

# 执行主函数
main