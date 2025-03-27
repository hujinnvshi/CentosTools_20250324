-- 创建内部表
CREATE TABLE employee (
    emp_id INT COMMENT '员工ID',
    emp_name STRING COMMENT '员工姓名',
    emp_age INT COMMENT '员工年龄',
    emp_dept STRING COMMENT '所属部门',
    emp_salary DOUBLE COMMENT '薪资',
    join_date DATE COMMENT '入职日期'
)
COMMENT '员工信息表'
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE;

-- 插入测试数据
INSERT INTO TABLE employee VALUES
(1001, '张三', 28, '技术部', 15000.00, '2023-01-15'),
(1002, '李四', 32, '市场部', 12000.00, '2023-02-01'),
(1003, '王五', 25, '技术部', 13000.00, '2023-03-10'),
(1004, '赵六', 35, '人事部', 11000.00, '2023-04-05'),
(1005, '孙七', 30, '财务部', 14000.00, '2023-05-20');

-- 批量插入数据方式二：从本地文件加载数据
-- 假设数据文件为 employee.txt，内容格式如下：
-- 1006,钱八,29,技术部,16000.00,2023-06-01
-- 1007,周九,31,市场部,13000.00,2023-07-15
LOAD DATA LOCAL INPATH '/path/to/employee.txt' INTO TABLE employee;

-- 查询验证数据
SELECT * FROM employee;