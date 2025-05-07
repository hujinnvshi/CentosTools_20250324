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

log "LDAP 服务器 IP 将使用: $LDAP_HOST"

# 创建临时目录
TEMP_DIR=$(mktemp -d)
CHROOTPW_LDIF="${TEMP_DIR}/chrootpw.ldif"
DB_LDIF="${TEMP_DIR}/db.ldif"
BASE_LDIF="${TEMP_DIR}/base.ldif"
trap 'rm -rf "${TEMP_DIR}"' EXIT

# 清理现有配置
log "清理现有配置..."
rm -rf /etc/openldap/slapd.d/*
rm -rf /var/lib/ldap/*

# 安装必要的软件包
log "安装 OpenLDAP 及相关工具..."
yum -y install openldap openldap-servers openldap-clients || error "安装 OpenLDAP 失败"

# 生成管理员密码
log "配置管理员密码..."
HASHED_PW=$(slappasswd -s "$LDAP_ROOTPW")
if [ $? -ne 0 ]; then
    error "生成密码哈希失败"
fi

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
chmod 700 /var/run/openldap # 更改为700，更安全

# 创建slapd配置文件
log "创建slapd配置文件 (/etc/openldap/slapd.conf)..."
cat > /etc/openldap/slapd.conf << EOF
include         /etc/openldap/schema/core.schema
include         /etc/openldap/schema/cosine.schema
include         /etc/openldap/schema/nis.schema
include         /etc/openldap/schema/inetorgperson.schema

pidfile         /var/run/openldap/slapd.pid
argsfile        /var/run/openldap/slapd.args

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

access to attrs=userPassword,shadowLastChange
        by self write
        by anonymous auth
        by dn="cn=admin,$LDAP_SUFFIX" write
        by * none

access to *
        by self write
        by dn="cn=admin,$LDAP_SUFFIX" write
        by * read
EOF

chown ldap:ldap /etc/openldap/slapd.conf
chmod 700 /etc/openldap/slapd.conf # 更改为700，更安全

# 检查配置文件 (slaptest -u, 检查slapd.conf并尝试生成slapd.d的初始结构)
log "检查配置文件 (slaptest -u)..."
# 先确保slapd.d目录存在且权限正确，以供slaptest -u写入
rm -rf /etc/openldap/slapd.d/* # 清理旧的slapd.d内容
mkdir -p /etc/openldap/slapd.d
chown -R ldap:ldap /etc/openldap/slapd.d
chmod 700 /etc/openldap/slapd.d
slaptest -u -f /etc/openldap/slapd.conf -F /etc/openldap/slapd.d || error "配置文件检查失败 (slaptest -u)"

# 确保slapd.d目录权限在slaptest -u后依然正确
chown -R ldap:ldap /etc/openldap/slapd.d
chmod 700 /etc/openldap/slapd.d

# 尝试停止任何可能正在运行的旧slapd进程
log "尝试停止任何旧的 LDAP 服务..."
kill $(ps aux | grep slapd | grep -v grep | awk '{print $2}') 2>/dev/null || true
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
slaptest -f /etc/openldap/slapd.conf -F /etc/openldap/slapd.d || error "配置转换失败 (slaptest -f)"
chown -R ldap:ldap /etc/openldap/slapd.d # 确保slapd.d目录及其内容的所有权

# 启动服务前确保数据库目录已初始化
if [ ! -f "/var/lib/ldap/data.mdb" ]; then
    log "初始化MDB数据库结构 (slapadd)..."
    # 数据目录和DB_CONFIG应该已经准备好，权限也已设置
    slapadd -F /etc/openldap/slapd.d -n 1 -l /dev/null || error "数据库初始化失败 (slapadd)"
    chown -R ldap:ldap /var/lib/ldap/* # 确保slapadd创建的文件权限正确
fi

# 启动服务
log "启动 LDAP 服务..."
slapd -h "ldap:/// ldapi:///" -u ldap -g ldap -F /etc/openldap/slapd.d || error "启动 LDAP 服务失败"

# 等待服务完全启动
log "等待服务启动 (5秒)..."
sleep 5

# 验证服务是否正在运行
if ! ps aux | grep slapd | grep -v grep > /dev/null; then
    log "LDAP服务启动失败，正在检查详细日志..."
    # CentOS 7 通常日志在 /var/log/messages
    if [ -f /var/log/messages ]; then
        tail -n 50 /var/log/messages
    elif [ -f /var/log/syslog ]; then # 某些系统可能是syslog
        tail -n 50 /var/log/syslog
    fi
    error "LDAP服务启动失败，请检查上述日志信息"
fi
log "LDAP 服务已成功启动。"

# 创建基础配置文件: olcRootPW
cat > "$CHROOTPW_LDIF" << EOF
dn: olcDatabase={2}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $HASHED_PW
EOF

# 导入基础配置 (olcRootPW)
log "导入基础配置 (olcRootPW)..."
ldapmodify -Y EXTERNAL -H ldapi:/// -f "$CHROOTPW_LDIF" || error "导入基础配置 (olcRootPW) 失败"

# 导入基本 Schema
log "导入基本 Schema..."
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif || error "导入 cosine.ldif schema 失败"
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif || error "导入 nis.ldif schema 失败"
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif || error "导入 inetorgperson.ldif schema 失败"

# 创建数据库配置: olcSuffix, olcRootDN, olcAccess for monitor and mdb
cat > "$DB_LDIF" << EOF
dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read by dn.base="cn=admin,$LDAP_SUFFIX" read by * none

dn: olcDatabase={2}mdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: $LDAP_SUFFIX

dn: olcDatabase={2}mdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=admin,$LDAP_SUFFIX

dn: olcDatabase={2}mdb,cn=config
changetype: modify
add: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by dn="cn=admin,$LDAP_SUFFIX" write by anonymous auth by self write by * none
olcAccess: {1}to dn.base="" by * read
olcAccess: {2}to * by dn="cn=admin,$LDAP_SUFFIX" write by * read
EOF

# 导入数据库配置
log "导入数据库配置 (olcSuffix, olcRootDN, olcAccess)..."
ldapmodify -Y EXTERNAL -H ldapi:/// -f "$DB_LDIF" || error "导入数据库配置失败"

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

# 检查服务状态
if ! ps aux | grep slapd | grep -v grep > /dev/null; then
    error "LDAP 服务未运行"
fi
log "LDAP 服务正在运行。"

# 验证基本查询
log "尝试基本 LDAP 查询..."
if ! ldapsearch -x -b "$LDAP_SUFFIX" -H ldap:/// '(objectClass=*)' &>/dev/null; then
    error "LDAP 查询测试失败"
fi
log "LDAP 基本查询成功。"

# 配置环境变量
log "配置环境变量 (/etc/profile.d/ldap.sh)..."
cat > /etc/profile.d/ldap.sh << EOF
export LDAPHOST=$LDAP_HOST
export LDAPPORT=$LDAP_PORT
export LDAPBASE="$LDAP_SUFFIX"
EOF
source /etc/profile.d/ldap.sh
log "环境变量已配置。请运行 'source /etc/profile.d/ldap.sh' 或重新登录以使环境变量在当前会话生效。"

# 输出使用信息
cat << EOF

${GREEN}LDAP 安装完成！${NC}

基本信息：
- LDAP URL: ldap://${LDAP_HOST}:${LDAP_PORT}
- Base DN: $LDAP_SUFFIX
- 管理员 DN: cn=admin,$LDAP_SUFFIX
- 管理员密码: $LDAP_ROOTPW (请妥善保管)

常用命令：
1. 搜索用户：
   ldapsearch -x -H ldap://${LDAP_HOST} -b "ou=People,$LDAP_SUFFIX" '(objectClass=person)'

2. 添加用户 (示例 user.ldif):
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
   userPassword: {SSHA}$(slappasswd -s 'newpassword' | कट -c 7-)
   EOL
   ldapadd -x -D "cn=admin,$LDAP_SUFFIX" -w "$LDAP_ROOTPW" -f user.ldif

3. 修改用户：
   ldapmodify -x -D "cn=admin,$LDAP_SUFFIX" -w "$LDAP_ROOTPW" -f modify.ldif

4. 删除用户：
   ldapdelete -x -D "cn=admin,$LDAP_SUFFIX" -w "$LDAP_ROOTPW" "uid=testuser,ou=People,$LDAP_SUFFIX"

5. 验证服务状态：
   ps aux | grep slapd | grep -v grep

请妥善保管管理员密码！
要使环境变量立即生效，请运行: source /etc/profile.d/ldap.sh

EOF

log "安装脚本执行完毕！"