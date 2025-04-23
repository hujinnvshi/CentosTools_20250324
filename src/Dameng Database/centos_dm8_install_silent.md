一、环境准备
[root@dameng1 /]# mkdir dm8

[root@dameng1 /]# mkdir soft

[root@dameng1 soft]# chmod -R 755 /soft

[root@dameng1 soft]# chmod -R 755 /dm8

操作系统：Centos7
安装版本：/tmp/dm8_20200907_x86_rh7_64_ent_8.1.1.126.iso
数据库端口设置为：6001
数据库密码：Secsmart#612

二、安装
 说明：可以用dmdba用户安装，也可以用root用户安装。dmdba用户安装的话，是无法创建数据库服务的，因此CREATE_DB_SERVICE一定要设置为N，不然会报错。我们一般使用root用户安装。

1、安装命令：
./DMInstall.bin -q /soft/auto_install.xml

注意：虽然我DMInstall.bin和auto_install.xml在同一目录下，但是安装的时候还是需要指定auto_install.xml的全路径/soft/auto_install.xml，不然会报错。

2、auto_install.xml文件
复制代码
<?xml version="1.0"?>
<DATABASE>
    <!--安装数据库的语言配置，安装中文版配置 ZH，英文版配置 EN，不区分大小写。不允许为空。-->
    <LANGUAGE>en</LANGUAGE>
    <!--安装程序的时区配置，默认值为+08:00，范围：-12:59 ~ +14:00 -->
    <TIME_ZONE>+08:00</TIME_ZONE>
    <!-- key 文件路径 -->
    <KEY></KEY>
    <!--安装程序组件类型，取值 0、1、2，0 表示安装全部，1 表示安装服务器，2 表示安装客户端。默认为 0。 -->
    <INSTALL_TYPE>0</INSTALL_TYPE>
    <!--安装路径，不允许为空。 -->
    <INSTALL_PATH>/data/dm8/dmdbms</INSTALL_PATH>
    <!--是否初始化库，取值 Y/N、y/n，不允许为空。 -->
    <INIT_DB>Y</INIT_DB>
    <!--数据库实例参数 -->
    <DB_PARAMS>
    <!--初始数据库存放的路径，不允许为空 -->
    <PATH>/data/dm8/dmdbms/data</PATH>
    <!--初始化数据库名字，默认是 DAMENG，不超过 128 个字符 -->
    <DB_NAME>DAMENG</DB_NAME>
    <!--初始化数据库实例名字，默认是 DMSERVER，不超过 128 个字符 -->
    <INSTANCE_NAME>DMSERVER</INSTANCE_NAME>
    <!--初始化时设置 dm.ini 中的 PORT_NUM，默认 5236，取值范围：1024~65534 -->
    <PORT_NUM>5236</PORT_NUM>
    <!--初始数据库控制文件的路径，文件路径长度最大为 256 -->
    <CTL_PATH></CTL_PATH>
    <!--初始数据库日志文件的路径，文件路径长度最大为 256 -->
    <LOG_PATHS>
        <LOG_PATH>/data/dm8/dmdbms/data/dm01.log</LOG_PATH>
        <LOG_PATH>/data/dm8/dmdbms/data/dm02.log</LOG_PATH>
    </LOG_PATHS>
    <!--数据文件使用的簇大小，只能是 16 页或 32 页之一，缺省使用 16 页 -->
    <EXTENT_SIZE>16</EXTENT_SIZE>
    <!--数据文件使用的页大小，缺省使用 8K，只能是 4K、8K、16K 或 32K 之一 -->
    <PAGE_SIZE>8</PAGE_SIZE>
    <!--日志文件使用的簇大小，默认是 256，取值范围 64 和 2048 之间的整数 -->
    <LOG_SIZE>256</LOG_SIZE>
    <!--标识符大小写敏感，默认值为 Y。只能是’Y’, ’y’, ’N’, ’n’, ’1’, ’0’之一 -->
    <CASE_SENSITIVE>Y</CASE_SENSITIVE>
    <!--字符集选项，默认值为 0。0 代表 GB18030,1 代表 UTF-8,2 代表韩文字符集 EUC-KR-->
    <CHARSET>0</CHARSET>
    <!--设置为 1 时，所有 VARCHAR 类型对象的长度以字符为单位，否则以字节为单位。默认值为 0。 -->
    <LENGTH_IN_CHAR>0</LENGTH_IN_CHAR>
    <!--字符类型在计算 HASH 值时所采用的 HASH 算法类别。0：原始 HASH 算法；1：改进的HASH 算法。默认值为 1。 -->
    <USE_NEW_HASH>1</USE_NEW_HASH>
    <!--初始化时设置 SYSDBA 的密码，默认为 SYSDBA，长度在 9 到 48 个字符之间 -->
    <SYSDBA_PWD></SYSDBA_PWD>
    <!--初始化时设置 SYSAUDITOR 的密码，默认为 SYSAUDITOR，长度在 9 到 48 个字符之间 -->
    <SYSAUDITOR_PWD></SYSAUDITOR_PWD>
    <!--初始化时设置 SYSSSO 的密码，默认为 SYSSSO，长度在 9 到 48 个字符之间，仅在安全版本下可见和可设置 -->
    <SYSSSO_PWD></SYSSSO_PWD>
    <!--初始化时设置 SYSDBO 的密码，默认为 SYSDBO，长度在 9 到 48 个字符之间，仅在安全版本下可见和可设置 -->
    <SYSDBO_PWD></SYSDBO_PWD>
    <!--初始化时区，默认是东八区。格式为：正负号小时：分钟，范围：-12:59 ~ +14:00-->
    <TIME_ZONE>+08:00</TIME_ZONE>
    <!--是否启用页面内容校验，0：不启用；1：简单校验；2：严格校验(使用 CRC16 算法生成校验码)。默认 0 -->
    <PAGE_CHECK>0</PAGE_CHECK>
    <!--设置默认加密算法，不超过 128 个字符 -->
    <EXTERNAL_CIPHER_NAME></EXTERNAL_CIPHER_NAME>
    <!--设置默认 HASH 算法，不超过 128 个字符 -->
    <EXTERNAL_HASH_NAME></EXTERNAL_HASH_NAME>
    <!--设置根密钥加密引擎，不超过 128 个字符 -->
    <EXTERNAL_CRYPTO_NAME></EXTERNAL_CRYPTO_NAME>
    <!--全库加密密钥使用的算法名。算法可以是 DM 内部支持的加密算法，或者是第三方的加密算法。默认使用"AES256_ECB"算法加密，最长为 128 个字节 -->
    <ENCRYPT_NAME></ENCRYPT_NAME>
    <!--指定日志文件是否加密。默认值 N。取值 Y/N，y/n，1/0 -->
    <RLOG_ENC_FLAG>N</RLOG_ENC_FLAG>
    <!--用于加密服务器根密钥，最长为 48 个字节 -->
    <USBKEY_PIN></USBKEY_PIN>
    <!--设置空格填充模式，取值 0 或 1，默认为 0 -->
    <BLANK_PAD_MODE>0</BLANK_PAD_MODE>
    <!--指定 system.dbf 文件的镜像路径，默认为空 -->
    <SYSTEM_MIRROR_PATH></SYSTEM_MIRROR_PATH>
    <!--指定 main.dbf 文件的镜像路径，默认为空 -->
    <MAIN_MIRROR_PATH></MAIN_MIRROR_PATH>
    <!--指定 roll.dbf 文件的镜像路径，默认为空 -->
    <ROLL_MIRROR_PATH></ROLL_MIRROR_PATH>
    <!--是否是四权分立，默认值为 0(不使用)。仅在安全版本下可见和可设置。只能是 0 或 1-->
    <PRIV_FLAG>0</PRIV_FLAG>
    <!--指定初始化过程中生成的日志文件所在路径。合法的路径，文件路径长度最大为 257(含结束符)，不包括文件名-->
    <ELOG_PATH></ELOG_PATH>
    </DB_PARAMS>
    <!--是否创建数据库实例的服务，值 Y/N y/n，不允许为空，不初始化数据库将忽略此节点。非 root 用户不能创建数据库服务。 -->
    <CREATE_DB_SERVICE>Y</CREATE_DB_SERVICE>
    <!--是否启动数据库，值 Y/N y/n，不允许为空，不创建数据库服务将忽略此节点。 -->
    <STARTUP_DB_SERVICE>Y</STARTUP_DB_SERVICE>
</DATABASE>
复制代码
3、执行安装
复制代码
[root@dameng1 soft]# ./DMInstall.bin -q /soft/auto_install.xml
Extract install files..........
2021-08-19 11:34:45
[INFO] Installing DM DBMS...
2021-08-19 11:34:45
[INFO] Installing BASE Module...
2021-08-19 11:35:15
[INFO] Installing SERVER Module...
2021-08-19 11:35:17
[INFO] Installing CLIENT Module...
2021-08-19 11:36:16
[INFO] Installing DRIVERS Module...
2021-08-19 11:36:24
[INFO] Installing MANUAL Module...
2021-08-19 11:36:27
[INFO] Installing SERVICE Module...
2021-08-19 11:36:31
[INFO] Move log file to log directory.
2021-08-19 11:36:32
[INFO] Change the power of installtion directory successfully.
2021-08-19 11:36:32
[INFO] Starting DmAPService service...
2021-08-19 11:36:34
[INFO] Start DmAPService service successfully.
2021-08-19 11:36:34
[INFO] Installed DM DBMS completely.
2021-08-19 11:36:38
[INFO] Creating database...
2021-08-19 11:36:42
[INFO] Create database completed.
2021-08-19 11:36:42
[INFO] Creating database service...
2021-08-19 11:36:42
[INFO] Create database service completed.
2021-08-19 11:36:42
[INFO] Starting the database service(DmServiceDMSERVER)...
2021-08-19 11:36:58
[INFO] Start the database service(DmServiceDMSERVER) success!
复制代码
注意：

LANGUAGE默认值为zh，安装时报如下错：

 

原因是我操作系统是英文，xml文件的LANGUAGE应该为en，如果操作系统是中文，则LANGUAGE=zh，LANGUAGE值不区分大小写。

4、disql连接试试
 

三、注意点
1、这三个参数没有默认值，并且是必填的，不填会报错
<INSTALL_PATH>/data/dm8/dmdbms</INSTALL_PATH>

<INIT_DB>Y</INIT_DB>

<PATH>/data/dm8/dmdbms/data</PATH>

2、LOG_PATHS
我是这样配置的：

<LOG_PATHS>

       <LOG_PATH>/data/dm8/dmdbms/data/dm01.log</LOG_PATH>

       <LOG_PATH>/data/dm8/dmdbms/data/dm02.log</LOG_PATH>

</LOG_PATHS>

其实可以不配置LOG_PATH，如下所示：

<LOG_PATHS>

       <LOG_PATH> </LOG_PATH>

</LOG_PATHS>

不配置redo日志路径，会在数据库安装目录下自动生成两个和数据库实例同名的日志文件。比如我数据库实例名叫DAMENG，安装在/data/dm8/dmdbms/data/目录下，那么会在/data/dm8/dmdbms/data/DAMENG下生成DAMENG01.log和DAMENG02.log这两个redo日志文件。

redo日志文件数量大于等于2，如果想指定日志文件位置和名称的话，一定要注意数量。

3、是否创建服务
CREATE_DB_SERVICE=Y会自动创建数据库服务，比如是用root安装才能创建，如果是用dmdba用户安装，CREATE_DB_SERVICE=Y的话会报错。STARTUP_DB_SERVICE=Y的话会自动启动数据库服务，这样可以验证是否真的安装成功。STARTUP_DB_SERVICE=Y的话，CREATE_DB_SERVICE必须也等于Y，如果CREATE_DB_SERVICE=N的话，并不会报错，而是直接忽略CREATE_DB_SERVICE的配置。

4、服务启动失败
我在其他服务器用root静默安装的时候，在最后一步用服务启动报错，其实数据库安装成功了，服务也成功创建了，进入bin目录下./DmserviceDMSERVER start启动成功，就是不支持systemctl start DmServiceDMSERVER。

解决方式如下：

vi /etc/selinux/config

修改SELINUX=disabled

修改完后需要重启服务器。

因为是内网服务器，就不截图了，我本地没复现出来。