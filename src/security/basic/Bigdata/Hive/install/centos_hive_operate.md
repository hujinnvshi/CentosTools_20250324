我帮你整理一个Hive手动操作命令文档：

```markdown:/Users/www.redelego.cn/CentosTools_20250324/src/security/basic/Bigdata/Hive/install/centos_hive_operate.md
# Hive 手动操作命令

## 1. 服务启动命令

### 启动 Metastore
```bash
nohup /data/hive/bin/hive --service metastore > /data/hive/logs/metastore.out 2>&1 &
```

### 启动 HiveServer2
```bash
# 注意：必须先启动 Metastore，等待约30秒后再启动 HiveServer2
nohup /data/hive/bin/hiveserver2 > /data/hive/logs/hiveserver2.out 2>&1 &
```

## 2. 服务停止命令

### 停止 HiveServer2
```bash
pkill -f org.apache.hive.service.server.HiveServer2
```

### 停止 Metastore
```bash
pkill -f org.apache.hadoop.hive.metastore.HiveMetaStore
```

## 3. 服务状态检查

### 检查进程
```bash
ps -ef | grep hive
```

### 检查端口
```bash
# 检查 HiveServer2 端口（默认10000）
netstat -nltp | grep 10000

# 检查 Metastore 端口（默认9083）
netstat -nltp | grep 9083
```

### 检查日志
```bash
# 查看 Metastore 日志
tail -f /data/hive/logs/metastore.out

# 查看 HiveServer2 日志
tail -f /data/hive/logs/hiveserver2.out
```

## 4. 连接测试

### 使用 Beeline 连接
```bash
# 本地连接
/data/hive/bin/beeline -u jdbc:hive2://localhost:10000

# 指定用户连接
/data/hive/bin/beeline -u jdbc:hive2://localhost:10000 -n hive
/data/hive/bin/beeline -u jdbc:hive2://172.16.48.171:10000 -n hive
```

### 使用 Hive CLI 测试
```bash
/data/hive/bin/hive -e "show databases;"
```

## 注意事项：
1. 启动顺序：必须先启动 Metastore，再启动 HiveServer2
2. 停止顺序：建议先停止 HiveServer2，再停止 Metastore
3. 启动前确保 HDFS 和 MySQL 服务正常运行
4. 建议使用 hive 用户执行这些命令
```