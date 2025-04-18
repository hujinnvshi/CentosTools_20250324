-- 创建数据库（如果不存在）
CREATE DATABASE IF NOT EXISTS hive_test;
USE hive_test;

-- 创建 Hive 组件信息表
CREATE TABLE IF NOT EXISTS hive_components (
    component_id INT COMMENT '组件ID',
    component_name STRING COMMENT '组件名称',
    component_type STRING COMMENT '组件类型',
    description STRING COMMENT '组件描述',
    port INT COMMENT '默认端口号',
    status STRING COMMENT '组件状态'
)
COMMENT '存储 Hive 组件信息的测试表'
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE;

-- 插入测试数据
INSERT INTO TABLE hive_components VALUES
(1, 'HiveServer2', 'Service', 'Hive 的主服务组件，提供 JDBC/ODBC 连接支持', 10000, 'Active'),
(2, 'Metastore', 'Service', 'Hive 元数据存储服务，管理表结构和位置信息', 9083, 'Active');

-- 切换到测试数据库
USE hive_test;

-- 查看表结构
DESC hive_components;

-- 查看表详细信息
DESC FORMATTED hive_components;

-- 基本查询
SELECT * FROM hive_components;

-- 按条件查询
SELECT component_name, port, status 
FROM hive_components 
WHERE component_type = 'Service';

-- 按端口号排序
SELECT component_name, port 
FROM hive_components 
ORDER BY port;