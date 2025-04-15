Centos7.9系统
Hadoop2.7.7 安装在 /data/hadoop-2.7.7/base
Hive2.1.0 安装在 /data/hive
我想将hive的执行引擎改为tez
tez部署在/data/tez-0.9.1/base 中
请给出详细的操作步骤，以及相关的配置文件修改。

我帮你整理将Hive执行引擎切换到Tez的详细步骤：

```markdown:/Users/www.redelego.cn/CentosTools_20250324/src/security/basic/Bigdata/Tez/centos_tez_install.md
# Hive 切换 Tez 执行引擎配置指南

## 1. 环境变量配置

```bash
# 编辑 /etc/profile.d/tez.sh
cat > /etc/profile.d/tez.sh << 'EOF'
# Tez 环境变量
export TEZ_HOME=/data/tez-0.9.1/base
export TEZ_CONF_DIR=$TEZ_HOME/conf
export TEZ_JARS=$TEZ_HOME
export HADOOP_CLASSPATH=${TEZ_CONF_DIR}:${TEZ_JARS}/*:${TEZ_JARS}/lib/*:$HADOOP_CLASSPATH
EOF

# 使环境变量生效
source /etc/profile.d/tez.sh
```

## 2. 上传 Tez 到 HDFS

```bash
# 创建 HDFS 目录
hdfs dfs -mkdir -p /apps/tez

# 上传 Tez 相关文件
hdfs dfs -put /data/tez-0.9.1/base/* /apps/tez/
```

## 3. 修改 Hive 配置

```bash
# 编辑 /data/hive/conf/hive-site.xml，添加或修改以下配置
cat > /data/hive/conf/hive-site.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <!-- 现有配置保持不变 -->
    
    <!-- Tez 相关配置 -->
    <property>
        <name>hive.execution.engine</name>
        <value>tez</value>
    </property>
    
    <property>
        <name>hive.tez.container.size</name>
        <value>1024</value>
    </property>
    
    <property>
        <name>hive.tez.java.opts</name>
        <value>-Xmx820m</value>
    </property>
    
    <!-- Tez 优化配置 -->
    <property>
        <name>hive.tez.auto.reducer.parallelism</name>
        <value>true</value>
    </property>
    
    <property>
        <name>hive.tez.dynamic.partition.pruning</name>
        <value>true</value>
    </property>
    
    <property>
        <name>hive.optimize.index.filter</name>
        <value>true</value>
    </property>
    
    <property>
        <name>hive.vectorized.execution.enabled</name>
        <value>true</value>
    </property>
    
    <property>
        <name>hive.vectorized.execution.reduce.enabled</name>
        <value>true</value>
    </property>
</configuration>
EOF
```

## 4. 创建 Tez 配置文件

```bash
# 创建 tez-site.xml
cat > /data/tez-0.9.1/base/conf/tez-site.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <property>
        <name>tez.lib.uris</name>
        <value>${fs.defaultFS}/apps/tez/,${fs.defaultFS}/apps/tez/lib/</value>
    </property>
    
    <property>
        <name>tez.use.cluster.hadoop-libs</name>
        <value>true</value>
    </property>
    
    <property>
        <name>tez.am.resource.memory.mb</name>
        <value>1024</value>
    </property>
    
    <property>
        <name>tez.task.resource.memory.mb</name>
        <value>1024</value>
    </property>
    
    <property>
        <name>tez.runtime.io.sort.mb</name>
        <value>512</value>
    </property>
</configuration>
EOF
```

## 5. 重启服务

```bash
# 停止 Hive 服务
pkill -f org.apache.hive.service.server.HiveServer2
pkill -f org.apache.hadoop.hive.metastore.HiveMetaStore

# 启动 Hive 服务
nohup /data/hive/bin/hive --service metastore > /data/hive/logs/metastore.out 2>&1 &
sleep 30
nohup /data/hive/bin/hiveserver2 > /data/hive/logs/hiveserver2.out 2>&1 &
```

## 6. 验证配置

```bash
# 连接 Hive
/data/hive/bin/beeline -u jdbc:hive2://localhost:10000

# 在 Beeline 中执行以下命令
set hive.execution.engine;

```

## 注意事项：
1. 确保 Hadoop YARN 服务正常运行
2. 内存配置需要根据实际服务器资源调整
3. 首次执行任务可能会较慢，因为需要下载相关依赖
4. 建议在测试环境验证后再在生产环境部署
```
# https://blog.csdn.net/lz6363/article/details/87475064