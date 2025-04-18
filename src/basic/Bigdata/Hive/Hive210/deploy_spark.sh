#!/bin/bash

# 环境变量定义
HADOOP_HOME="/data2/Hive210/base/hadoop-2.10.2"
HIVE_HOME="/data2/Hive210/base/apache-hive-2.1.0-bin"
INSTALL_DIR="/data2/Hive210/base"
SPARK_VERSION="3.2.4"
SPARK_HADOOP_VERSION="2.7"
SPARK_HOME="${INSTALL_DIR}/spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}"
# 添加Scala版本定义
SCALA_VERSION="2.12.18"
SCALA_HOME="${INSTALL_DIR}/scala-${SCALA_VERSION}"

# 修改install_scala函数
install_scala() {
    log "开始安装Scala..."
    cd ${INSTALL_DIR} || error "无法进入安装目录"
    # 使用清华镜像源下载
    if [ ! -f "scala-${SCALA_VERSION}.tgz" ]; then
        wget "https://mirrors.tuna.tsinghua.edu.cn/scala/scala-${SCALA_VERSION}.tgz" || \
        wget "https://downloads.typesafe.com/scala/${SCALA_VERSION}/scala-${SCALA_VERSION}.tgz" || \
        error "Scala下载失败"
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
        # 使用清华镜像源作为主源，阿里云作为备用源
        wget "https://mirrors.tuna.tsinghua.edu.cn/apache/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}.tgz" || \
        wget "https://mirrors.aliyun.com/apache/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}.tgz" || \
        wget "https://mirrors.huaweicloud.com/apache/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}.tgz" || \
        error "Spark下载失败"
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
# 修改主机地址配置
export SPARK_LOCAL_IP=127.0.0.1
export SPARK_MASTER_HOST=127.0.0.1
export SPARK_MASTER_PORT=7077
export SPARK_MASTER_WEBUI_PORT=8082  # 修改为8082
export SPARK_WORKER_CORES=$(nproc)
export SPARK_WORKER_MEMORY=$(($(free -g | awk '/^Mem:/{print $2}') * 60 / 100))g
export SPARK_DAEMON_MEMORY=1g
EOF

    # 修改spark-defaults.conf配置
    cat >> ${SPARK_HOME}/conf/spark-defaults.conf << EOF
spark.master                     spark://127.0.0.1:7077
spark.eventLog.enabled           true
spark.eventLog.dir              hdfs:///spark-logs
spark.history.fs.logDirectory   hdfs:///spark-logs
spark.executor.memory           2g
spark.driver.memory             1g
spark.ui.port                   8082  # 添加此行
spark.port.maxRetries           32
EOF
}

# 配置Hive使用Spark
configure_hive_spark() {
    log "配置Hive使用Spark引擎..."
    # 需要备份原有配置,添加时间戳
    BACKUP_TIME=$(date +%Y%m%d_%H%M%S)
    cp ${HIVE_HOME}/conf/hive-site.xml ${HIVE_HOME}/conf/hive-site.xml.bak_${BACKUP_TIME}

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
    $SPARK_HOME/bin/spark-submit \
    --class org.apache.spark.examples.SparkPi \
    --master yarn \
    --deploy-mode cluster \
    $SPARK_HOME/examples/jars/spark-examples_*.jar \
    10        
    log "Spark测试完成"
}

# 主函数
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