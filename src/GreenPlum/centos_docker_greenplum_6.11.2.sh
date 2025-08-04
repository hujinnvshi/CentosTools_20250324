#!/bin/bash
# Greenplum 6.11.2 Docker 一键部署脚本
# 包含端口检查、健康检查和初始化功能

set -euo pipefail

# 配置参数
GP_PORT=40224
GP_CONTAINER_NAME="greenplum_6.11.2V1_${GP_PORT}"
GP_ADMIN_USER="gpadmin"
GP_ADMIN_PASSWORD="Secsmart#612"
GP_DATABASE="postgres"
GP_DATA_DIR="/data/${GP_CONTAINER_NAME}"

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    echo "❌ Docker 未安装，请先安装 Docker"
    exit 1
fi

# 创建数据目录
mkdir -p "$GP_DATA_DIR"
chmod 777 "$GP_DATA_DIR"

# 检查端口是否被占用
check_port() {
    if netstat -tuln | grep ":$GP_PORT " > /dev/null; then
        echo "❌ 端口 $GP_PORT 已被占用，请释放端口或修改配置"
        exit 1
    fi
}

# 拉取镜像（如果不存在）
pull_image() {
    if ! docker image inspect gramirezc/greenplum_6.11.2 &> /dev/null; then
        echo "正在拉取 Greenplum 镜像..."
        docker pull gramirezc/greenplum_6.11.2
    else
        echo "Greenplum 镜像已存在"
    fi
}

# 启动容器
start_container() {
    echo "启动 Greenplum 容器..."
    docker run -d \
        --name "$GP_CONTAINER_NAME" \
        -p $GP_PORT:5432 \
        -v "$GP_DATA_DIR:/home/gpadmin" \
        -e "GP_USER=$GP_ADMIN_USER" \
        -e "GP_PASSWORD=$GP_ADMIN_PASSWORD" \
        -e "GP_DATABASE=$GP_DATABASE" \
        --health-cmd="pg_isready -U $GP_ADMIN_USER -d $GP_DATABASE" \
        --health-interval=10s \
        --health-timeout=5s \
        --health-retries=5 \
        gramirezc/greenplum_6.11.2
    
    echo "容器已启动，等待服务初始化..."
}

# 等待服务就绪
wait_for_service() {
    local timeout=120
    local start_time=$(date +%s)
    
    while :; do
        # 检查容器健康状态
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "$GP_CONTAINER_NAME")
        
        if [ "$health_status" == "healthy" ]; then
            echo "✅ Greenplum 服务已就绪"
            return 0
        fi
        
        # 检查超时
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout ]; then
            echo "❌ 服务启动超时，请检查日志：docker logs $GP_CONTAINER_NAME"
            return 1
        fi
        
        echo "等待服务启动...($elapsed/$timeout 秒)"
        sleep 5
    done
}

# 初始化数据库
initialize_database() {
    echo "初始化数据库..."
    # 创建示例表
    docker exec -it "$GP_CONTAINER_NAME" /opt/greenplum/bin/psql -U "$GP_ADMIN_USER" -d postgres <<-EOSQL
    CREATE TABLE employees (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100),
        department VARCHAR(50),
        salary NUMERIC(10,2)
    ) DISTRIBUTED BY (id);
    
    INSERT INTO employees (name, department, salary) VALUES
    ('Alice', 'Engineering', 75000),
    ('Bob', 'Marketing', 65000),
    ('Charlie', 'Sales', 80000);
    
    CREATE TABLE sales (
        id SERIAL PRIMARY KEY,
        product VARCHAR(50),
        quantity INT,
        sale_date DATE
    ) DISTRIBUTED BY (id);
    
    INSERT INTO sales (product, quantity, sale_date) VALUES
    ('Laptop', 10, '2023-01-15'),
    ('Phone', 25, '2023-01-20'),
    ('Tablet', 15, '2023-02-05');
EOSQL
    echo "✅ 数据库初始化完成"
}

# 显示连接信息
show_connection_info() {
    local container_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$GP_CONTAINER_NAME")
    
    echo "=================================================="
    echo "Greenplum 部署成功！"
    echo "=================================================="
    echo "连接信息:"
    echo "主机: localhost 或 $container_ip"
    echo "端口: $GP_PORT"
    echo "用户名: $GP_ADMIN_USER"
    echo "密码: $GP_ADMIN_PASSWORD"
    echo "数据库: $GP_DATABASE"
    echo "=================================================="
    echo "PSQL 连接命令:"
    echo "psql -h localhost -p $GP_PORT -U $GP_ADMIN_USER -d $GP_DATABASE"
    echo "=================================================="
    echo "Web 管理界面:"
    echo "http://localhost:28080 (如果支持)"
    echo "=================================================="
}

# 主执行流程
main() {
    echo "开始部署 Greenplum 6.11.2..."
    
    check_port
    pull_image
    
    # 清理旧容器（如果存在）
    if docker ps -a --filter "name=$GP_CONTAINER_NAME" | grep -q "$GP_CONTAINER_NAME"; then
        echo "发现已存在的容器，删除中..."
        docker rm -f "$GP_CONTAINER_NAME"
    fi

    start_container
    # wait_for_service
    # initialize_database
    show_connection_info    
    echo "✅ 部署完成"
}

main