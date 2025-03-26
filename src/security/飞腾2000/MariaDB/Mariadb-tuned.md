# MariaDB 部署需求说明

## 环境信息
- 系统：Kylin Linux Advanced Server V10 (Lance)
- 硬件：飞腾2000芯片
- 数据库：MariaDB 10.11

## 1. 基础配置
### 1.1 系统参数
- 端口：3306
- 字符集：utf8mb4
- 排序规则：utf8mb4_general_ci

### 1.2 账户信息
- root密码：Secsmart#612
- 管理员账户：admin/Secsmart#612

## 2. 部署架构
### 2.1 目录规划
```plaintext
/data/mariadb/
├── base/          # 程序安装目录
├── data/          # 数据存储目录
├── log/           # 日志目录
│   ├── error.log  # 错误日志
│   ├── slow.log   # 慢查询日志
│   └── binlog/    # 二进制日志
├── tmp/           # 临时文件
└── conf/          # 配置文件目录
    └── my.cnf     # 主配置文件
```
## 3. 性能优化
### 3.1 内存配置
- InnoDB缓冲池：系统内存的70%
- 日志缓冲区：16MB
- 查询缓存：禁用（性能考虑）
### 3.2 连接配置
- 最大连接数：10000
- 最大线程数：10000
- 临时表大小：16MB
- 排序缓冲区：2MB
### 3.3 存储配置
- InnoDB日志文件：1GB
- 事务提交：每秒刷新
- 二进制日志保留：7天
## 4. 日志系统
### 4.1 错误日志
- 路径：/data/mariadb/log/error.log
- 级别：ERROR
### 4.2 慢查询日志
- 路径：/data/mariadb/log/slow.log
- 阈值：2秒
- 记录范围：包含未使用索引的查询
### 4.3 二进制日志
- 路径：/data/mariadb/log/binlog/mariadb-bin
- 格式：ROW
- 缓存：1MB
- 同步：每秒刷新
## 5. 安全加固
- 禁用本地文件导入
- 限制包大小：16MB
- SSL加密传输
- 强密码策略
- 限制root远程登录
- 跳过主机名解析
## 6. 高级特性
- 线程池优化
- 表名小写
- 事件调度
- 性能模式
- 审计日志
- 长事务监控
## 7. 验证项目
### 7.1 基础验证
- 服务启动状态
- 数据库连接测试
- 字符集配置验证
### 7.2 功能验证
- 创建测试库：testdb
- 创建测试表：testtable
- 插入测试数据
- 远程连接测试
### 7.3 环境变量
- 配置全局PATH
- 配置服务控制命令
- 配置快捷连接命令
## 8. 运维命令
- 启动：systemctl start mariadb
- 停止：systemctl stop mariadb
- 重启：systemctl restart mariadb
- 状态：systemctl status mariadb
- 连接：mysql -uadmin -p'Secsmart#612'

帮我生成一键安装脚本，方便以后使用,并提供启动数据库，关闭数据库，连接数据库的完整命令