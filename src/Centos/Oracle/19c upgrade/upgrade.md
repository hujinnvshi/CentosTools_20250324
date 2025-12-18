升级 Oracle 19c 从**19.3.0.0.0（初始版本）** 到**19.21.0.0.0（第 21 个 Release Update，RU）** 是典型的「累计补丁升级」（Oracle 19c 的 RU 为累计更新，无需逐个安装 19.4~19.20，直接装 19.21 即可）。以下是**单实例环境的完整升级步骤**（RAC 集群需额外处理，文末补充），包含前提准备、实操步骤、验证与回滚，确保升级安全可控。

### 核心前提（必看，避免升级失败）

1. **版本兼容性**：Oracle 19c 支持「跨 RU 直接升级」，19.3 可直接升级到 19.21，无需逐版本安装中间 RU；
2. **MOS 账号**：需 Oracle 官方 My Oracle Support (MOS)账号，下载 19.21 的 RU 补丁（补丁需匹配操作系统平台，如 Linux x86-64）；
3. **OPatch 版本要求**：必须升级 OPatch 到支持 19.21 RU 的版本（最低要求 OPatch 12.2.0.1.39+，建议升级到最新版）；
4. **备份兜底**：升级前必须做「全库备份+软件目录备份」，防止升级失败无法回滚；
5. **环境检查**：
   - 数据库无无效对象、无长期运行的事务、归档模式已开启；
   - 操作系统满足补丁要求（如 Linux 内核版本、glibc 版本，参考 MOS 补丁说明）；
   - 磁盘空间 ≥ 补丁大小的 2 倍（19c RU 补丁约 2-5GB）。

### 步骤 1：下载所需文件（MOS 操作）

1. 登录 MOS（https://support.oracle.com/）；
2. 搜索补丁编号：**19.21.0.0.0 RU**（对应补丁号如`36203641`，不同平台编号不同，关键词「Oracle Database 19c Release Update 21」）；
3. 下载对应平台的 RU 补丁包（如 Linux x86-64 的`p36203641_190000_Linux-x86-64.zip`）；
4. 下载最新 OPatch 工具（MOS 搜索「OPatch 19c」，下载对应版本如`p6880880_190000_Linux-x86-64.zip`）。

### 步骤 2：升级前备份（核心兜底）

#### 2.1 全库 RMAN 备份（推荐）

```bash
# 登录Oracle用户，启动RMAN
rman target /

# 全库备份（包含控制文件、归档日志）
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK FORMAT '/backup/rman_full_%U.bkp';
  BACKUP FULL DATABASE PLUS ARCHIVELOG;
  BACKUP CURRENT CONTROLFILE;
  RELEASE CHANNEL c1;
}
exit;
```

#### 2.2 备份 Oracle 软件目录

```bash
# 停止数据库后，备份ORACLE_HOME（示例路径：/u01/app/oracle/product/19c/dbhome_1）
tar -zcvf /backup/oracle_home_19.3.tar.gz /u01/app/oracle/product/19c/dbhome_1
```

### 步骤 3：升级 OPatch 工具

OPatch 是 Oracle 补丁管理工具，旧版本无法识别新 RU，必须先升级：

```bash
# 1. 切换到Oracle用户
su - oracle

# 2. 进入ORACLE_HOME目录，备份旧OPatch
cd $ORACLE_HOME
mv OPatch OPatch_OLD

# 3. 解压新OPatch包（假设下载到/opt/patches）
unzip /opt/patches/p6880880_190000_Linux-x86-64.zip -d $ORACLE_HOME

# 4. 验证OPatch版本（需≥12.2.0.1.39）
$ORACLE_HOME/OPatch/opatch version
```

### 步骤 4：应用 19.21 RU 补丁（核心操作）

#### 4.1 停止数据库及相关服务

```bash
# 1. 关闭数据库实例
sqlplus / as sysdba
SHUTDOWN IMMEDIATE;
EXIT;

# 2. 关闭监听（若监听在ORACLE_HOME下）
lsnrctl stop

# 3. 关闭EM（若启用）
emctl stop dbconsole
```

#### 4.2 解压并应用 RU 补丁

```bash
# 1. 解压RU补丁包到临时目录
mkdir -p /opt/patches/19.21
unzip /opt/patches/p36203641_190000_Linux-x86-64.zip -d /opt/patches/19.21

# 2. 进入补丁目录，检查补丁兼容性（预检查）
cd /opt/patches/19.21/36203641
$ORACLE_HOME/OPatch/opatch prereq CheckConflictAgainstOHWithDetail -ph ./

# 3. 应用补丁（无冲突则执行）
$ORACLE_HOME/OPatch/opatch apply -silent

# 4. 检查补丁应用状态（确认19.21 RU已安装）
$ORACLE_HOME/OPatch/opatch lsinventory
```

### 步骤 5：升级数据库数据字典（关键，易遗漏）

应用补丁后，需升级数据库数据字典，使内核与字典版本一致：

```bash
# 1. 启动数据库到UPGRADE模式
sqlplus / as sysdba
STARTUP UPGRADE;
EXIT;

# 2. 运行catctl.pl升级脚本（Oracle 19c推荐用并行升级）
cd $ORACLE_HOME/rdbms/admin
$ORACLE_HOME/perl/bin/perl catctl.pl -n 4 catupgrd.sql  # -n 4表示4并行进程，根据CPU调整

# 3. 升级完成后，启动数据库到正常模式
sqlplus / as sysdba
SHUTDOWN IMMEDIATE;
STARTUP;

# 4. 编译无效对象（升级后会产生无效对象，需重建）
@?/rdbms/admin/utlrp.sql

# 5. 验证无效对象（需为0或业务无关对象）
SELECT COUNT(*) FROM dba_objects WHERE status = 'INVALID';
```

### 步骤 6：验证升级结果

```bash
# 1. 检查数据库版本（需显示19.21.0.0.0）
sqlplus / as sysdba
SELECT * FROM v$version;
# 预期输出：Oracle Database 19c Enterprise Edition Release 19.0.0.0.0 - Production
# Version 19.21.0.0.0

# 2. 检查补丁信息
SELECT patch_id, patch_type, status FROM dba_registry_sqlpatch;
# 确认19.21的RU补丁状态为APPLIED

# 3. 启动监听并验证连接
lsnrctl start
sqlplus 用户名/密码@数据库服务名  # 验证业务连接正常
```

### 步骤 7：回滚方案（升级失败时）

若升级后出现异常，可通过 OPatch 回滚补丁：

```bash
# 1. 停止数据库和监听
sqlplus / as sysdba
SHUTDOWN IMMEDIATE;
EXIT;
lsnrctl stop

# 2. 回滚19.21 RU补丁（补丁号替换为实际编号）
$ORACLE_HOME/OPatch/opatch rollback -id 36203641

# 3. 恢复数据字典（启动到降级模式）
sqlplus / as sysdba
STARTUP DOWNGRADE;
@$ORACLE_HOME/rdbms/admin/catdwgrd.sql  # 执行降级脚本
SHUTDOWN IMMEDIATE;
STARTUP;
@?/rdbms/admin/utlrp.sql  # 重新编译对象

# 4. 验证回滚后的版本（回到19.3.0.0.0）
SELECT * FROM v$version;
```

### 补充：RAC 集群环境的额外注意事项

若你的 Oracle 19c 是 RAC 集群，需在**所有节点**执行以下差异步骤：

1. 补丁应用前，停止集群服务：`crsctl stop crs`（所有节点）；
2. 在「主节点」应用补丁后，同步到其他节点：`opatch apply -remote_nodes node2,node3`；
3. 数据字典升级仅需在「一个节点」执行，无需所有节点操作；
4. 升级后验证集群状态：`crsctl check cluster -all`。

### 关键注意事项

1. **测试环境先行**：务必先在测试环境验证升级，确认业务 SQL、存储过程、第三方工具（如 Toad、DataGuard）兼容 19.21；
2. **补丁匹配平台**：确保下载的 RU 补丁与操作系统（Linux/AIX/Windows）、位数（x86-64/ARM）完全匹配；
3. **时间窗口**：单实例升级约 30-60 分钟，RAC 约 1-2 小时，需预留业务停机窗口；
4. **MOS 文档参考**：升级前查阅 MOS 文档「Oracle Database 19c Release Update (RU) Release Notes」（Doc ID 2580992.1），确认 19.21 的已知问题；
5. **参数检查**：升级后检查`init.ora`/`spfile`，确保无废弃参数（Oracle 19c 后续 RU 可能废弃部分参数）。

### 总结

升级核心流程：`备份 → 升级OPatch → 停库 → 应用RU补丁 → 升级数据字典 → 验证`。19c 的 RU 是累计更新，直接装 19.21 即可覆盖 19.3 到 19.21 的所有修复，升级后需重点验证业务功能、无效对象、集群状态（RAC），确保无兼容性问题。
