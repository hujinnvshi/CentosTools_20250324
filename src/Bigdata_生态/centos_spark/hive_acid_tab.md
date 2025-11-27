Hive 2.1.1
使用 beeline -u "jdbc:hive2://cdhk1:10000/default;principal=hive/cdhk1@EXAMPLE.COM"连接
帮我检查下是否开启了 acid 表功能
并创建一张 acid 表
插入五行数据
并进行查询
你是一名杰出的 Hive 应用专家，帮我实现上面的功能。

### 一、前置说明（Hive 2.1.1 ACID 表核心限制）

Hive 2.1.1 对 ACID 表有严格约束，需满足：

- 仅支持 **ORC 文件格式**；
- 仅支持 **管理表（MANAGED_TABLE）**，外部表不支持；
- 必须开启 **分桶（Bucketing）**；
- 不支持 `INSERT INTO ... VALUES` 直接插入，需通过 `INSERT INTO ... SELECT` 方式；
- 需开启事务相关配置（如下）。

### 二、操作步骤（Beeline 交互）

#### 步骤 1：连接 Beeline（Kerberos 认证）

```bash
# 先确保Kerberos票据有效（如需要）
kinit [你的Kerberos用户]@EXAMPLE.COM

# 连接HiveServer2
beeline -u "jdbc:hive2://cdhk1:10000/default;principal=hive/cdhk1@EXAMPLE.COM"
```

连接成功后会进入 `0: jdbc:hive2://cdhk1:10000/default>` 交互提示符。

#### 步骤 2：检查 ACID 功能是否开启

执行以下命令检查核心配置，确保参数值匹配（若未开启，需临时设置或修改`hive-site.xml`）：

```sql
-- 1. 事务管理器（必须为DbTxnManager）
set hive.txn.manager;
-- 预期结果：org.apache.hadoop.hive.ql.lockmgr.DbTxnManager

-- 2. 支持并发（必须为true）
set hive.support.concurrency;
-- 预期结果：true

-- 3. 强制分桶（必须为true）
set hive.enforce.bucketing;
-- 预期结果：true

-- 4. 压缩器初始化（必须为true）
set hive.compactor.initiator.on;
-- 预期结果：true

-- 5. 压缩器工作线程（至少1）
set hive.compactor.worker.threads;
-- 预期结果：≥1（如1/3/5）
```

**若配置未开启，临时生效设置（会话级）**：

```sql
set hive.txn.manager=org.apache.hadoop.hive.ql.lockmgr.DbTxnManager;
set hive.support.concurrency=true;
set hive.enforce.bucketing=true;
set hive.compactor.initiator.on=true;
set hive.compactor.worker.threads=3;
set hive.exec.dynamic.partition.mode=strict;
```

#### 步骤 3：创建 ACID 表

必须指定 `transactional=true`、ORC 格式、分桶，示例如下：

```sql
-- 创建ACID事务表（管理表+ORC+分桶）
CREATE TABLE acid_user_info (
    id INT,
    name STRING,
    age INT,
    gender STRING,
    address STRING
)
-- 分桶（ACID表必须，分桶字段/数量可自定义）
CLUSTERED BY (id) INTO 2 BUCKETS
-- 仅支持ORC格式
STORED AS ORC
-- 表属性：开启事务+ORC压缩（可选）
TBLPROPERTIES (
    'transactional' = 'true',
    'orc.compress' = 'SNAPPY'
);

-- 验证表属性（确认transactional=true）
DESCRIBE EXTENDED acid_user_info;
```

#### 步骤 4：插入 5 行数据

Hive 2.1.1 不支持 `INSERT INTO ... VALUES` 直接插入 ACID 表，需通过 `UNION ALL` 生成多行数据：

```sql
-- 插入5行测试数据
INSERT INTO acid_user_info
SELECT 1, '张三', 25, '男', '北京' UNION ALL
SELECT 2, '李四', 30, '男', '上海' UNION ALL
SELECT 3, '王五', 28, '女', '广州' UNION ALL
SELECT 4, '赵六', 32, '男', '深圳' UNION ALL
SELECT 5, '陈七', 26, '女', '杭州';
```

#### 步骤 5：查询 ACID 表数据

```sql
-- 全量查询
SELECT * FROM acid_user_info;

-- 条件查询（示例）
SELECT name, age, address FROM acid_user_info WHERE gender = '女';
```

### 三、预期输出

#### 查询结果示例：

```
+----------------+------------------+---------------+-------------------+--------------------+
| acid_user_info.id | acid_user_info.name | acid_user_info.age | acid_user_info.gender | acid_user_info.address |
+----------------+------------------+---------------+-------------------+--------------------+
| 1              | 张三             | 25            | 男                | 北京               |
| 2              | 李四             | 30            | 男                | 上海               |
| 3              | 王五             | 28            | 女                | 广州               |
| 4              | 赵六             | 32            | 男                | 深圳               |
| 5              | 陈七             | 26            | 女                | 杭州               |
+----------------+------------------+---------------+-------------------+--------------------+
5 rows selected (0.897 seconds)
```

### 四、常见问题排查

1. **Kerberos 认证失败**：确保 `kinit` 获取有效票据，且 `principal` 与 HiveServer2 配置一致；
2. **创建表报错「Transactional tables must be bucketed」**：未配置分桶（`CLUSTERED BY`），补充分桶语句即可；
3. **插入数据报错「Unsupported transactional operation」**：误用 `INSERT VALUES`，改用 `UNION ALL + SELECT` 方式；
4. **查询无数据**：检查插入语句是否执行成功，或 HDFS 路径（`/user/hive/warehouse/acid_user_info`）是否有 ORC 文件。

### 五、持久化开启 ACID（可选）

若需永久开启 ACID 功能，修改 Hive 集群的 `hive-site.xml` 配置：

```xml
<property>
    <name>hive.txn.manager</name>
    <value>org.apache.hadoop.hive.ql.lockmgr.DbTxnManager</value>
</property>
<property>
    <name>hive.support.concurrency</name>
    <value>true</value>
</property>
<property>
    <name>hive.enforce.bucketing</name>
    <value>true</value>
</property>
<property>
    <name>hive.compactor.initiator.on</name>
    <value>true</value>
</property>
<property>
    <name>hive.compactor.worker.threads</name>
    <value>3</value>
</property>
```

修改后重启 HiveMetastore 和 HiveServer2 生效。
