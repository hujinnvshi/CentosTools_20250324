sqlplus sys/1 as sysdba


CREATE PFILE='/tmp/pfile_temp.ora' FROM SPFILE;
vi /tmp/pfile_temp.ora


CREATE SPFILE='/data/oracle/product/11.2.0/db_1/dbs/spfileorcl.ora' FROM PFILE='/tmp/pfile_temp.ora';

SHUTDOWN IMMEDIATE;
STARTUP;



yum install -y rlwrap
echo "alias sqlplus='rlwrap sqlplus'" >> ~/.bashrc && source ~/.bashrc