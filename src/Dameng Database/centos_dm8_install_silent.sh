#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 输出函数
print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" && exit 1; }

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    print_error "请使用root用户执行此脚本"
fi

# 设置变量
INSTALL_DIR="/data/dm8"
SOFT_DIR="/media/dm8"
ISO_FILE="/tmp/dm8_20200907_x86_rh7_64_ent_8.1.1.126.iso"
DB_PORT="6001"
DB_PASSWORD="Secsmart#612"

# 创建目录
print_message "创建安装目录..."
mkdir -p ${INSTALL_DIR} ${SOFT_DIR}
chmod -R 755 ${INSTALL_DIR} ${SOFT_DIR}

# 挂载ISO文件
print_message "挂载ISO文件..."
if [ ! -f "${ISO_FILE}" ]; then
    print_error "ISO文件不存在：${ISO_FILE}"
fi
mount -o loop ${ISO_FILE} ${SOFT_DIR} || print_error "挂载ISO文件失败"

# 生成auto_install.xml
print_message "生成auto_install.xml配置文件..."
cat > ${INSTALL_DIR}/auto_install.xml << EOF
<?xml version="1.0"?>
<DATABASE>
    <LANGUAGE>en</LANGUAGE>
    <TIME_ZONE>+08:00</TIME_ZONE>
    <KEY></KEY>
    <INSTALL_TYPE>0</INSTALL_TYPE>
    <INSTALL_PATH>${INSTALL_DIR}/dmdbms</INSTALL_PATH>
    <INIT_DB>Y</INIT_DB>
    <DB_PARAMS>
        <PATH>${INSTALL_DIR}/dmdbms/data</PATH>
        <DB_NAME>DAMENG</DB_NAME>
        <INSTANCE_NAME>DMSERVER</INSTANCE_NAME>
        <PORT_NUM>${DB_PORT}</PORT_NUM>
        <CTL_PATH></CTL_PATH>
        <LOG_PATHS>
            <LOG_PATH>${INSTALL_DIR}/dmdbms/data/dm01.log</LOG_PATH>
            <LOG_PATH>${INSTALL_DIR}/dmdbms/data/dm02.log</LOG_PATH>
        </LOG_PATHS>
        <EXTENT_SIZE>16</EXTENT_SIZE>
        <PAGE_SIZE>8</PAGE_SIZE>
        <LOG_SIZE>256</LOG_SIZE>
        <CASE_SENSITIVE>Y</CASE_SENSITIVE>
        <CHARSET>0</CHARSET>
        <LENGTH_IN_CHAR>1</LENGTH_IN_CHAR>
        <USE_NEW_HASH>1</USE_NEW_HASH>
        <SYSDBA_PWD>${DB_PASSWORD}</SYSDBA_PWD>
        <SYSAUDITOR_PWD>${DB_PASSWORD}</SYSAUDITOR_PWD>
        <SYSSSO_PWD>${DB_PASSWORD}</SYSSSO_PWD>
        <SYSDBO_PWD>${DB_PASSWORD}</SYSDBO_PWD>
        <TIME_ZONE>+08:00</TIME_ZONE>
        <PAGE_CHECK>0</PAGE_CHECK>
        <EXTERNAL_CIPHER_NAME></EXTERNAL_CIPHER_NAME>
        <EXTERNAL_HASH_NAME></EXTERNAL_HASH_NAME>
        <EXTERNAL_CRYPTO_NAME></EXTERNAL_CRYPTO_NAME>
        <ENCRYPT_NAME></ENCRYPT_NAME>
        <RLOG_ENC_FLAG>N</RLOG_ENC_FLAG>
        <USBKEY_PIN></USBKEY_PIN>
        <BLANK_PAD_MODE>0</BLANK_PAD_MODE>
        <SYSTEM_MIRROR_PATH></SYSTEM_MIRROR_PATH>
        <MAIN_MIRROR_PATH></MAIN_MIRROR_PATH>
        <ROLL_MIRROR_PATH></ROLL_MIRROR_PATH>
        <PRIV_FLAG>0</PRIV_FLAG>
        <ELOG_PATH></ELOG_PATH>
    </DB_PARAMS>
    <CREATE_DB_SERVICE>Y</CREATE_DB_SERVICE>
    <STARTUP_DB_SERVICE>Y</STARTUP_DB_SERVICE>
</DATABASE>
EOF

# 执行安装
print_message "开始安装DM8..."
cd ${SOFT_DIR}
./DMInstall.bin -q ${INSTALL_DIR}/auto_install.xml || print_error "DM8安装失败"

# 配置环境变量
print_message "配置DM8环境变量..."
cat > /etc/profile.d/dm8.sh << EOF
export DM_HOME=${INSTALL_DIR}/dmdbms
export PATH=\$DM_HOME/bin:\$PATH
export LD_LIBRARY_PATH=\$DM_HOME/bin:\$LD_LIBRARY_PATH
EOF

# 加载环境变量
source /etc/profile.d/dm8.sh || print_error "加载环境变量失败"

# 验证环境变量
print_message "验证环境变量..."
if ! command -v disql &>/dev/null; then
    print_error "环境变量配置失败，disql 命令未找到"
else
    print_message "环境变量配置成功"
fi

# 检查服务状态
print_message "检查DM8服务状态..."
if systemctl is-active --quiet DmServiceDMSERVER; then
    print_message "DM8服务已成功启动"
else
    print_error "DM8服务启动失败，请检查日志"
fi

# 测试连接
print_message "测试DM8连接..."
${INSTALL_DIR}/dmdbms/bin/disql SYSDBA/${DB_PASSWORD}@localhost:${DB_PORT} << EOF
select * from v\$instance;
exit;
EOF


# 完成
print_message "DM8安装、配置和测试完成！"

# 打印服务基本信息
print_message "DM8服务基本信息："
echo "安装目录：${INSTALL_DIR}/dmdbms"
echo "数据目录：${INSTALL_DIR}/dmdbms/data"
echo "日志目录：${INSTALL_DIR}/dmdbms/data"
echo "端口号：${DB_PORT}"
echo "SYSDBA密码：${DB_PASSWORD}"

# 打印使用连接信息
print_message "DM8使用连接信息："
echo "1. 使用disql连接数据库："
echo "   ${INSTALL_DIR}/dmdbms/bin/disql SYSDBA/${DB_PASSWORD}@localhost:${DB_PORT}"
echo "2. 使用systemctl管理服务："
echo "   启动服务：systemctl start DmServiceDMSERVER"
echo "   停止服务：systemctl stop DmServiceDMSERVER"
echo "   重启服务：systemctl restart DmServiceDMSERVER"
echo "   查看状态：systemctl status DmServiceDMSERVER"
echo "3. 日志文件位置："
echo "   错误日志：${INSTALL_DIR}/dmdbms/data/DAMENG/DAMENG.log"
echo "   慢查询日志：${INSTALL_DIR}/dmdbms/data/DAMENG/DAMENG_slow.log"