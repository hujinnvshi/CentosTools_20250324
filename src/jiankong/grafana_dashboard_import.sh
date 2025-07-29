#!/bin/bash

# 导入Grafana仪表盘脚本
# 使用方法: ./import-grafana-dashboard.sh [仪表盘ID] [数据源名称] [Grafana URL] [用户名] [密码]

set -euo pipefail

# 默认参数
DASHBOARD_ID=${1:-1860}           # Node Exporter仪表盘ID
DATASOURCE_NAME=${2:-Prometheus}  # 默认数据源名称
GRAFANA_URL=${3:-http://localhost:3000}
USERNAME=${4:-admin}
PASSWORD=${5:-Secsmart#612}

# 重试配置
MAX_ATTEMPTS=3
RETRY_DELAY=5  # 秒

# 日志函数
log() {
    echo -e "\033[1;34m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m $1"
}

error() {
    echo -e "\033[1;31m[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1\033[0m" >&2
}

# 检查Grafana是否可达
check_grafana_health() {
    log "检查Grafana服务健康状态..."
    for attempt in $(seq 1 $MAX_ATTEMPTS); do
        response=$(curl -s -o /dev/null -w "%{http_code}" "$GRAFANA_URL/api/health" -u "$USERNAME:$PASSWORD")
        if [ "$response" = "200" ]; then
            log "Grafana服务正常运行"
            return 0
        fi
        error "尝试 $attempt/$MAX_ATTEMPTS: Grafana不可达 (状态码: $response)"
        sleep $RETRY_DELAY
    done
    error "Grafana服务无法访问，退出脚本"
    return 1
}

# 获取仪表盘JSON
fetch_dashboard_json() {
    log "获取仪表盘ID $DASHBOARD_ID 的配置..."
    local dashboard_json=""
    
    # 尝试获取指定版本（最新稳定版）
    dashboard_json=$(curl -s "https://grafana.com/api/dashboards/$DASHBOARD_ID/revisions/latest/download")
    
    # 验证获取结果
    if [ -z "$dashboard_json" ] || ! echo "$dashboard_json" | grep -q "title"; then
        error "无法获取仪表盘配置，可能ID错误或网络问题"
        return 1
    fi
    
    echo "$dashboard_json"
    return 0
}

# 导入仪表盘
import_dashboard() {
    local dashboard_json="$1"
    log "准备导入仪表盘到Grafana..."
    
    for attempt in $(seq 1 $MAX_ATTEMPTS); do
        log "尝试 $attempt/$MAX_ATTEMPTS 导入仪表盘..."
        
        response=$(curl -s -X POST -H "Content-Type: application/json" \
            -u "$USERNAME:$PASSWORD" \
            -d "{
                \"dashboard\": $dashboard_json,
                \"inputs\": [{
                    \"name\": \"DS_PROMETHEUS\",
                    \"type\": \"datasource\",
                    \"pluginId\": \"prometheus\",
                    \"value\": \"$DATASOURCE_NAME\"
                }],
                \"overwrite\": true
            }" \
            "$GRAFANA_URL/api/dashboards/db")
        
        # 检查导入是否成功
        if echo "$response" | grep -q '"status":"success"' || 
           echo "$response" | grep -q '"imported":true' || 
           echo "$response" | grep -q '"uid"'; then
            log "仪表盘导入成功!"
            echo "$response" | grep -o '"url":"[^"]*"' | cut -d'"' -f4
            return 0
        else
            error "导入失败 (尝试 $attempt/$MAX_ATTEMPTS): $response"
            [ $attempt -lt $MAX_ATTEMPTS ] && sleep $RETRY_DELAY
        fi
    done
    
    error "达到最大重试次数，导入失败"
    return 1
}

# 主函数
main() {
    log "开始导入Grafana仪表盘 (ID: $DASHBOARD_ID)..."
    
    # 检查Grafana状态
    check_grafana_health || return 1
    
    # 获取仪表盘配置
    dashboard_json=$(fetch_dashboard_json) || return 1
    
    # 导入仪表盘
    import_dashboard "$dashboard_json" || return 1
    
    log "仪表盘导入流程完成!"
}

main "$@"