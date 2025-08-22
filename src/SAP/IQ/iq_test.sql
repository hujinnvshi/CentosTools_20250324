-- 1. 创建测试表
CREATE TABLE TestTable (
    ID        INTEGER       PRIMARY KEY,
    Name      VARCHAR(50)   NOT NULL,
    JoinDate  DATE          DEFAULT CURRENT DATE,
    Salary    NUMERIC(10,2) CHECK (Salary > 0)
);

-- 2. 插入五行测试数据
INSERT INTO TestTable (ID, Name, JoinDate, Salary) VALUES 
(1, '张三', '2023-01-15', 8500.00),
(2, '李四', '2023-02-20', 9200.50),
(3, '王五', DEFAULT, 7800.00),         -- 使用默认当前日期
(4, '赵六', '2023-04-10', NULL),       -- 允许NULL的列
(5, '钱七', '2023-05-01', 10500.75);

-- 3. 验证插入结果（可选）
SELECT * FROM TestTable ORDER BY ID;

SELECT PROPERTY('ProductVersion') AS "ProductVersion",
       PROPERTY('ProductName') AS "ProductName",
       PROPERTY('ProductLevel') AS "ProductLevel",
       PROPERTY('Version') AS "Version";


