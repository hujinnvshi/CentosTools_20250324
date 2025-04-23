Mysql Gtid 主从同步
帮我创建一个检查状态的脚本
以及创建下测试数据。

-- 创建测试数据库
CREATE DATABASE IF NOT EXISTS test_db;
USE test_db;

-- 创建测试表
CREATE TABLE IF NOT EXISTS test_table (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 插入测试数据
INSERT INTO test_table (name) VALUES ('Alice'), ('Bob'), ('Charlie');

-- 查询测试数据
SELECT * FROM test_table;


-- MySQL 8.0.28 主从同步
mysql -h 172.16.48.166 -P 3312 -uadmin -pSecsmart#612 admin
mysql -h 172.16.48.167 -P 3312 -uadmin -pSecsmart#612 admin