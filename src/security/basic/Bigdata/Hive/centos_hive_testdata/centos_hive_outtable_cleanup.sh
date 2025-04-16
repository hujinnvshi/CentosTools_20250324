#!/bin/bash

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

# 设置变量
HIVE_CMD="/data/hive/bin/beeline -u jdbc:hive2://172.16.48.171:10000 -n hive"
TEST_DIR="/tmp/hive_test"
# 设置变量
HDFS_HOST="tempvm"
HDFS_DIR="hdfs://${HDFS_HOST}:8020/user/hive/warehouse/test_db.db/employees_external1"

# 检查Hive连接
print_message "检查Hive连接..."
if ! ${HIVE_CMD} -e "show databases;" > /dev/null 2>&1; then
    print_error "无法连接到Hive服务器，请检查连接信息"
fi

# 删除Hive表和数据库
print_message "删除Hive表和数据库..."
${HIVE_CMD} << EOF
DROP TABLE IF EXISTS test_db.employees_external1;
DROP DATABASE IF EXISTS test_db CASCADE;
EOF

# 清理HDFS目录
print_message "清理HDFS目录..."
hdfs dfs -rm -r -f ${HDFS_DIR} 2>/dev/null || true
hdfs dfs -rm -r -f /user/hive/warehouse/test_db.db 2>/dev/null || true

# 清理本地文件
print_message "清理本地文件..."
rm -rf ${TEST_DIR}

# 验证清理结果
print_message "验证清理结果..."

# 检查Hive表是否存在
TABLE_EXISTS=$(${HIVE_CMD} -e "SHOW TABLES IN test_db LIKE 'employees_external1';" 2>/dev/null)
if [ -n "$TABLE_EXISTS" ]; then
    print_error "Hive表未成功删除"
fi

# 检查HDFS目录是否存在
if hdfs dfs -test -d ${HDFS_DIR} 2>/dev/null; then
    print_error "HDFS目录未成功删除"
fi

# 检查本地目录是否存在
if [ -d "${TEST_DIR}" ]; then
    print_error "本地测试目录未成功删除"
fi

print_message "清理完成！所有测试数据已被删除。"
