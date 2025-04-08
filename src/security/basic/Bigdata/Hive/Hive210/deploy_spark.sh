#!/bin/bash

# 环境变量定义
HADOOP_HOME="/data2/Hive210/base/hadoop-2.10.2"
HIVE_HOME="/data2/Hive210/base/apache-hive-2.1.0-bin"
INSTALL_DIR="/data2/Hive210/base"
SPARK_VERSION="3.2.4"
SPARK_HADOOP_VERSION="2.7"
SPARK_HOME="${INSTALL_DIR}/spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 日志函数
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# 下载并安装Spark
install_spark() {
    log "开始安装Spark..."
    
    cd ${INSTALL_DIR} || error "无法进入安装目录"
    
    if [ ! -f "spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}.tgz" ]; then
        wget "https://dlcdn.apache.org/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}.tgz" || error "Spark下载失败"
    fi
    
    tar -xzf "spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}.tgz" || error "Spark解压失败"
    
    log "Spark安装完成"
}

# 配置Spark环境
configure_spark() {
    log "配置Spark环境..."
    
    # 配置spark-env.sh
    cp ${SPARK_HOME}/conf/spark-env.sh.template ${SPARK_HOME}/conf/spark-env.sh
    cat >> ${SPARK_HOME}/conf/spark-env.sh << EOF
export JAVA_HOME=/data2/JDK8u251/jdk1.8.0_251
export HADOOP_HOME=${HADOOP_HOME}
export HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
export SPARK_MASTER_HOST=$(hostname)
export SPARK_MASTER_PORT=7077
export SPARK_WORKER_CORES=$(nproc)
export SPARK_WORKER_MEMORY=$(($(free -g | awk '/^Mem:/{print $2}') * 80 / 100))g
export SPARK_DAEMON_MEMORY=1g
EOF

    # 配置spark-defaults.conf
    cp ${SPARK_HOME}/conf/spark-defaults.conf.template ${SPARK_HOME}/conf/spark-defaults.conf
    cat >> ${SPARK_HOME}/conf/spark-defaults.conf << EOF
spark.master                     spark://$(hostname):7077
spark.eventLog.enabled           true
spark.eventLog.dir              hdfs:///spark-logs
spark.history.fs.logDirectory   hdfs:///spark-logs
spark.executor.memory           2g
spark.driver.memory             1g
EOF

    # 配置workers
    echo $(hostname) > ${SPARK_HOME}/conf/workers
    
    log "Spark配置完成"
}

# 配置Hive使用Spark
configure_hive_spark() {
    log "配置Hive使用Spark引擎..."
    # 需要备份原有配置
    cp ${HIVE_HOME}/conf/hive-site.xml ${HIVE_HOME}/conf/hive-site.xml.bak
    # 修改hive-site.xml
    cat > ${HIVE_HOME}/conf/hive-site.xml << EOF
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <!-- 保留原有配置 -->
    <property>
        <name>hive.execution.engine</name>
        <value>spark</value>
    </property>
    <property>
        <name>spark.master</name>
        <value>spark://$(hostname):7077</value>
    </property>
    <property>
        <name>spark.eventLog.enabled</name>
        <value>true</value>
    </property>
    <property>
        <name>spark.eventLog.dir</name>
        <value>hdfs:///spark-logs</value>
    </property>
    <property>
        <name>spark.executor.memory</name>
        <value>2g</value>
    </property>
    <property>
        <name>spark.driver.memory</name>
        <value>1g</value>
    </property>
</configuration>
EOF
    log "Hive配置完成"
}

# 创建HDFS目录
setup_hdfs() {
    log "创建HDFS目录..."
    ${HADOOP_HOME}/bin/hdfs dfs -mkdir -p /spark-logs
    ${HADOOP_HOME}/bin/hdfs dfs -chmod 777 /spark-logs
}

# 启动Spark服务
start_spark() {
    log "启动Spark服务..."
    ${SPARK_HOME}/sbin/start-all.sh
}

# 测试Spark性能
test_spark() {
    log "测试Spark性能..."
    
    # 运行SparkPi示例
    ${SPARK_HOME}/bin/spark-submit \
        --class org.apache.spark.examples.SparkPi \
        --master spark://$(hostname):7077 \
        --executor-memory 1G \
        --total-executor-cores 2 \
        ${SPARK_HOME}/examples/jars/spark-examples*.jar \
        100
        
    log "Spark测试完成"
}

# 主函数
install_scala() {
    log "开始安装Scala..."
    
    cd ${INSTALL_DIR} || error "无法进入安装目录"
    
    if [ ! -f "scala-${SCALA_VERSION}.tgz" ]; then
        wget "https://downloads.lightbend.com/scala/${SCALA_VERSION}/scala-${SCALA_VERSION}.tgz" || error "Scala下载失败"
    fi
    
    tar -xzf "scala-${SCALA_VERSION}.tgz" || error "Scala解压失败"
    
    # 配置Scala环境变量
    cat > /etc/profile.d/scala.sh << EOF
export SCALA_HOME=${SCALA_HOME}
export PATH=\$PATH:\$SCALA_HOME/bin
EOF
    
    source /etc/profile.d/scala.sh
    
    # 验证安装
    scala -version || error "Scala安装失败"
    
    log "Scala安装完成"
}

main() {
    log "开始部署Spark集群..."
    
    # 检查Java环境
    java -version || error "Java未安装"
    
    # 检查Hadoop运行状态
    jps | grep -E "NameNode|DataNode" > /dev/null || error "Hadoop未运行"
    
    install_scala    # 添加这一行
    install_spark
    configure_spark
    setup_hdfs
    configure_hive_spark
    start_spark
    test_spark
    
    log "Spark部署完成"
    log "请使用jps命令检查服务状态"
    log "访问Spark Web UI: http://$(hostname):8080"
}

# 执行主函数
main