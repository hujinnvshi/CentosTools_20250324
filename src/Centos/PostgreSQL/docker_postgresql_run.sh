#!/bin/bash

# 定义部署参数
CONTAINER_NAME="postgres_11.2_V1"
DATA_DIR="/data2/${CONTAINER_NAME}/data"
PG_PORT="5432"
PG_USER="admin"
PG_PASSWORD="Secsmart#612"
PG_DATABASE="postgres"

# 创建持久化目录
mkdir -p ${DATA_DIR} && chmod 777 ${DATA_DIR}  

# 运行PostgreSQL容器
docker run -d \
  --name ${CONTAINER_NAME} \
  --restart always \
  -p ${PG_PORT}:5432 \
  -v ${DATA_DIR}:/var/lib/postgresql/data \
  -e POSTGRES_USER=${PG_USER} \
  -e POSTGRES_PASSWORD=${PG_PASSWORD} \
  -e POSTGRES_DB=${PG_DATABASE} \
  postgres:11.2

# 等待容器启动
sleep 10

# 增加错误处理逻辑
if [ $? -ne 0 ]; then
    echo "容器启动失败，请检查日志"
    docker logs ${CONTAINER_NAME}
    exit 1
fi

# 验证部署
echo "验证容器状态:"
docker ps --filter "name=${CONTAINER_NAME}"
echo -e "\n登录命令:"
echo "docker exec -it ${CONTAINER_NAME} psql -U ${PG_USER} -d ${PG_DATABASE}"
echo "或使用外部连接:"
echo "psql -h 127.0.0.1 -p ${PG_PORT} -U ${PG_USER} -d ${PG_DATABASE}"