根据您的启动脚本，我来调整检测脚本以适配您的环境：

```bash:/Users/www.redelego.cn/CentosTools_20250324/src/security/Elastic Search/check_es.sh
#!/bin/bash

# 设置颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# ES 配置
ES_HOST="localhost"
ES_PORT="9200"
ES_USER="user-es"
ES_HOME="/opt/elasticsearch-7.10.2"

# 检查ES进程
check_process() {
    if ps -u ${ES_USER} | grep elasticsearch > /dev/null; then
        echo -e "${GREEN}Elasticsearch 进程正在运行${NC}"
        ps -u ${ES_USER} | grep elasticsearch
    else
        echo -e "${RED}Elasticsearch 进程未运行${NC}"
        exit 1
    fi
}

# 检查端口
check_port() {
    if netstat -tuln | grep ":$ES_PORT" > /dev/null; then
        echo -e "${GREEN}端口 $ES_PORT 正在监听${NC}"
    else
        echo -e "${RED}端口 $ES_PORT 未监听${NC}"
        exit 1
    fi
}

# 检查集群健康状态
check_health() {
    response=$(curl -s "http://$ES_HOST:$ES_PORT/_cluster/health")
    if [ $? -eq 0 ]; then
        status=$(echo $response | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        echo -e "${GREEN}集群状态: $status${NC}"
    else
        echo -e "${RED}无法获取集群状态${NC}"
        exit 1
    fi
}

# 检查磁盘使用情况
check_disk() {
    echo "ES数据目录使用情况："
    df -h ${ES_HOME}/data
}

# 检查日志
check_logs() {
    echo "最近的错误日志："
    tail -n 5 ${ES_HOME}/logs/elasticsearch.log
}

# 检查JVM状态
check_jvm() {
    su - ${ES_USER} -c "jps | grep Elasticsearch"
}

# 执行所有检查
echo "开始检查 Elasticsearch..."
check_process
check_port
check_health
check_disk
check_logs
check_jvm
echo "检查完成"
```

主要调整：
1. 添加了 ES_USER 和 ES_HOME 变量
2. 修改了进程检查方式，使用指定用户
3. 更新了数据目录路径
4. 添加了日志检查功能
5. 添加了 JVM 状态检查

启动和停止脚本：
```bash:/Users/www.redelego.cn/CentosTools_20250324/src/security/Elastic Search/es_control.sh
#!/bin/bash

# ES 配置
ES_USER="user-es"
ES_HOME="/opt/elasticsearch-7.10.2"

case "$1" in
    start)
        echo "启动 Elasticsearch..."
        su - ${ES_USER} -c "nohup ${ES_HOME}/bin/elasticsearch > /dev/null 2>&1 &"
        ;;
    stop)
        echo "停止 Elasticsearch..."
        ps -u ${ES_USER} | grep elasticsearch | awk '{print $1}' | xargs kill
        ;;
    restart)
        $0 stop
        sleep 5
        $0 start
        ;;
    *)
        echo "用法: $0 {start|stop|restart}"
        exit 1
        ;;
esac
```

使用方法：
```bash
# 添加执行权限
chmod +x check_es.sh es_control.sh

# 检查状态
./check_es.sh

# 控制服务
./es_control.sh start|stop|restart
```