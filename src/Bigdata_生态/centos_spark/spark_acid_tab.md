### 一、前置前提（Spark 访问 Hive ACID 表核心要求）

Spark 访问 Hive ACID 表需满足以下条件（Hive 2.1.1 + Spark 2.x/3.x 通用）：

1. Spark 配置集成 Hive：将 Hive 的`hive-site.xml`拷贝到`$SPARK_HOME/conf`目录（确保 Spark 能读取 Hive 元数据和 Kerberos 配置）；
2. Kerberos 认证有效：与 Hive 一致的 Kerberos 票据（避免认证失败）；
3. ACID 表格式兼容：Hive ACID 表为 ORC 格式，Spark 原生支持 ORC 读取。

### 二、操作步骤（spark-shell --master yarn）

#### 步骤 1：前置准备（Kerberos 认证+配置检查）

```bash
# 1. 确保Kerberos票据有效（与Hive认证用户一致）
kinit [你的Kerberos用户]@EXAMPLE.COM

# 2. 检查Spark conf目录是否有hive-site.xml（关键！）
ls $SPARK_HOME/conf/hive-site.xml
# 若不存在，从Hive集群拷贝（如Hive的conf目录：/etc/hive/conf/hive-site.xml）
cp /etc/hive/conf/hive-site.xml $SPARK_HOME/conf/
```

#### 步骤 2：启动 spark-shell（指定 yarn 模式+Kerberos 适配）

```bash
# 启动spark-shell，指定yarn master，同时加载Hive配置
# yarn.nodemanager.linux-container-executor.nonsecure-mode.limit-users 设置为false
spark-shell --master yarn \
  --conf spark.hadoop.hive.metastore.kerberos.principal=spark/cdhk2@EXAMPLE.COM \
  --conf spark.hadoop.hive.server2.authentication=KERBEROS \
  --conf spark.hadoop.hadoop.security.authentication=kerberos
```

启动成功后进入 Scala 交互提示符（`scala>`），且 SparkSession 会自动关联 Hive（默认名为`spark`）。

#### 步骤 3：验证 Spark 与 Hive 元数据连接

先确认 Spark 能读取 Hive 的数据库和表列表，验证 ACID 表是否存在：

```scala
// 1. 显示Hive所有数据库（确认连接成功）
spark.sql("show databases").show()

// 2. 切换到default库（ACID表所在库）
spark.sql("use default").show()

// 3. 显示default库下的表（确认acid_user_info存在）
spark.sql("show tables").show()

// 4. 查看ACID表结构（验证元数据读取）
spark.sql("desc acid_user_info").show(false)
```

#### 步骤 4：读取 Hive ACID 表数据

Spark 读取 ACID 表与普通 ORC 表操作一致，支持 SQL 和 DataFrame 两种方式：

##### 方式 1：SQL 方式（推荐，与 Hive 语法一致）

```scala
// 1. 全量读取ACID表数据
val acidTableDF = spark.sql("select * from acid_user_info")

// 2. 展示所有数据（对应之前插入的5行）
acidTableDF.show()

// 3. 条件查询（示例：筛选女性用户）
spark.sql("select name, age, address from acid_user_info where gender = '女'").show()

// 4. 统计分析（示例：按性别分组统计人数）
spark.sql("select gender, count(*) as user_count from acid_user_info group by gender").show()
```

##### 方式 2：DataFrame API 方式

```scala
// 1. 加载ACID表为DataFrame
val acidDF = spark.table("acid_user_info")

// 2. 打印Schema（验证表结构）
acidDF.printSchema()

// 3. 筛选+展示（示例：年龄>28的用户）
acidDF.filter("age > 28").select("id", "name", "age").show()

// 4. 保存为临时视图（供后续SQL复用）
acidDF.createOrReplaceTempView("tmp_acid_user")
spark.sql("select * from tmp_acid_user where address like '%京%'").show()
```

#### 步骤 5：（可选）Spark 写入 Hive ACID 表说明

⚠️ **核心限制**：Spark 2.x/3.x 不建议直接写入 Hive ACID 表（Spark 未原生支持 Hive ACID 事务协议），若需写入，推荐两种方案：

1. 优先通过 Hive CLI/Beeline 执行`INSERT`（符合 ACID 事务规范）；
2. 若必须通过 Spark 写入，需先写入普通 ORC 表，再通过 Hive 迁移至 ACID 表：

```scala
// 示例：Spark写入临时ORC表 → Hive插入ACID表
// 1. Spark创建临时ORC表并写入数据
spark.sql(
  """
    |CREATE TABLE tmp_orc_user (
    |  id INT, name STRING, age INT, gender STRING, address STRING
    |) STORED AS ORC
  """.stripMargin
)
// 插入测试数据
spark.sql(
  """
    |INSERT INTO tmp_orc_user
    |SELECT 6, '杨八', 29, '男', '成都' UNION ALL
    |SELECT 7, '吴九', 27, '女', '南京'
  """.stripMargin
)

// 2. 退出spark-shell，通过Beeline将临时表数据插入ACID表
// beeline -u "jdbc:hive2://cdhk1:10000/default;principal=hive/cdhk1@EXAMPLE.COM"
// INSERT INTO acid_user_info SELECT * FROM tmp_orc_user;
```

### 三、预期输出示例

#### 1. 全量读取 ACID 表的输出：

```
+---+----+---+------+-------+
| id|name|age|gender|address|
+---+----+---+------+-------+
|  1|张三| 25|    男|   北京|
|  2|李四| 30|    男|   上海|
|  3|王五| 28|    女|   广州|
|  4|赵六| 32|    男|   深圳|
|  5|陈七| 26|    女|   杭州|
+---+----+---+------+-------+
```

#### 2. 条件查询（女性用户）输出：

```
+----+---+-------+
|name|age|address|
+----+---+-------+
|王五| 28|   广州|
|陈七| 26|   杭州|
+----+---+-------+
```

### 四、常见问题排查

1. **Kerberos 认证失败**：

   - 确保`kinit`票据未过期（执行`klist`查看）；
   - 检查`hive-site.xml`中`hive.metastore.kerberos.principal`与集群一致；
   - 启动 spark-shell 时添加`--principal [你的Kerberos用户]@EXAMPLE.COM`。

2. **找不到 ACID 表**：

   - 确认`hive-site.xml`已拷贝到`$SPARK_HOME/conf`；
   - 执行`spark.sql("use default")`切换到正确数据库；
   - 检查 Hive 元数据服务（HiveMetastore）是否正常运行。

3. **读取数据为空**：

   - 确认 Hive 的 ACID 表已成功插入数据（Beeline 中查询验证）；
   - 检查 Spark 读取的 Hive 库是否与表所在库一致；
   - 验证 ORC 文件权限（Spark/Yarn 用户需有 HDFS 路径`/user/hive/warehouse/acid_user_info`的读权限）。

4. **Spark 写入 ACID 表报错**：
   - 直接写入会提示“不支持事务表写入”，需按上述“临时表迁移”方案操作；
   - 若需批量写入，优先使用 Hive 的`LOAD DATA`或`INSERT SELECT`。
