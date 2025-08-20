iq 16.1 SP 05
rmi port :14001
tds port :14002

步骤1：使用dbisql命令行工具连接：
dbisql -c "uid=sa;pwd=;eng=iq_server"
步骤2：修改sa密码
CALL sp_iqmodifypassword('sa', 'Secsmart#612');


cd D:\SAPIQ161\IQ-16_1\Bin64\

-- 1. 本地连接（无密码）
dbisql.exe -c "uid=sa;pwd=;eng=iq_server"

-- 2. 设置sa密码
ALTER USER sa SET PASSWORD 'Secur3P@ssw0rd';

-- 3. 启用远程访问
GRANT CONNECT TO PUBLIC;

-- 4. 验证密码
CONNECT TO iq_server USER sa IDENTIFIED BY 'Secur3P@ssw0rd';


cd D:\SAPIQ161\IQ-16_1\Bin64
start_iq -n <服务器名> <数据库文件>

cd D:\SAPIQ161\IQ-16_1\Bin64
start_iq.bat @iqconfig.cfg