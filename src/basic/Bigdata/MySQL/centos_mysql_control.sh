#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 输出带颜色的信息函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

case "$1" in
    start)
        print_message "启动 MySQL 服务..."
        systemctl start mysqld
        ;;
    stop)
        print_message "停止 MySQL 服务..."
        systemctl stop mysqld
        ;;
    restart)
        print_message "重启 MySQL 服务..."
        systemctl restart mysqld
        ;;
    status)
        print_message "MySQL 服务状态："
        systemctl status mysqld
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status}"
        exit 1
esac
# 关闭 MySQL
mysqladmin -u root -p shutdown

-- 创建管理用户
CREATE USER 'admin'@'%' IDENTIFIED BY 'Secsmart#612';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%';
FLUSH PRIVILEGES;

mysql -h 172.16.61.225 -uadmin -p'Secsmart#612'
mysql -h 172.16.48.171 -uadmin -p'Secsmart#612' 

-- MySQL 5.7.39 集群
mysql -h 172.16.48.166 -P 3010 -uadmin -p'Secsmart#612'
mysql -h 172.16.48.167 -P 3010 -uadmin -p'Secsmart#612'

-- MySQL 5.7.38 集群
mysql -h 172.16.48.166 -P 3011 -uadmin -p'Secsmart#612'
mysql -h 172.16.48.167 -P 3011 -uadmin -p'Secsmart#612'

mysql -h 192.168.0.40 -P 3306 -uadmin -p'Secsmart#612'
mysql -h 172.16.48.72 -P 3014 -uadmin -p'Secsmart#612'

mysql -uhive20250324 -p'Secsmart#612' -h 172.16.61.225
mysql -uhive20250324 -p'Secsmart#612' -h 172.16.61.225 -D hive20250324