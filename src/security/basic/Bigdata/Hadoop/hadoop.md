# Hadoop 2.7.7 安装配置规范

## 1. 环境要求
### 1.1 操作系统
- 系统版本：CentOS Linux release 7.9.2009 (Core)
- 系统架构：x86_64

### 1.2 前置依赖
- JDK 版本：1.8.0 及以上
- 所需工具：wget, tar, ssh-keygen
- 系统用户：hdfs (用户组: hadoop)

## 2. 安装规范
### 2.1 软件版本
- Hadoop 版本：2.7.7
- 安装包名：hadoop-2.7.7.tar.gz
- 下载源：Apache 官方镜像或清华镜像

### 2.2 目录规范
```plaintext
/data/hadoop-2.7.7/
├── base/          # 基础安装目录
├── data/          # 数据存储目录
│   ├── namenode/  # NameNode 数据
│   └── datanode/  # DataNode 数据
├── logs/          # 日志目录
└── conf/          # 配置文件目录
```
### 2.3 系统资源配置
- CPU 配置：
  
  - NameNode: 2 核心以上
  - DataNode: 根据实际负载配置
  - MapReduce: 动态调整任务数
- 内存配置：
  
  - NameNode: 系统内存的 20%
  - DataNode: 系统内存的 40%
  - MapReduce: 系统内存的 30%
- HDFS 配置：
  
  - 块大小：128MB
  - 副本数：1
  - 块扫描间隔：21600秒
### 2.4 服务配置
- 系统服务名：hadoop-daemon
- 开机自启动：是
- 服务类型：systemd
- 运行用户：hdfs
- 运行组：hadoop
### 2.5 环境变量
```bash
HADOOP_HOME=/data/hadoop-2.7.7/base
HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
HADOOP_LOG_DIR=/data/hadoop-2.7.7/logs
PATH=${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin:${PATH}
 ```

## 3. 安装流程
1. 环境检查
   
   - 系统版本验证
   - JDK 版本检查
   - 依赖包检查
   - 用户权限验证
2. 安装配置
   
   - 创建目录结构
   - 下载解压安装包
   - 配置环境变量
   - 优化系统参数
3. 服务配置
   
   - 创建系统服务
   - 配置开机自启
   - 设置服务权限
4. 初始化配置
   
   - 格式化 NameNode
   - 创建基础目录
   - 设置目录权限
   - 创建测试数据
## 4. 验证标准
### 4.1 基础验证
- HDFS 服务状态
- 进程运行状态
- 端口监听状态
- 日志文件检查
### 4.2 功能验证
- 创建测试目录：/data/hadoop-2.7.7/data/test
- 创建测试文件：test.txt (内容: hello world)
- 创建系统目录：/tmp, /users
- 设置根目录权限：777
### 4.3 性能验证
- MapReduce 示例程序
- HDFS 读写测试
- 资源使用监控
## 5. 运维支持
- 提供启停脚本
- 提供状态检查脚本
- 提供日志分析工具
- 提供性能监控接口
帮我创建一个一键执行bash脚本。

History：
    On 172.16.48.191 2023-08-10 15:00:00 verify_hadoop.sh执行成功。