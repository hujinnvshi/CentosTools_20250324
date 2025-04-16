#!/bin/bash

# 设置环境变量
export HIVE_HOME="/data2/Hive210/base/apache-hive-2.1.0-bin"
export HADOOP_HOME="/data2/Hive210/base/hadoop-2.10.2"
# 设置日志级别为最简
export HADOOP_ROOT_LOGGER="ERROR,NullAppender"
export HIVE_ROOT_LOGGER="ERROR,NullAppender"

# 连接Hive
${HIVE_HOME}/bin/beeline -u "jdbc:hive2://172.16.48.28:10000/default" \
    -n Hive210 \
    --silent=true \
    2>/dev/null