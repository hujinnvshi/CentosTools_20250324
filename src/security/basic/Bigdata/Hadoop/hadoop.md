# Hadoop 2.7.7 安装配置需求

## 环境前提
- CentOS Linux release 7.9.2009 (Core)
- Java 环境已正确配置（JDK 1.8）

## 安装要求
1. 软件版本
   - Hadoop 版本：2.7.7
   - 安装包：hadoop-2.7.7.tar.gz

2. 安装路径
   - 基础目录：/data/hadoop-2.7.7/base
   - 数据目录：/data/hadoop-2.7.7/data
   - 日志目录：/data/hadoop-2.7.7/logs

3. 配置要求
   - 配置环境变量（HADOOP_HOME 等）
   - 根据系统资源自动优化配置：
     * CPU 核心数动态配置
     * 内存使用率合理分配
     * HDFS 块大小优化
     * MapReduce 任务数优化

4. 系统服务
   - 配置为系统服务
   - 开机自动启动
   - 支持服务管理（start/stop/restart）

5. 测试验证
   - HDFS 基础功能测试
   - MapReduce 示例程序测试
   - 集群状态监控检查

## 安装步骤
1. 下载安装包
2. 解压配置文件
3. 环境变量配置
4. 系统参数优化
5. 服务配置启动
6. 功能测试验证

## 预期结果
- Hadoop 服务正常运行
- 开机自动启动
- 资源利用合理
- 基础功能正常

帮我创建一个一键执行bash脚本。