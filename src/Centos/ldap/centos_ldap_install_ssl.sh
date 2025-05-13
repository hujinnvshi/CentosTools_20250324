#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 日志函数
log() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    error "请使用 root 用户执行此脚本"
fi

# 检查端口占用
if netstat -tuln | grep -q ':389'; then
    error "端口 389 已被占用。请先停止占用该端口的服务。"
fi
if netstat -tuln | grep -q ':636'; then
    error "端口 636 已被占用。请先停止占用该端口的服务。"
fi

# 检查LDAP服务状态
if ps aux | grep slapd | grep -v grep > /dev/null; then
    error "LDAP 服务似乎已在运行。请先停止现有服务。"
fi

# 设置 LDAP 基本配置
LDAP_DOMAIN="example.com"
LDAP_SUFFIX="dc=example,dc=com"
LDAP_ROOTPW="Secsmart#612"  # 管理员密码
LDAP_ORGANIZATION="Example Inc"
LDAP_HOST=$(hostname -I | awk '{print $1}') # 自动获取本机IP作为LDAP_HOST
LDAP_PORT="389"             # LDAP服务端口
LDAPS_PORT="636"            # LDAPS服务端口

# SSL证书相关路径
SSL_CERT_DIR="/etc/openldap/certs"
SSL_KEY_FILE="${SSL_CERT_DIR}/ldap.key"
SSL_CSR_FILE="${SSL_CERT_DIR}/ldap.csr"
SSL_CERT_FILE="${SSL_CERT_DIR}/ldap.crt"


log "LDAP 服务器 IP 将使用: $LDAP_HOST"
log "LDAP 管理员密码将是: $LDAP_ROOTPW (请在生产环境中更改)"

# 创建临时目录
TEMP_DIR=$(mktemp -d)
CHROOTPW_LDIF="${TEMP_DIR}/chrootpw.ldif"
DB_LDIF="${TEMP_DIR}/db.ldif"
BASE_LDIF="${TEMP_DIR}/base.ldif"
SSL_LDIF="${TEMP_DIR}/ssl.ldif" # 新增SSL LDIF文件变量
# trap 'rm -rf "${TEMP_DIR}"' EXIT
trap 'echo "清理临时目录: $TEMP_DIR"' EXIT

# 清理现有配置
log "清理现有配置..."
systemctl stop slapd >/dev/null 2>&1 || true # 尝试停止服务，以防万一
rm -rf /etc/openldap/slapd.d/*
rm -rf /var/lib/ldap/*
rm -rf ${SSL_CERT_DIR}/* # 清理旧证书

# 安装必要的软件包
log "安装 OpenLDAP 及相关工具 (包括 openssl)..."
yum -y install openldap compat-openldap openldap-servers openldap-servers-sql openldap-clients openldap-devel migrationtools openssl || error "安装 OpenLDAP 或 openssl 失败"

# 生成SSL证书
log "生成自签名SSL证书..."
mkdir -p "$SSL_CERT_DIR"
openssl genpkey -algorithm RSA -out "$SSL_KEY_FILE" -pkeyopt rsa_keygen_bits:2048 || error "生成私钥失败"
openssl req -new -key "$SSL_KEY_FILE" -out "$SSL_CSR_FILE" -subj "/CN=${LDAP_HOST}" || error "生成CSR失败"
openssl x509 -req -days 3650 -in "$SSL_CSR_FILE" -signkey "$SSL_KEY_FILE" -out "$SSL_CERT_FILE" || error "生成自签名证书失败"
chown -R ldap:ldap "$SSL_CERT_DIR"
chmod 600 "$SSL_KEY_FILE"
chmod 644 "$SSL_CERT_FILE" "$SSL_CSR_FILE"
log "SSL证书已生成在 $SSL_CERT_DIR"

# 配置slapd服务以监听ldaps
log "配置slapd服务以包含ldaps..."
if [ -f /etc/sysconfig/slapd ]; then
    if grep -q "^SLAPD_URLS=" /etc/sysconfig/slapd; then
        sed -i 's|^SLAPD_URLS=.*|SLAPD_URLS="ldap:/// ldapi:/// ldaps:///"|' /etc/sysconfig/slapd
    else
        echo 'SLAPD_URLS="ldap:/// ldapi:/// ldaps:///"' >> /etc/sysconfig/slapd
    fi
else
    log "警告: /etc/sysconfig/slapd 文件未找到。可能需要手动配置slapd启动参数以包含ldaps。"
    # 作为备选，可以直接修改slapd.service文件或通过其他方式配置，但sysconfig是CentOS的常用方法
fi


# 生成管理员密码
log "配置管理员密码..."
HASHED_PW=$(slappasswd -s "$LDAP_ROOTPW")
if [ $? -ne 0 ] || [ -z "$HASHED_PW" ]; then
    error "生成密码哈希失败"
fi
log "密码哈希: $HASHED_PW"


# 创建数据目录
log "创建数据目录 (/var/lib/ldap)..."
mkdir -p /var/lib/ldap
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown -R ldap:ldap /var/lib/ldap
chmod 700 /var/lib/ldap

# 创建运行目录
log "创建运行目录 (/var/run/openldap)..."
mkdir -p /var/run/openldap
chown -R ldap:ldap /var/run/openldap
chmod 700 /var/run/openldap

# 创建slapd配置文件
log "创建slapd配置文件 (/etc/openldap/slapd.conf)..."
cat > /etc/openldap/slapd.conf << EOF
include         /etc/openldap/schema/core.schema
include         /etc/openldap/schema/cosine.schema
include         /etc/openldap/schema/nis.schema
include         /etc/openldap/schema/inetorgperson.schema

pidfile         /var/run/openldap/slapd.pid
argsfile        /var/run/openldap/slapd.args

# TLS Configuration (slaptest -u will convert these if needed, but we'll set via LDIF later for cn=config)
# TLSCACertificatePath $SSL_CERT_DIR
# TLSCertificateFile $SSL_CERT_FILE
# TLSCertificateKeyFile $SSL_KEY_FILE

database        mdb
suffix          "$LDAP_SUFFIX"
rootdn          "cn=admin,$LDAP_SUFFIX"
rootpw          $HASHED_PW
directory       /var/lib/ldap

index objectClass                       eq,pres
index ou,cn,mail,surname,givenname      eq,pres,sub
index uidNumber,gidNumber,loginShell    eq,pres
index uid,memberUid                     eq,pres,sub
index nisMapName,nisMapEntry            eq,pres,sub
index entryCSN,entryUUID                eq

access to attrs=userPassword,shadowLastChange
        by self write
        by anonymous auth
        by dn="cn=admin,$LDAP_SUFFIX" write
        by * write

access to *
        by self write
        by dn="cn=admin,$LDAP_SUFFIX" write
        by * write
EOF

chown ldap:ldap /etc/openldap/slapd.conf
chmod 640 /etc/openldap/slapd.conf

# 检查配置文件 (slaptest -u, 检查slapd.conf并尝试生成slapd.d的初始结构)
log "检查配置文件并生成初始slapd.d (slaptest -u)..."
rm -rf /etc/openldap/slapd.d/* # 清理旧的slapd.d内容
mkdir -p /etc/openldap/slapd.d
chown -R ldap:ldap /etc/openldap/slapd.d
chmod 700 /etc/openldap/slapd.d
slaptest -u -f /etc/openldap/slapd.conf -F /etc/openldap/slapd.d || error "配置文件检查失败 (slaptest -u)"

# 确保slapd.d目录权限在slaptest -u后依然正确
chown -R ldap:ldap /etc/openldap/slapd.d
chmod 700 /etc/openldap/slapd.d

# 尝试停止任何可能正在运行的旧slapd进程 (slaptest -u 可能不会停止服务)
log "尝试再次停止任何旧的 LDAP 服务..."
systemctl stop slapd >/dev/null 2>&1 || true
# kill $(ps aux | grep slapd | grep -v grep | awk '{print $2}') 2>/dev/null || true # 保留以防systemctl失败
sleep 2

# 再次确保数据目录是干净的并设置权限 (因为slaptest -u可能不会清理旧数据)
log "再次清理并准备数据目录..."
rm -rf /var/lib/ldap/*
mkdir -p /var/lib/ldap
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown -R ldap:ldap /var/lib/ldap
chmod 700 /var/lib/ldap

# 再次确保配置目录是干净的并设置权限 (slaptest -u可能已创建内容，但我们要用slaptest -f覆盖)
log "再次清理并准备配置目录 (/etc/openldap/slapd.d)..."
rm -rf /etc/openldap/slapd.d/*
mkdir -p /etc/openldap/slapd.d
chown -R ldap:ldap /etc/openldap/slapd.d
chmod 700 /etc/openldap/slapd.d

# 使用slaptest生成最终的slapd.d配置（不带-u选项，仅转换slapd.conf到slapd.d）
log "使用slaptest生成最终的slapd.d配置..."
slaptest -f /etc/openldap/slapd.conf -F /etc/openldap/slapd.d
chown -R ldap:ldap /etc/openldap/slapd.d # 确保slapd.d目录及其内容的所有权

# 启动服务前确保数据库目录已初始化
if [ ! -f "/var/lib/ldap/data.mdb" ]; then
    log "初始化MDB数据库结构 (slapadd)..."
    slapadd -F /etc/openldap/slapd.d -n 0 -l /etc/openldap/schema/core.ldif # 确保core schema被加载到cn=config
    slapadd -F /etc/openldap/slapd.d -n 1 -l /dev/null # 初始化主数据库
    # 数据目录和DB_CONFIG应该已经准备好，权限也已设置
    # slapadd -F /etc/openldap/slapd.d -n 1 -l /dev/null || error "数据库初始化失败 (slapadd)" # 旧命令
    chown -R ldap:ldap /var/lib/ldap/* # 确保slapadd创建的文件权限正确
fi

# 修改服务启动后的验证逻辑
log "启动 LDAP 服务 (systemctl restart slapd)..."
if ! systemctl restart slapd; then
    journalctl -u slapd -n 50 --no-pager
    error "启动 LDAP 服务失败，请检查上述日志"
fi

# 等待服务完全启动
log "等待服务启动 (5秒)..."
sleep 5

# 验证服务是否正在运行
if ! ps aux | grep slapd | grep -v grep > /dev/null; then
    log "LDAP服务启动失败，正在检查详细日志..."
    if [ -f /var/log/messages ]; then
        tail -n 50 /var/log/messages
    elif [ -f /var/log/syslog ]; then
        tail -n 50 /var/log/syslog
    fi
    journalctl -u slapd -n 50 --no-pager # 查看systemd日志
    error "LDAP服务启动失败，请检查上述日志信息"
fi
log "LDAP 服务已成功启动。"

# 创建SSL配置LDIF
cat > "$SSL_LDIF" << EOF
dn: cn=config
changetype: modify
add: olcTLSCipherSuite
olcTLSCipherSuite: NORMAL
-
add: olcTLSCACertificatePath
olcTLSCACertificatePath: $SSL_CERT_DIR
-
add: olcTLSCertificateFile
olcTLSCertificateFile: $SSL_CERT_FILE
-
add: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: $SSL_KEY_FILE
EOF

chmod 600 "$SSL_LDIF"

# 导入SSL配置
log "导入SSL配置到cn=config..."
log "$SSL_LDIF"

# 创建基础配置文件: olcRootPW
log "获取当前MDB数据库DN..."
# MDB数据库通常是 olcDatabase={1}mdb,cn=config 或 olcDatabase={2}mdb,cn=config
# slapcat -n0 可能会列出多个database, 我们需要mdb的那个
CURRENT_MDB_DN=$(ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(olcDatabase=*mdb)" dn -LLL | grep '^dn:' | awk '{print $2}' | head -n 1)

if [ -z "$CURRENT_MDB_DN" ]; then
    # 尝试从slapd.d目录结构猜测
    if [ -d /etc/openldap/slapd.d/cn=config/olcDatabase={1}mdb ]; then
        CURRENT_MDB_DN="olcDatabase={1}mdb,cn=config"
    elif [ -d /etc/openldap/slapd.d/cn=config/olcDatabase={2}mdb ]; then
        CURRENT_MDB_DN="olcDatabase={2}mdb,cn=config"
    else
        error "无法自动获取MDB数据库DN。请检查slapd服务是否正确运行并已生成slapd.d配置。"
    fi
    log "尝试使用猜测的MDB DN: $CURRENT_MDB_DN"
fi
log "MDB数据库DN为: $CURRENT_MDB_DN"


cat > "$CHROOTPW_LDIF" << EOF
dn: $CURRENT_MDB_DN
changetype: modify
replace: olcRootPW
olcRootPW: $HASHED_PW
EOF
chmod 600 "$CHROOTPW_LDIF" # 修正权限

# 导入基础配置 (olcRootPW)
log "导入基础配置 (olcRootPW)..."
log "$CHROOTPW_LDIF"
ldapmodify -Y EXTERNAL -H ldapi:/// -f "$CHROOTPW_LDIF" -Q || error "导入基础配置 (olcRootPW) 失败"

# 导入基本 Schema (这些通常由slaptest -u从slapd.conf的include指令处理并转换为cn=config下的olcSchemaConfig条目)
# 如果slaptest -u正常工作，这些ldapadd可能不需要，或者会导致重复条目错误。
# 现代OpenLDAP倾向于通过cn=config动态加载schema，而不是直接ldapadd .ldif文件到cn=schema,cn=config
# log "导入基本 Schema (如果需要)..."
# ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif || log "导入 cosine.ldif schema 可能已存在或失败"
# ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif || log "导入 nis.ldif schema 可能已存在或失败"
# ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif || log "导入 inetorgperson.ldif schema 可能已存在或失败"

# 创建数据库配置: olcSuffix, olcRootDN, olcAccess for monitor and mdb
# 注意：olcRootDN 和 olcSuffix 应该已经被 slaptest -u 从 slapd.conf 设置到 $CURRENT_MDB_DN
# olcAccess 规则也应该被转换。这里我们主要是确保 monitor 的 olcAccess。
cat > "$DB_LDIF" << EOF
dn: olcDatabase={0}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage by dn.base="cn=admin,$LDAP_SUFFIX" manage by * read

dn: olcDatabase={0}config,cn=config
changetype: add
objectClass: olcDatabaseConfig
olcDatabase: {0}config
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage by * none

dn: $CURRENT_MDB_DN
changetype: modify
replace: olcSuffix
olcSuffix: $LDAP_SUFFIX

dn: $CURRENT_MDB_DN
changetype: modify
replace: olcRootDN
olcRootDN: cn=admin,$LDAP_SUFFIX

dn: $CURRENT_MDB_DN
changetype: modify
add: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by dn="cn=admin,$LDAP_SUFFIX" write by anonymous auth by self write by * read
-
add: olcAccess
olcAccess: {1}to dn.base="" by * read
-
add: olcAccess
olcAccess: {2}to * by dn="cn=admin,$LDAP_SUFFIX" write by * read
EOF
chmod 600 "$DB_LDIF"

# 导入数据库配置
log "导入/更新数据库配置 (olcSuffix, olcRootDN, olcAccess)..."
log "$DB_LDIF"
ldapmodify -Y EXTERNAL -H ldapi:/// -f "$DB_LDIF" || error "导入数据库配置失败"
ldapmodify -Y EXTERNAL -H ldapi:/// -f "$SSL_LDIF" || error "导入SSL配置失败"

# 创建基本组织结构
cat > "$BASE_LDIF" << EOF
dn: $LDAP_SUFFIX
objectClass: top
objectClass: domain
objectClass: organization
dc: $(echo $LDAP_DOMAIN | cut -d. -f1)
o: $LDAP_ORGANIZATION

dn: cn=admin,$LDAP_SUFFIX
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: admin
description: LDAP Administrator

dn: ou=People,$LDAP_SUFFIX
objectClass: top
objectClass: organizationalUnit
ou: People

dn: ou=Group,$LDAP_SUFFIX
objectClass: top
objectClass: organizationalUnit
ou: Group
EOF
chmod 600 "$BASE_LDIF"

# 导入基本组织结构
log "导入基本组织结构..."
ldapadd -x -D "cn=admin,$LDAP_SUFFIX" -w "$LDAP_ROOTPW" -H ldapi:/// -f "$BASE_LDIF" || error "导入基本组织结构失败"

# 验证安装
log "验证 LDAP 安装..."
# 检查端口
if ! netstat -tuln | grep -q ":${LDAP_PORT}"; then
    error "LDAP 端口 ${LDAP_PORT} 未监听"
fi
log "端口 ${LDAP_PORT} 正在监听。"

if ! netstat -tuln | grep -q ":${LDAPS_PORT}"; then
    error "LDAPS 端口 ${LDAPS_PORT} 未监听"
fi
log "端口 ${LDAPS_PORT} 正在监听。"

# 检查服务状态
if ! ps aux | grep slapd | grep -v grep > /dev/null; then
    error "LDAP 服务未运行"
fi
log "LDAP 服务正在运行。"

# 验证基本查询
log "尝试基本 LDAP 查询 (ldap://)..."
if ! ldapsearch -x -b "$LDAP_SUFFIX" -H "ldap://${LDAP_HOST}" '(objectClass=*)' &>/dev/null; then
    error "LDAP 查询测试失败 (ldap://)"
fi
log "LDAP 基本查询成功 (ldap://)。"

log "尝试基本 LDAPS 查询 (ldaps://)..."
# 对于自签名证书，客户端可能需要 -ZZ (StartTLS) 或指定CA，或者忽略证书检查 (不推荐生产环境)
# 为了简单测试，我们先尝试直接连接，如果失败，提示用户可能需要配置客户端信任
if ! ldapsearch -x -b "$LDAP_SUFFIX" -H "ldaps://${LDAP_HOST}" '(objectClass=*)' -LLL -o ldap_opt_x_tls_require_cert=never &>/dev/null; then
    log "LDAPS 查询测试失败 (ldaps://)。可能需要客户端配置以信任自签名证书，或使用 -o ldap_opt_x_tls_require_cert=never 进行测试。"
    # error "LDAPS 查询测试失败" # 暂时不因为这个报错退出
else
    log "LDAPS 基本查询成功 (ldaps://)。"
fi

log "尝试 Monitor 后端查询 (ldaps://)..."
if ! ldapsearch -x -b "cn=Monitor" -H "ldaps://${LDAP_HOST}" '(objectClass=*)' -LLL -o ldap_opt_x_tls_require_cert=never &>/dev/null; then
     log "Monitor 后端查询测试失败 (ldaps://)。"
else
    log "Monitor 后端查询成功 (ldaps://)。"
fi


# 配置环境变量
log "配置环境变量 (/etc/profile.d/ldap.sh)..."
cat > /etc/profile.d/ldap.sh << EOF
export LDAPHOST=$LDAP_HOST
export LDAPPORT=$LDAP_PORT
export LDAPS_PORT=$LDAPS_PORT
export LDAPBASE="$LDAP_SUFFIX"
EOF
source /etc/profile.d/ldap.sh
log "环境变量已配置。请运行 'source /etc/profile.d/ldap.sh' 或重新登录以使环境变量在当前会话生效。"

# 输出使用信息
cat << EOF

${GREEN}LDAP 安装完成！${NC}

基本信息：
- LDAP URL: ldap://${LDAP_HOST}:${LDAP_PORT}
- LDAPS URL: ldaps://${LDAP_HOST}:${LDAPS_PORT}
- Base DN: $LDAP_SUFFIX
- 管理员 DN: cn=admin,$LDAP_SUFFIX
- 管理员密码: $LDAP_ROOTPW (请妥善保管)
- SSL 证书: ${SSL_CERT_FILE}
- SSL 私钥: ${SSL_KEY_FILE}

常用命令：
1. 搜索用户 (LDAP):
   ldapsearch -x -H ldap://${LDAP_HOST} -b "ou=People,$LDAP_SUFFIX" '(objectClass=person)'
2. 搜索用户 (LDAPS, 可能需要客户端信任证书或使用 -o ldap_opt_x_tls_require_cert=never):
   ldapsearch -x -H ldaps://${LDAP_HOST} -b "ou=People,$LDAP_SUFFIX" '(objectClass=person)' -o ldap_opt_x_tls_require_cert=never

3. 添加用户 (示例 user.ldif):
   cat > user.ldif << EOL
   dn: uid=testuser,ou=People,$LDAP_SUFFIX
   objectClass: top
   objectClass: person
   objectClass: organizationalPerson
   objectClass: inetOrgPerson
   uid: testuser
   cn: Test User
   sn: User
   givenName: Test
   mail: testuser@$LDAP_DOMAIN
   userPassword: {SSHA}$(slappasswd -s 'newpassword' | cut -c 7-)
   EOL
   ldapadd -x -D "cn=admin,$LDAP_SUFFIX" -w "$LDAP_ROOTPW" -H ldap://${LDAP_HOST} -f user.ldif

4. 查看 Monitor 信息 (LDAPS):
   ldapsearch -x -H ldaps://${LDAP_HOST} -b "cn=Monitor" '(objectClass=*)' -o ldap_opt_x_tls_require_cert=never


请妥善保管管理员密码！
要使环境变量立即生效，请运行: source /etc/profile.d/ldap.sh

EOF

log "安装脚本执行完毕！"