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
HDFS_DIR="/user/hive/warehouse/test_db.db/employees_external"
CSV_FILE="${TEST_DIR}/test.csv"

# 创建测试目录
print_message "创建测试目录..."
mkdir -p ${TEST_DIR}

# 创建示例CSV数据
print_message "创建测试数据..."
cat > ${CSV_FILE} << EOF
1,张三,25,技术部,15000.00,2023-01-01
2,李四,30,市场部,12000.00,2023-02-01
3,王五,28,销售部,18000.00,2023-03-01
4,赵六,35,人事部,13000.00,2023-04-01
5,孙七,27,财务部,14000.00,2023-05-01
EOF

# 上传数据到HDFS
print_message "上传数据到HDFS..."
hdfs dfs -mkdir -p ${HDFS_DIR}
hdfs dfs -put -f ${CSV_FILE} ${HDFS_DIR}/

# 创建Hive SQL文件
print_message "创建Hive SQL文件..."
cat > ${TEST_DIR}/create_table.sql << EOF
-- 创建数据库
CREATE DATABASE IF NOT EXISTS test_db;
USE test_db;

-- 删除已存在的表
DROP TABLE IF EXISTS employees_external;

-- 创建外部表
CREATE EXTERNAL TABLE employees_external (
    id INT,
    name STRING,
    age INT,
    department STRING,
    salary DECIMAL(10,2),
    hire_date DATE
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '${HDFS_DIR}';

-- 查询数据验证
SELECT * FROM employees_external;

-- 统计信息
SELECT 
    department,
    COUNT(*) as employee_count,
    AVG(salary) as avg_salary,
    MIN(salary) as min_salary,
    MAX(salary) as max_salary
FROM employees_external
GROUP BY department;
EOF

# 执行Hive查询
print_message "执行Hive查询..."
${HIVE_CMD} -f ${TEST_DIR}/create_table.sql

# 验证结果
if [ $? -eq 0 ]; then
    print_message "测试完成！外部表创建和数据导入成功。"
    print_message "测试数据位置: ${CSV_FILE}"
    print_message "可以使用以下命令查看数据:"
    echo "${HIVE_CMD} -e 'SELECT * FROM test_db.employees_external;'"
else
    print_error "测试失败，请检查错误信息。"
fi

# 清理临时SQL文件（保留数据文件供查看）
rm -f ${TEST_DIR}/create_table.sql