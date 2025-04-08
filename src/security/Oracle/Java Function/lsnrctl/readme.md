LSNRCTL for Linux: Version 11.2.0.1.0 - Production on 28-MAR-2025 15:31:53

Copyright (c) 1991, 2009, Oracle.  All rights reserved.

Connecting to (DESCRIPTION=(ADDRESS=(PROTOCOL=IPC)(KEY=EXTPROC1521)))
STATUS of the LISTENER
------------------------
Alias                     listener
Version                   TNSLSNR for Linux: Version 11.2.0.1.0 - Production
Start Date                28-MAR-2025 09:46:07
Uptime                    0 days 5 hr. 45 min. 46 sec
Trace Level               off
Security                  ON: Local OS Authentication
SNMP                      OFF
Listener Parameter File   /u01/app/oracle/product/11.2.0/db_1/network/admin/listener.ora
Listener Log File         /u01/app/oracle/diag/tnslsnr/oracle11gsin/listener/alert/log.xml
Listening Endpoints Summary...
  (DESCRIPTION=(ADDRESS=(PROTOCOL=ipc)(KEY=EXTPROC1521)))
  (DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)(HOST=oracle11gsin)(PORT=1521)))
Services Summary...
Service "orcl" has 1 instance(s).
  Instance "orcl", status UNKNOWN, has 1 handler(s) for this service...
Service "orcl11g.us.oracle.com" has 1 instance(s).
  Instance "orcl", status READY, has 1 handler(s) for this service...
Service "orclXDB.us.oracle.com" has 1 instance(s).
  Instance "orcl", status READY, has 1 handler(s) for this service...
The command completed successfully

上面是lsnrctl status的输出,我想知道具体是什么含义，以及3条Service是在哪里配置的，如何修改调整。



-- 以 SYSDBA 身份登录
ALTER SYSTEM SET SERVICE_NAMES = '' SCOPE=BOTH;
ALTER SYSTEM SET LOCAL_LISTENER = '' SCOPE=BOTH;
ALTER SYSTEM SET REMOTE_LISTENER = '' SCOPE=BOTH;

show parameter remote_listener;
show parameter service_names;
show parameter local_listener;


-- 以 SYSDBA 身份登录后执行
-- 还原 service_names
ALTER SYSTEM SET SERVICE_NAMES = 'orcl11g.us.oracle.com' SCOPE=BOTH;

-- 还原 local_listener
ALTER SYSTEM SET LOCAL_LISTENER = '(ADDRESS=(PROTOCOL=TCP)(HOST=oracle11gsin)(PORT=1521))' SCOPE=BOTH;

-- 还原 remote_listener（当前为空值，可以不设置）
ALTER SYSTEM SET REMOTE_LISTENER = '' SCOPE=BOTH;

-- 重新注册服务到监听器
ALTER SYSTEM REGISTER;


# 使用 SID 连接（应该成功）
sqlplus system/1@"(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle11gsin)(PORT=1521))(CONNECT_DATA=(SID=orcl)))"

# 使用 SERVICE_NAME 连接（应该失败）
sqlplus system/1@"(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle11gsin)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=orcl)))"