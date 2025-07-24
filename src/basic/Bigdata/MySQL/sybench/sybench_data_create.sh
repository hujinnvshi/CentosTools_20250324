#!/bin/bash

# Sysbench 数据准备脚本
# 使用前请确保已创建数据库和用户

# 设置变量
DB_USER="root"
DB_PASSWORD="Secsmart#612"
DB_NAME="sbtest"
TABLE_SIZE=1000000  # 每张表的数据量
TABLES=10           # 创建的表数量
THREADS=8           # 使用的线程数

# 执行数据准备
sysbench oltp_read_write \
    --db-driver=mysql \
    --mysql-host=localhost \
    --mysql-port=3011 \
    --mysql-user=${DB_USER} \
    --mysql-password=${DB_PASSWORD} \
    --mysql-db=${DB_NAME} \
    --table-size=${TABLE_SIZE} \
    --tables=${TABLES} \
    --threads=${THREADS} \
    prepare

# 检查执行结果
if [ $? -eq 0 ]; then
    echo "数据准备成功完成！"
    echo "共创建 ${TABLES} 张表，每表 ${TABLE_SIZE} 行数据"
else
    echo "数据准备失败，请检查错误信息"
    exit 1
fi