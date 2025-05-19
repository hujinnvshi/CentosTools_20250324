#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 输出带颜色的信息函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    print_error "请使用 root 用户执行此脚本"
    exit 1
fi

# 设置变量
LDAP_DOMAIN="node3.com"
LDAP_ORGANIZATION="node3 Inc"
LDAP_ADMIN_PASSWORD="123456"
LDAP_BASE_DN="dc=node3,dc=com"
LDAP_ADMIN_DN="cn=admin,${LDAP_BASE_DN}"
PHPLDAPADMIN_VERSION="1.2.6.3"
PHPLDAPADMIN_DIR="/var/www/html/phpldapadmin"
SERVER_IP=$(ip addr show | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n 1)

# 询问用户是否要自定义配置
read -p "是否要自定义LDAP配置? (y/n, 默认: n): " customize_config
if [[ "$customize_config" =~ ^[Yy]$ ]]; then
    read -p "请输入LDAP域名 (默认: ${LDAP_DOMAIN}): " input_domain
    LDAP_DOMAIN=${input_domain:-$LDAP_DOMAIN}
    
    read -p "请输入组织名称 (默认: ${LDAP_ORGANIZATION}): " input_org
    LDAP_ORGANIZATION=${input_org:-$LDAP_ORGANIZATION}
    
    read -p "请输入管理员密码 (默认: ${LDAP_ADMIN_PASSWORD}): " input_password
    LDAP_ADMIN_PASSWORD=${input_password:-$LDAP_ADMIN_PASSWORD}
    
    # 根据域名自动生成Base DN
    IFS='.' read -ra DOMAIN_PARTS <<< "$LDAP_DOMAIN"
    LDAP_BASE_DN=""
    for part in "${DOMAIN_PARTS[@]}"; do
        if [ -z "$LDAP_BASE_DN" ]; then
            LDAP_BASE_DN="dc=$part"
        else
            LDAP_BASE_DN="${LDAP_BASE_DN},dc=$part"
        fi
    done
    LDAP_ADMIN_DN="cn=admin,${LDAP_BASE_DN}"
fi

print_message "将使用以下配置:"
echo "域名: ${LDAP_DOMAIN}"
echo "组织: ${LDAP_ORGANIZATION}"
echo "Base DN: ${LDAP_BASE_DN}"
echo "管理员DN: ${LDAP_ADMIN_DN}"
echo "服务器IP: ${SERVER_IP}"

# 确认继续
read -p "是否继续安装? (y/n, 默认: y): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]] && [[ ! -z "$confirm" ]]; then
    print_message "安装已取消"
    exit 0
fi

# 安装必要的软件包
print_message "安装必要的软件包..."
yum install -y epel-release
yum install -y httpd php php-ldap php-xml php-mbstring php-gd wget unzip firewalld

# 验证OpenLDAP是否已安装并运行
print_message "验证OpenLDAP服务状态..."
if ! ldapsearch -x -H ldap://localhost -b "" -s base "+" > /dev/null 2>&1; then
    print_error "OpenLDAP服务未运行或无法连接，请确保OpenLDAP已正确安装并运行"
    exit 1
fi

# 安装phpLDAPadmin
print_message "安装phpLDAPadmin..."
mkdir -p ${PHPLDAPADMIN_DIR}
cd /tmp

# 检查是否已下载
if [ -f "${PHPLDAPADMIN_VERSION}.zip" ]; then
    print_message "phpLDAPadmin安装包已存在，跳过下载"
else
    print_message "下载phpLDAPadmin..."
    if ! wget https://github.com/leenooks/phpLDAPadmin/archive/refs/tags/${PHPLDAPADMIN_VERSION}.zip; then
        print_error "下载phpLDAPadmin失败"
        exit 1
    fi
fi

if ! unzip -q ${PHPLDAPADMIN_VERSION}.zip; then
    print_error "解压phpLDAPadmin失败"
    exit 1
fi

cp -r phpLDAPadmin-${PHPLDAPADMIN_VERSION}/* ${PHPLDAPADMIN_DIR}/
cp ${PHPLDAPADMIN_DIR}/config/config.php.example ${PHPLDAPADMIN_DIR}/config/config.php

# 手动配置phpLDAPadmin


# 设置Apache配置
print_message "设置Apache配置..."
cat > /etc/httpd/conf.d/phpldapadmin.conf << EOF
Alias /phpldapadmin ${PHPLDAPADMIN_DIR}

<Directory ${PHPLDAPADMIN_DIR}>
  <IfModule mod_authz_core.c>
    # Apache 2.4
    Require all granted
  </IfModule>
  <IfModule !mod_authz_core.c>
    # Apache 2.2
    Order allow,deny
    Allow from all
  </IfModule>
</Directory>
EOF

# 设置权限
print_message "设置权限..."
chown -R apache:apache ${PHPLDAPADMIN_DIR}
chmod -R 755 ${PHPLDAPADMIN_DIR}

# 启动Apache服务
print_message "启动Apache服务..."
systemctl start httpd
systemctl enable httpd


# 清理临时文件
print_message "清理临时文件..."
rm -f /tmp/${PHPLDAPADMIN_VERSION}.zip
rm -rf /tmp/phpLDAPadmin-${PHPLDAPADMIN_VERSION}

# 验证安装
print_message "验证phpLDAPadmin安装..."
if curl -s http://localhost/phpldapadmin/ | grep -q "phpLDAPadmin"; then
    print_message "phpLDAPadmin安装成功"
else
    print_warning "无法验证phpLDAPadmin安装，请手动检查"
fi

print_message "安装完成！"
print_message "phpLDAPadmin 访问地址: http://${SERVER_IP}/phpldapadmin"
print_message "LDAP管理员DN: ${LDAP_ADMIN_DN}"
print_message "LDAP管理员密码: ${LDAP_ADMIN_PASSWORD}"

# 安全提示
print_warning "请注意：为了安全起见，请在生产环境中配置SSL/TLS"
print_warning "建议配置HTTPS以保护phpLDAPadmin的访问安全"

# 添加HTTPS配置建议
cat << EOF

=== HTTPS配置建议 ===
要配置HTTPS，请执行以下步骤：

1. 安装SSL模块：
   yum install -y mod_ssl openssl

2. 生成自签名证书：
   mkdir -p /etc/httpd/ssl
   openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/httpd/ssl/apache.key -out /etc/httpd/ssl/apache.crt

3. 配置SSL虚拟主机：
   编辑 /etc/httpd/conf.d/ssl.conf 文件，确保以下设置：
   
   <VirtualHost _default_:443>
     ServerName ${SERVER_IP}
     DocumentRoot "/var/www/html"
     SSLEngine on
     SSLCertificateFile /etc/httpd/ssl/apache.crt
     SSLCertificateKeyFile /etc/httpd/ssl/apache.key
   </VirtualHost>

4. 重启Apache：
   systemctl restart httpd
EOF