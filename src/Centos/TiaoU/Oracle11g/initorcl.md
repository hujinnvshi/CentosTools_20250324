sqlplus sys/1 as sysdba


CREATE PFILE='/tmp/pfile_temp.ora' FROM SPFILE;
vi /tmp/pfile_temp.ora


CREATE SPFILE='/data/oracle/product/11.2.0/db_1/dbs/spfileorcl.ora' FROM PFILE='/tmp/pfile_temp.ora';

startup pfile='/data/oracle12102/app/dbs/initorcl12.ora';

SHUTDOWN IMMEDIATE;
STARTUP;



yum install -y rlwrap
echo "alias sqlplus='rlwrap sqlplus'" >> ~/.bashrc && source ~/.bashrc



sqlplus / as sysdba
SQL> startup mount;
SQL> alter system set local_listener='(ADDRESS=(PROTOCOL=TCP)(HOST=kafka)(PORT=1531))' scope=both;
SQL> alter system set db_domain='' scope=spfile;
SQL> alter system register;
SQL> shutdown immediate;
SQL> startup;