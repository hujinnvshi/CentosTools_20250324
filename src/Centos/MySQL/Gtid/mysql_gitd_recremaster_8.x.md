以下是基于 MySQL 8.x 版本的 GTID 复制重构详细步骤：

---

### **MySQL 8.x GTID 环境 Slave 重构 Master 节点详细步骤**

---

### **1. 停止 Slave 同步**
在 Slave 节点上停止同步：
```sql
STOP SLAVE;
```

---

### **2. 重置 Slave 状态**
重置 Slave 状态，清除旧的同步信息：
```sql
RESET SLAVE ALL;
```

---

### **3. 获取 Master 的 GTID 信息**
在 Master 节点上执行以下命令，获取当前的 GTID 信息：
```sql
SHOW MASTER STATUS \G;
```

输出示例：
```
*************************** 1. row ***************************
             File: binlog.000010
         Position: 1077
     Binlog_Do_DB: 
 Binlog_Ignore_DB: 
Executed_Gtid_Set: 71570446-c179-11ee-ac58-005056aa559b:1-26
1 row in set (0.00 sec)
```

---

### **4. 创建复制用户**
在 Master 节点上创建用于复制的用户：
```sql
CREATE USER 'repl'@'%' IDENTIFIED BY 'Secsmart#612';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
FLUSH PRIVILEGES;
```

---

### **5. 配置新的 Master 信息**
在 Slave 节点上配置连接到新的 Master 节点：
```sql
CHANGE MASTER TO
MASTER_HOST='172.16.48.166',
MASTER_PORT=3312,
MASTER_USER='admin',
MASTER_PASSWORD='Secsmart#612',
MASTER_AUTO_POSITION=4401;

CHANGE MASTER TO
MASTER_HOST='172.16.48.166',
MASTER_PORT=3312,
MASTER_USER='admin',
MASTER_PASSWORD='Secsmart#612',
MASTER_LOG_FILE='Percona-bin.000004',  -- 指定二进制日志文件
MASTER_LOG_POS=4401;               -- 指定日志位置

```

SET GLOBAL sql_slave_skip_counter = 1;

- **`MASTER_HOST`**：新 Master 的 IP 地址。
- **`MASTER_USER`** 和 **`MASTER_PASSWORD`**：用于复制的用户名和密码。
- **`MASTER_AUTO_POSITION=1`**：启用 GTID 自动定位。

---

### **6. 启动 Slave 同步**
启动 Slave 同步：
```sql
START SLAVE;
```

---

### **7. 检查同步状态**
检查 Slave 同步状态，确保同步正常：
```sql
SHOW SLAVE STATUS \G;
```

重点关注以下字段：
- **`Slave_IO_Running`**：是否为 `Yes`。
- **`Slave_SQL_Running`**：是否为 `Yes`。
- **`Seconds_Behind_Master`**：是否为 `0`。

---

### **8. 验证数据同步**
在新 Master 上创建测试数据，验证是否同步到 Slave：
```sql
CREATE DATABASE test_db;
USE test_db;
CREATE TABLE test_table (id INT PRIMARY KEY, name VARCHAR(50));
INSERT INTO test_table VALUES (1, 'Test Data');
```

在 Slave 上查询数据，验证同步是否成功：
```sql
USE test_db;
SELECT * FROM test_db.test_table;
```

---

### **总结**
通过以上步骤，可以在 MySQL 8.x GTID 环境中将 Slave 节点重新配置为连接到新的 Master 节点，并确保数据同步正常。