#!/bin/bash

# Oracle数据库垃圾数据清理工具启动脚本
# 用于在Linux/macOS环境下启动Java应用程序

# 设置环境变量
JAVA_HOME=${JAVA_HOME:-"/usr/lib/jvm/java-8-oracle"}
ORACLE_HOME=${ORACLE_HOME:-"/u01/app/oracle/product/19.0.0/dbhome_1"}
CLASSPATH="."

# 添加Oracle JDBC驱动到类路径
if [ -d "$ORACLE_HOME/jdbc/lib" ]; then
    for jar in "$ORACLE_HOME"/jdbc/lib/*.jar; do
        CLASSPATH="$CLASSPATH:$jar"
    done
fi

# 如果找不到Oracle JDBC驱动，尝试在当前目录查找
if [ ! -f "$ORACLE_HOME/jdbc/lib/ojdbc8.jar" ] && [ ! -f "$ORACLE_HOME/jdbc/lib/ojdbc7.jar" ]; then
    if [ -f "./ojdbc8.jar" ]; then
        CLASSPATH="$CLASSPATH:./ojdbc8.jar"
    elif [ -f "./ojdbc7.jar" ]; then
        CLASSPATH="$CLASSPATH:./ojdbc7.jar"
    else
        echo "警告: 找不到Oracle JDBC驱动。请确保ojdbc7.jar或ojdbc8.jar在当前目录或Oracle安装目录中。"
        echo "您可以从Oracle官网下载JDBC驱动: https://www.oracle.com/database/technologies/jdbc-drivers-12c-downloads.html"
    fi
fi

# 编译Java程序
echo "编译Java程序..."
"$JAVA_HOME/bin/javac" -cp "$CLASSPATH" OracleDataCleanup.java

if [ $? -ne 0 ]; then
    echo "编译失败，请检查Java环境和代码。"
    exit 1
fi

# 运行Java程序
echo "启动Oracle数据库垃圾数据清理工具..."
"$JAVA_HOME/bin/java" -cp "$CLASSPATH" oracle.data.cleanup.OracleDataCleanup