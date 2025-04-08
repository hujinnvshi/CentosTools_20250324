Service "orcl" has 1 instance(s).
Instance "orcl", status UNKNOWN, has 1 handler(s) for this service... 如何不显式这一个Service
要移除 "orcl" 服务的显示，我们需要：

1. 删除静态注册配置：
```plaintext:/u01/app/oracle/product/11.2.0/db_1/network/admin/listener.ora
# 删除或注释以下配置
# SID_LIST_LISTENER =
#   (SID_LIST =
#     (SID_DESC =
#       (SID_NAME = orcl)
#       (ORACLE_HOME = /u01/app/oracle/product/11.2.0/db_1)
#     )
#   )
```

2. 执行以下 SQL 命令：
```sql
-- 以 SYSDBA 身份登录
-- 删除 orcl 服务
EXEC DBMS_SERVICE.DELETE_SERVICE('orcl');

-- 确保只保留需要的服务名
ALTER SYSTEM SET SERVICE_NAMES = 'orcl11g.us.oracle.com' SCOPE=BOTH;

-- 重新注册服务
ALTER SYSTEM REGISTER;
```

3. 重启监听器：
```bash
lsnrctl stop
lsnrctl start
```

4. 验证结果：
```bash
lsnrctl status
```

注意：这样操作后，通过 SID 的连接方式将不可用，只能使用 SERVICE_NAME 方式连接。