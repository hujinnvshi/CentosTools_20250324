# Oracle数据库垃圾数据清理框架

## 概述

本框架提供了一套完整的解决方案，用于自动化识别和清理Oracle数据库中的垃圾数据，包括未使用的表、过期的临时数据、空的表空间和未使用的数据文件等。框架包含PL/SQL后端和Java图形界面前端，可以帮助数据库管理员有效管理数据库空间，提高数据库性能。

## 功能特点

- **自动识别垃圾数据**：基于预定义规则自动识别数据库中的垃圾数据
- **多级清理策略**：支持表、数据文件和表空间三个层次的清理
- **人工审核机制**：清理前可进行人工审核，确保数据安全
- **自动化执行**：支持定时自动执行清理任务
- **操作日志记录**：详细记录所有清理操作，便于审计和回溯
- **图形化界面**：提供直观的Java图形界面，方便操作和监控
- **报告生成**：生成清理报告，展示空间节省情况

## 系统要求

### 数据库环境
- Oracle Database 11g R2 或更高版本
- 具有DBA权限的数据库账户

### 客户端环境
- Java Runtime Environment (JRE) 8 或更高版本
- Oracle JDBC驱动 (ojdbc7.jar 或 ojdbc8.jar)

## 安装步骤

### 1. 安装数据库组件

1. 连接到Oracle数据库：
   ```sql
   sqlplus system/password@database
   ```

2. 执行PL/SQL脚本创建必要的表和存储过程：
   ```sql
   @oracle_data_clean_plsql.sql
   ```

3. 验证安装：
   ```sql
   SELECT table_name FROM user_tables WHERE table_name LIKE 'CLEANUP_%';
   SELECT object_name FROM user_objects WHERE object_type = 'PACKAGE' AND object_name = 'DB_CLEANUP';
   ```

### 2. 安装客户端组件

1. 确保已安装JRE 8或更高版本
2. 将以下文件复制到同一目录：
   - OracleDataCleanup.java
   - start_cleanup_tool.sh (Linux/macOS)
   - start_cleanup_tool.bat (Windows)
   - ojdbc8.jar (如果本地没有Oracle JDBC驱动)

3. 设置执行权限（Linux/macOS）：
   ```bash
   chmod +x start_cleanup_tool.sh
   ```

## 使用方法

### 启动应用程序

- **Linux/macOS**：
  ```bash
  ./start_cleanup_tool.sh
  ```

- **Windows**：
  ```
  start_cleanup_tool.bat
  ```

### 连接到数据库

1. 在连接选项卡中输入数据库连接信息：
   - 主机名
   - 端口号（默认1521）
   - SID或服务名
   - 用户名（需要DBA权限）
   - 密码

2. 点击"连接数据库"按钮

### 配置清理规则

在配置选项卡中，可以调整以下参数：

- **表清理规则**：
  - 未访问天数阈值
  - 空表识别
  - 临时表前缀/后缀

- **数据文件清理规则**：
  - 空闲空间百分比阈值
  - 自动收缩启用

- **表空间清理规则**：
  - 空表空间识别
  - 碎片整理阈值

### 运行分析

1. 在仪表盘选项卡中，点击"运行分析"按钮
2. 如果选中"自动批准清理候选"，系统将自动批准所有识别出的垃圾数据
3. 否则，需要在"清理候选"选项卡中手动审核和批准

### 执行清理

1. 在"清理候选"选项卡中，查看已识别的垃圾数据
2. 选择要清理的项目，点击"批准选中项"按钮
3. 点击"执行已批准的清理"按钮开始清理操作

### 查看报告

在"报告"选项卡中，可以生成清理操作的详细报告，包括：

- 已清理的对象列表
- 每次清理操作节省的空间
- 清理操作的时间统计

## 自动化调度

可以通过Oracle Scheduler设置定期执行清理任务：

```sql
BEGIN
  DBMS_SCHEDULER.CREATE_JOB (
    job_name        => 'DB_CLEANUP_JOB',
    job_type        => 'STORED_PROCEDURE',
    job_action      => 'DB_CLEANUP.RUN_CLEANUP',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=WEEKLY; BYDAY=SUN; BYHOUR=2',
    enabled         => TRUE,
    comments        => '每周日凌晨2点自动运行数据库清理'
  );
END;
/
```

## 注意事项

1. **备份重要数据**：在执行清理操作前，务必备份重要数据
2. **权限要求**：运行此工具需要DBA权限
3. **生产环境使用**：在生产环境使用前，建议先在测试环境进行充分测试
4. **自定义规则**：根据实际业务需求调整清理规则参数
5. **监控清理过程**：大型数据库的清理操作可能需要较长时间，请耐心等待

## 故障排除

### 连接问题

- 确保数据库服务正在运行
- 验证连接信息（主机、端口、SID）是否正确
- 检查用户名和密码是否正确
- 确保网络连接正常

### 编译错误

- 确保已安装JDK 8或更高版本
- 确保CLASSPATH中包含Oracle JDBC驱动

### 权限错误

- 确保使用的数据库用户具有DBA权限
- 检查是否有执行PL/SQL包的权限

## 技术支持

如有问题或需要技术支持，请联系数据库管理员或系统开发团队。

## 许可证

本软件仅供内部使用，未经授权不得分发或用于商业目的。