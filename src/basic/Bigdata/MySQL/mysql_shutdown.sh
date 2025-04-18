#!/bin/bash

# 设置变量
MYSQL_BASE="/data/mysql"
MYSQL_ROOT_PASSWORD="Secsmart#612"

# 方法1：使用 systemctl 温和停止
systemctl stop mysqld

# 方法2：使用 mysqladmin 温和关闭
${MYSQL_BASE}/base/bin/mysqladmin -u root -p${MYSQL_ROOT_PASSWORD} shutdown

# 方法3：使用 MySQL 命令关闭
${MYSQL_BASE}/base/bin/mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "SHUTDOWN;"

# 检查关闭状态
check_mysql_status() {
    if ! pgrep mysqld > /dev/null; then
        echo "MySQL 已成功关闭"
        return 0
    else
        echo "MySQL 仍在运行"
        return 1
    fi
}

# 等待 MySQL 完全关闭
wait_for_shutdown() {
    local timeout=30
    local count=0
    while [ $count -lt $timeout ]; do
        if check_mysql_status; then
            break
        fi
        echo "等待 MySQL 关闭... $count/$timeout"
        sleep 1
        count=$((count + 1))
    done

    if [ $count -eq $timeout ]; then
        echo "MySQL 关闭超时"
        return 1
    fi
}