
# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 输出函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 创建测试数据
print_message "创建测试数据..."
cat > /tmp/init.sql << EOF

CREATE DATABASE test_db;
CREATE USER 'test_user'@'localhost' IDENTIFIED BY 'Test@123';
GRANT ALL PRIVILEGES ON test_db.* TO 'test_user'@'localhost';
FLUSH PRIVILEGES;

CREATE DATABASE admin;
CREATE USER 'admin'@'%' IDENTIFIED BY 'Secsmart#612';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%';
FLUSH PRIVILEGES;

USE test_db;
CREATE TABLE employees (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    age INT,
    department VARCHAR(50),
    salary DECIMAL(10,2),
    hire_date DATE
);

INSERT INTO employees (name, age, department, salary, hire_date) VALUES ('张三', 30, '技术部', 15000.00, '2023-01-01');
EOF

# 设置变量
export PERCONA_VERSION="8.4.0-1"
export PERCONA_HOME="/data/percona_8.4.0"
export PERCONA_USER="percona"
export PERCONA_GROUP="perconagrp"
export PERCONA_PORT="3308"
export PERCONA_PASSWORD="Secsmart#612"

if ! ${PERCONA_HOME}/base/bin/mysql -P ${PERCONA_PORT} -S ${PERCONA_HOME}/tmp/mysql.sock -uroot -p"${PERCONA_PASSWORD}" < /tmp/init.sql; then
    print_error "创建测试数据失败"
fi