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

# 设置 LDAP 基本配置
LDAP_DOMAIN="example.com"
LDAP_SUFFIX="dc=example,dc=com"
LDAP_ROOTPW="admin123"  # 管理员密码
LDAP_ORGANIZATION="Example Inc"

# 安装必要的软件包
log "安装 OpenLDAP 及相关工具..."
yum -y install openldap openldap-servers openldap-clients || error "安装 OpenLDAP 失败"

# 启动 LDAP 服务
log "启动 LDAP 服务..."
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown ldap:ldap /var/lib/ldap/DB_CONFIG
systemctl start slapd
systemctl enable slapd

# 生成管理员密码
log "配置管理员密码..."
HASHED_PW=$(slappasswd -s "$LDAP_ROOTPW")
if [ $? -ne 0 ]; then
    error "生成密码哈希失败"
fi

# 创建基础配置文件
cat > /tmp/chrootpw.ldif << EOF
dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootPW
olcRootPW: $HASHED_PW
EOF

# 导入基础配置
log "导入基础配置..."
ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/chrootpw.ldif || error "导入基础配置失败"

# 导入基本 Schema
log "导入基本 Schema..."
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif || error "导入 cosine schema 失败"
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif || error "导入 nis schema 失败"
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif || error "导入 inetorgperson schema 失败"

# 创建数据库配置
cat > /tmp/db.ldif << EOF
dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read by dn.base="cn=admin,$LDAP_SUFFIX" read by * none

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: $LDAP_SUFFIX

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=admin,$LDAP_SUFFIX

dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcRootPW
olcRootPW: $HASHED_PW

dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by dn="cn=admin,$LDAP_SUFFIX" write by anonymous auth by self write by * none
olcAccess: {1}to dn.base="" by * read
olcAccess: {2}to * by dn="cn=admin,$LDAP_SUFFIX" write by * read
EOF

# 导入数据库配置
log "导入数据库配置..."
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/db.ldif || error "导入数据库配置失败"

# 创建基本组织结构
cat > /tmp/base.ldif << EOF
dn: $LDAP_SUFFIX
objectClass: dcObject
objectClass: organization
dc: example
o: $LDAP_ORGANIZATION

dn: cn=admin,$LDAP_SUFFIX
objectClass: organizationalRole
cn: admin
description: LDAP Administrator

dn: ou=People,$LDAP_SUFFIX
objectClass: organizationalUnit
ou: People

dn: ou=Group,$LDAP_SUFFIX
objectClass: organizationalUnit
ou: Group
EOF

# 导入基本组织结构
log "导入基本组织结构..."
ldapadd -x -D "cn=admin,$LDAP_SUFFIX" -w "$LDAP_ROOTPW" -f /tmp/base.ldif || error "导入基本组织结构失败"

# 清理临时文件
log "清理临时文件..."
rm -f /tmp/chrootpw.ldif /tmp/db.ldif /tmp/base.ldif

# 验证安装
log "验证 LDAP 安装..."
if ! ldapsearch -x -b "$LDAP_SUFFIX" -H ldap:/// &>/dev/null; then
    error "LDAP 验证失败"
fi

# 配置环境变量
log "配置环境变量..."
cat > /etc/profile.d/ldap.sh << EOF
export LDAPHOST=localhost
export LDAPPORT=389
export LDAPBASE="$LDAP_SUFFIX"
EOF

# 输出使用信息
cat << EOF

${GREEN}LDAP 安装完成！${NC}

基本信息：
- LDAP URL: ldap://localhost:389
- Base DN: $LDAP_SUFFIX
- 管理员 DN: cn=admin,$LDAP_SUFFIX
- 管理员密码: $LDAP_ROOTPW

常用命令：
1. 搜索用户：
   ldapsearch -x -H ldap://localhost -b "$LDAP_SUFFIX" '(objectClass=person)'

2. 添加用户：
   ldapadd -x -D "cn=admin,$LDAP_SUFFIX" -w "$LDAP_ROOTPW" -f user.ldif

3. 修改用户：
   ldapmodify -x -D "cn=admin,$LDAP_SUFFIX" -w "$LDAP_ROOTPW" -f modify.ldif

4. 删除用户：
   ldapdelete -x -D "cn=admin,$LDAP_SUFFIX" -w "$LDAP_ROOTPW" "uid=user1,$LDAP_SUFFIX"

5. 验证服务状态：
   systemctl status slapd

请妥善保管管理员密码！

EOF

log "安装完成！"