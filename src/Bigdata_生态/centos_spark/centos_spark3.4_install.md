#!/bin/bash
set -e

# 颜色输出函数
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 环境参数配置（请根据实际环境修改）
export HADOOP_HOME=${HADOOP_HOME:-"/opt/hadoop"}
export HIVE_HOME=${HIVE_HOME:-"/opt/hive"}
export SPARK_HOME=${SPARK_HOME:-"/opt/spark"}
export JAVA_HOME=${JAVA_HOME:-"/usr/lib/jvm/java-11-openjdk"}
export HDFS_PORT=${HDFS_PORT:-"8020"}
export HIVE_METASTORE_PORT=${HIVE_METASTORE_PORT:-"9083"}

# 检查环境变量
check_environment() {
    log_info "检查环境变量配置..."
    
    # 检查 Hadoop
    if [ ! -d "$HADOOP_HOME" ]; then
        log_error "HADOOP_HOME 不存在: $HADOOP_HOME"
        exit 1
    fi
    log_info "HADOOP_HOME: $HADOOP_HOME"
    
    # 检查 Hive
    if [ ! -d "$HIVE_HOME" ]; then
        log_error "HIVE_HOME 不存在: $HIVE_HOME"
        exit 1
    fi
    log_info "HIVE_HOME: $HIVE_HOME"
    
    # 检查 Java
    if [ ! -d "$JAVA_HOME" ]; then
        log_error "JAVA_HOME 不存在: $JAVA_HOME"
        exit 1
    fi
    log_info "JAVA_HOME: $JAVA_HOME"
    
    # 检查 Spark
    if [ ! -d "$SPARK_HOME" ]; then
        log_warn "SPARK_HOME 不存在，将下载安装 Spark 3.4.1"
        install_spark
    else
        log_info "SPARK_HOME: $SPARK_HOME"
    fi
}

# 下载安装 Spark（如果需要）
install_spark() {
    log_info "下载安装 Spark 3.4.1..."
    
    mkdir -p /tmp/spark_install
    cd /tmp/spark_install
    
    wget -q https://archive.apache.org/dist/spark/spark-3.4.1/spark-3.4.1-bin-hadoop3.tgz
    tar -xzf spark-3.4.1-bin-hadoop3.tgz -C /opt/
    ln -sf /opt/spark-3.4.1-bin-hadoop3 /opt/spark
    
    export SPARK_HOME="/opt/spark"
    
    log_info "Spark 安装完成: $SPARK_HOME"
}

# 配置环境变量
setup_environment() {
    log_info "配置环境变量..."
    
    # 备份原有配置
    cp ~/.bashrc ~/.bashrc.backup.$(date +%Y%m%d)
    
    # 添加环境变量配置
    cat >> ~/.bashrc << EOF

# ========================
# BigData Environment Variables
# ========================
export HADOOP_HOME=$HADOOP_HOME
export HIVE_HOME=$HIVE_HOME
export SPARK_HOME=$SPARK_HOME
export JAVA_HOME=$JAVA_HOME
export HDFS_PORT=$HDFS_PORT
export HIVE_METASTORE_PORT=$HIVE_METASTORE_PORT

# PATH 配置
export PATH=\$SPARK_HOME/bin:\$SPARK_HOME/sbin:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin:\$HIVE_HOME/bin:\$PATH

# Spark 配置
export PYSPARK_PYTHON=python3
export PYSPARK_DRIVER_PYTHON=python3
export SPARK_CONF_DIR=\$SPARK_HOME/conf

# Hadoop 类路径
export SPARK_DIST_CLASSPATH=\$(\$HADOOP_HOME/bin/hadoop classpath)

# Hive 配置
export HIVE_CONF_DIR=\$HIVE_HOME/conf
EOF

    source ~/.bashrc
    log_info "环境变量配置完成"
}

# 配置 Spark
configure_spark() {
    log_info "配置 Spark 集成..."
    
    cd $SPARK_HOME/conf
    
    # 备份原有配置
    cp spark-defaults.conf spark-defaults.conf.backup.$(date +%Y%m%d) 2>/dev/null || true
    
    # 创建 spark-defaults.conf
    cat > spark-defaults.conf << EOF
# ========================
# Spark 3.4.1 集成配置
# ========================

# 基础配置
spark.master                    local[4]
spark.driver.memory             2g
spark.executor.memory           2g
spark.sql.adaptive.enabled      true
spark.sql.adaptive.coalescePartitions.enabled true

# Hive 2.3.9 集成配置
spark.sql.catalogImplementation hive
spark.sql.hive.metastore.version 2.3.9
spark.sql.hive.metastore.jars builtin
spark.sql.warehouse.dir hdfs://localhost:${HDFS_PORT}/user/hive/warehouse

# HDFS 配置（端口 ${HDFS_PORT}）
spark.hadoop.fs.defaultFS       hdfs://localhost:${HDFS_PORT}
spark.hadoop.dfs.replication    1

# PySpark 配置
spark.pyspark.python           python3
spark.pyspark.driver.python    python3

# 序列化配置
spark.serializer               org.apache.spark.serializer.KryoSerializer
spark.kryoserializer.buffer.max 256m

# 事件日志
spark.eventLog.enabled         true
spark.eventLog.dir             hdfs://localhost:${HDFS_PORT}/spark-logs
spark.history.fs.logDirectory  hdfs://localhost:${HDFS_PORT}/spark-logs

# 动态资源分配
spark.dynamicAllocation.enabled true
spark.dynamicAllocation.minExecutors 1
spark.dynamicAllocation.maxExecutors 10
EOF

    # 配置 spark-env.sh
    cp spark-env.sh.template spark-env.sh 2>/dev/null || true
    
    cat >> spark-env.sh << EOF

# Hadoop 集成
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
export YARN_CONF_DIR=$HADOOP_HOME/etc/hadoop

# Hive 集成
export HIVE_HOME=$HIVE_HOME
export HIVE_CONF_DIR=$HIVE_HOME/conf

# Java 配置
export JAVA_HOME=$JAVA_HOME

# Spark 目录
export SPARK_LOG_DIR=/data/spark/logs
export SPARK_WORKER_DIR=/data/spark/work
export SPARK_LOCAL_DIRS=/data/spark/tmp

# Python 配置
export PYSPARK_PYTHON=python3
export PYSPARK_DRIVER_PYTHON=python3

# 类路径配置
export SPARK_DIST_CLASSPATH=\$($HADOOP_HOME/bin/hadoop classpath)
EOF

    log_info "Spark 配置完成"
}

# 配置 MySQL 驱动
setup_mysql_driver() {
    log_info "配置 MySQL JDBC 驱动..."
    
    # 检查是否已有 MySQL 驱动
    MYSQL_DRIVER=$(find $HIVE_HOME/lib -name "mysql-connector*.jar" | head -1)
    
    if [ -n "$MYSQL_DRIVER" ]; then
        log_info "找到 MySQL 驱动: $MYSQL_DRIVER"
        # 复制到 Spark
        cp $MYSQL_DRIVER $SPARK_HOME/jars/
        log_info "MySQL 驱动已复制到 Spark"
    else
        log_warn "未找到 MySQL 驱动，正在下载..."
        download_mysql_driver
    fi
}

# 下载 MySQL 驱动
download_mysql_driver() {
    cd /tmp
    wget -q https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-8.0.33.tar.gz
    tar -xzf mysql-connector-java-8.0.33.tar.gz
    cp mysql-connector-java-8.0.33/mysql-connector-java-8.0.33.jar $SPARK_HOME/jars/
    log_info "MySQL 驱动下载并安装完成"
}

# 创建 HDFS 目录
create_hdfs_directories() {
    log_info "创建 HDFS 目录..."
    
    # 检查 HDFS 服务是否运行
    if $HADOOP_HOME/bin/hdfs dfs -test -d /tmp >/dev/null 2>&1; then
        log_info "HDFS 服务正常运行"
    else
        log_warn "HDFS 服务未运行，请先启动 HDFS"
        return 1
    fi
    
    # 创建必要的目录
    $HADOOP_HOME/bin/hdfs dfs -mkdir -p /spark-logs
    $HADOOP_HOME/bin/hdfs dfs -mkdir -p /tmp/spark
    $HADOOP_HOME/bin/hdfs dfs -chmod -R 777 /spark-logs
    $HADOOP_HOME/bin/hdfs dfs -chmod -R 777 /tmp/spark
    
    log_info "HDFS 目录创建完成"
}

# 测试集成功能
test_integration() {
    log_info "测试 Spark + Hive + HDFS 集成..."
    
    # 创建测试脚本
    cat > /tmp/test_spark_integration.py << 'EOF'
#!/usr/bin/env python3
from pyspark.sql import SparkSession
import sys

def test_integration():
    print("=== Spark 3.4.1 + Hive 2.3.9 + Hadoop 3.1.2 集成测试 ===")
    
    try:
        # 创建 SparkSession
        spark = SparkSession.builder \
            .appName("IntegrationTest") \
            .config("spark.sql.warehouse.dir", "hdfs://localhost:8020/user/hive/warehouse") \
            .config("spark.sql.catalogImplementation", "hive") \
            .enableHiveSupport() \
            .getOrCreate()
        
        print("✅ SparkSession 创建成功")
        
        # 测试 Spark 基本功能
        print("1. 测试 Spark 基本功能...")
        df = spark.range(100).toDF("number")
        count = df.count()
        print(f"✅ Spark 基本功能正常，数据量: {count}")
        
        # 测试 HDFS 集成
        print("2. 测试 HDFS 集成...")
        df.write.mode("overwrite").parquet("hdfs://localhost:8020/tmp/spark_test")
        hdfs_df = spark.read.parquet("hdfs://localhost:8020/tmp/spark_test")
        hdfs_count = hdfs_df.count()
        print(f"✅ HDFS 集成正常，读取数据量: {hdfs_count}")
        
        # 测试 Hive 集成
        print("3. 测试 Hive 集成...")
        spark.sql("SHOW DATABASES").show()
        spark.sql("USE default")
        print("✅ Hive 数据库操作正常")
        
        # 测试创建 Hive 表
        print("4. 测试 Hive 表操作...")
        spark.sql("""
            CREATE TABLE IF NOT EXISTS integration_test (
                id INT,
                name STRING,
                value DOUBLE
            ) STORED AS PARQUET
        """)
        print("✅ Hive 表创建成功")
        
        # 清理测试数据
        spark.sql("DROP TABLE IF EXISTS integration_test")
        spark.stop()
        
        print("🎉 所有集成测试通过！")
        return True
        
    except Exception as e:
        print(f"❌ 集成测试失败: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = test_integration()
    sys.exit(0 if success else 1)
EOF

    # 运行测试
    $SPARK_HOME/bin/spark-submit /tmp/test_spark_integration.py
}

# 创建管理脚本
create_management_scripts() {
    log_info "创建管理脚本..."
    
    # Spark 服务管理
    cat > /usr/local/bin/start-spark-history.sh << EOF
#!/bin/bash
echo "启动 Spark History Server..."
$SPARK_HOME/sbin/start-history-server.sh
echo "Spark History Server 启动完成"
echo "访问地址: http://localhost:18080"
EOF

    cat > /usr/local/bin/stop-spark-history.sh << EOF
#!/bin/bash
echo "停止 Spark History Server..."
$SPARK_HOME/sbin/stop-history-server.sh
echo "Spark History Server 已停止"
EOF

    cat > /usr/local/bin/spark-status.sh << EOF
#!/bin/bash
echo "=== Spark 服务状态 ==="
echo "Spark Home: $SPARK_HOME"
echo "History Server: \$(netstat -tln | grep -q 18080 && echo '运行中(18080)' || echo '未运行')"
echo "Hive Metastore: \$(netstat -tln | grep -q $HIVE_METASTORE_PORT && echo '运行中($HIVE_METASTORE_PORT)' || echo '未运行')"
echo "HDFS: \$(netstat -tln | grep -q $HDFS_PORT && echo '运行中($HDFS_PORT)' || echo '未运行')"
EOF

    # 设置执行权限
    chmod +x /usr/local/bin/start-spark-history.sh
    chmod +x /usr/local/bin/stop-spark-history.sh
    chmod +x /usr/local/bin/spark-status.sh
    
    log_info "管理脚本创建完成"
}

# 生成配置报告
generate_config_report() {
    log_info "生成配置报告..."
    
    cat > /tmp/spark_integration_report.txt << EOF
=== Spark 3.4.1 集成配置报告 ===
生成时间: $(date)

环境配置:
- Hadoop Home: $HADOOP_HOME
- Hive Home: $HIVE_HOME  
- Spark Home: $SPARK_HOME
- Java Home: $JAVA_HOME
- HDFS 端口: $HDFS_PORT
- Hive Metastore 端口: $HIVE_METASTORE_PORT

关键配置:
- Spark Master: local[4]
- Hive 集成: 已启用 (版本 2.3.9)
- HDFS 集成: 已启用 (端口 $HDFS_PORT)
- MySQL 驱动: 已配置

测试命令:
1. 启动 Spark History: /usr/local/bin/start-spark-history.sh
2. 测试集成: $SPARK_HOME/bin/spark-submit /tmp/test_spark_integration.py
3. 检查状态: /usr/local/bin/spark-status.sh

访问地址:
- Spark History: http://localhost:18080
- HDFS Web UI: http://localhost:9870
EOF

    log_info "配置报告已生成: /tmp/spark_integration_report.txt"
    cat /tmp/spark_integration_report.txt
}

# 主函数
main() {
    log_info "开始配置 Spark 3.4.1 集成..."
    
    check_environment
    setup_environment
    configure_spark
    setup_mysql_driver
    create_hdfs_directories
    create_management_scripts
    test_integration
    generate_config_report
    
    log_info "🎉 Spark 集成配置完成！"
    log_info "使用以下命令管理服务:"
    log_info "启动历史服务器: start-spark-history.sh"
    log_info "停止历史服务器: stop-spark-history.sh" 
    log_info "查看服务状态: spark-status.sh"
}

# 执行主函数
main "$@"