Percona-Server-8.4.0-1-Linux.x86_64.glibc2.17.tar.gz 安装包放置在/tmp

在CentOS Linux release 7.9.2009 (Core) 系统 部署Percona 8.4.1

1. 基础配置：
- 安装 Percona 8.4.1
- root 密码：Secsmart#612
- 端口：3306
- 字符集：utf8mb4
- 排序规则：utf8mb4_general_ci

2. 目录结构：
```plaintext
/data/Percona/
├── base/          # 安装目录
├── data/          # 数据目录
├── log/           # 日志根目录
│   ├── error.log  # 错误日志
│   ├── slow.log   # 慢查询日志
│   └── binlog/    # 二进制日志目录
├── tmp/           # 临时文件目录
└── my.cnf         # 配置文件
```

3. 性能配置：
- InnoDB 缓冲池大小：自动计算（系统内存的 20%）
- InnoDB 日志文件大小：1GB
- InnoDB 日志缓冲区大小：16MB
- 查询缓存大小：0（禁用查询缓存，提升性能）
- 最大连接数：1000
- 最大线程数：1000
- 临时表大小：16M
- 排序缓冲区：2M

4. 日志配置：
- 错误日志：/data/Percona/log/error.log
- 慢查询日志：/data/Percona/log/slow.log
  - 慢查询阈值：2 秒
  - 记录未使用索引的查询
- 二进制日志：
  - 路径：/data/Percona/log/binlog/Percona-bin
  - 格式：ROW
  - 过期时间：7 天
  - 缓存大小：1M
  - 同步策略：每秒刷新

5. 安全配置：
- 禁用 LOCAL INFILE
- 限制最大包大小：16M
- 开启 SSL 连接
- 密码策略：强（STRONG）
- 限制远程 root 登录

6. 其他优化：
- 开启线程池
- 表名小写
- skip-name-resolve（禁用 DNS 解析）
- 开启事件调度器
- 设置时区为 Asia/Shanghai

7. 监控配置：
- 开启性能模式（Performance Schema）
- 启用审计日志
- 记录长事务

这些优化考虑了以下几个方面：
1. 性能优化
2. 安全加固
3. 可维护性
4. 监控能力
5. 运维便利性

安装好后进行连接测试，并创建一个数据库，一个用户，一个表，多个个字段，一个数据。确保安装成功，并且可以正常连接。
安装好后配置全局环境变量，方便以后使用。

帮我生成一键安装bash脚本，方便以后使用,并提供启动数据库，关闭数据库，连接数据库的完整命令


# 启动数据库
systemctl start percona

# 停止数据库
systemctl stop percona

# 重启数据库
systemctl restart percona

# 查看状态
systemctl status percona

# 连接数据库（root用户）
mysql -uroot -pSecsmart#612

# 连接测试数据库（测试用户）
mysql -utest_user -pTest@123 test_db