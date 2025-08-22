iq 16.1 SP 05
rmi port :14001
tds port :14002

步骤1：使用dbisql命令行工具连接：
D:\SAPIQ161\IQ-16_1\Bin64\dbisql.exe -c "uid=sa;pwd=;eng=iqdemo"

步骤2：修改sa密码
CALL sp_iqmodifypassword('sa', 'Secsmart#612');


-- 1. 本地连接（无密码）
D:\SAPIQ161\IQ-16_1\Bin64\dbisql.exe -c "uid=admin;pwd=Secsmart#612;eng=iq_demo"

-- 2. 设置sa密码
ALTER USER sa SET PASSWORD 'Secsmart#612';

-- 3. 启用远程访问
GRANT CONNECT TO PUBLIC;

-- 4. 验证密码
CONNECT TO iq_server USER sa IDENTIFIED BY 'Secur3P@ssw0rd';

# 后台启动
D:\SAPIQ161\IQ-16_1\Bin64\iqsrv16.exe -n iq_demo -x "TCPIP(PORT=2638)" ^
   @C:\ProgramData\SAPIQ\demo\iqdemo.cfg ^
   C:\ProgramData\SAPIQ\demo\iqdemo.db

# 前台启动
# 修改配置文件 兼容中文
SELECT DB_PROPERTY('CharSet') AS "CharSet";


D:\SAPIQ161\IQ-16_1\Bin64\start_iq.exe -n iq_demo ^
   @C:\ProgramData\SAPIQ\demo\iqdemo.cfg ^
   C:\ProgramData\SAPIQ\demo\iqdemo.db


# 找到iqsrv16进程ID
tasklist /FI "IMAGENAME eq iqsrv16.exe"

# 强制终止（替换1234为实际PID）
taskkill /F /PID 1234

# 停止
D:\SAPIQ161\IQ-16_1\Bin64\dbstop.exe -c "UID=admin;PWD=Secsmart#612;SERVER=iq_demo"

# 链接OK
# port:2638 database:iqdemo 172.16.212.175
D:\SAPIQ161\IQ-16_1\Bin64\dbisql.exe -c "character_set=cp936;uid=admin;pwd=Secsmart#612;eng=iq_demo;host=172.16.212.175;port=2638;database=iqdemo"

# 关闭所有iqsrv16实例
taskkill /F /IM iqsrv16.exe

# 关闭所有start_iq实例
taskkill /F /IM start_iq.exe

# 创建测试库
C:\ProgramData\SAPIQ\demo

# 日志文件
C:\ProgramData\SAPIQ\logfiles\iq_demo.002.srvlog
