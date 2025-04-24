#!/bin/bash

# 定义变量
PG_USER="PostgreSQL_9.4.26_V1"
PG_PORT="6001"
PG_DB="testdb"

# 创建测试数据库
psql -h localhost -p $PG_PORT -U admin -d postgres -c "CREATE DATABASE $PG_DB;" || { echo "创建测试数据库失败"; exit 1; }

# 创建测试表
psql -h localhost -p $PG_PORT -U admin -d $PG_DB << EOF
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF

# 插入测试数据
psql -h localhost -p $PG_PORT -U admin -d $PG_DB << EOF
INSERT INTO users (username, email) VALUES
('user1', 'user1@example.com'),
('user2', 'user2@example.com'),
('user3', 'user3@example.com');
EOF

# 查询测试数据
psql -h localhost -p $PG_PORT -U admin -d $PG_DB -c "SELECT * FROM users;"

echo "测试表和测试数据创建完成！"