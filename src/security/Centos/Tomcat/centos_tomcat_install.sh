#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 输出函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    print_error "请使用root用户执行此脚本"
fi

# 设置变量
TOMCAT_VERSION="8.5.31"
TOMCAT_HOME="/data/tomcat"
TOMCAT_USER="tomcat"
TOMCAT_GROUP="tomcat"
JAVA_HOME="/data/java/jdk1.8.0_251"
HTTP_PORT="8822"

# 添加镜像地址
APACHE_MIRROR="https://archive.apache.org/dist/tomcat/tomcat-8/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"
ALIYUN_MIRROR="https://mirrors.aliyun.com/apache/tomcat/tomcat-8/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"
TSINGHUA_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/apache/tomcat/tomcat-8/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"

# 创建用户和组
print_message "创建tomcat用户和组..."
groupadd ${TOMCAT_GROUP} 2>/dev/null || true
useradd -r -m -s /bin/bash -g ${TOMCAT_GROUP} ${TOMCAT_USER} 2>/dev/null || true

# 创建目录
print_message "创建目录结构..."
mkdir -p ${TOMCAT_HOME}/{bin,base,logs,temp,webapps,work}

# 在脚本开头添加
# 检查Java环境
if [ ! -d "${JAVA_HOME}" ]; then
    print_error "Java环境未安装或路径不正确: ${JAVA_HOME}"
fi

# 检查端口占用
if netstat -tuln | grep ":${HTTP_PORT}" >/dev/null; then
    print_error "端口 ${HTTP_PORT} 已被占用"
fi

# 检查磁盘空间
REQUIRED_SPACE=500 # MB
AVAILABLE_SPACE=$(df -m ${TOMCAT_HOME%/*} | awk 'NR==2 {print $4}')
if [ ${AVAILABLE_SPACE} -lt ${REQUIRED_SPACE} ]; then
    print_error "磁盘空间不足，需要至少 ${REQUIRED_SPACE}MB"
fi

# 在安装前添加备份功能
if [ -d "${TOMCAT_HOME}" ]; then
    BACKUP_TIME=$(date +%Y%m%d_%H%M%S)
    print_message "备份已存在的Tomcat目录..."
    tar czf ${TOMCAT_HOME}_backup_${BACKUP_TIME}.tar.gz ${TOMCAT_HOME} || print_error "备份失败"
fi

# 修改下载逻辑
print_message "下载Tomcat..."
cd /tmp
if [ ! -f "apache-tomcat-${TOMCAT_VERSION}.tar.gz" ]; then
    print_message "尝试从阿里云镜像下载..."
    wget ${ALIYUN_MIRROR} || {
        print_message "尝试从清华镜像下载..."
        wget ${TSINGHUA_MIRROR} || {
            print_message "尝试从Apache官方下载..."
            wget ${APACHE_MIRROR} || {
                print_error "所有下载源均失败"
            }
        }
    }
fi

print_message "解压Tomcat..."
tar xf apache-tomcat-${TOMCAT_VERSION}.tar.gz
cp -r apache-tomcat-${TOMCAT_VERSION}/* ${TOMCAT_HOME}/base/

# 配置server.xml
print_message "配置server.xml..."
cat > ${TOMCAT_HOME}/base/conf/server.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<Server port="8005" shutdown="SHUTDOWN">
  <Listener className="org.apache.catalina.startup.VersionLoggerListener" />
  <Listener className="org.apache.catalina.core.AprLifecycleListener" SSLEngine="on" />
  <Listener className="org.apache.catalina.core.JreMemoryLeakPreventionListener" />
  <Listener className="org.apache.catalina.mbeans.GlobalResourcesLifecycleListener" />
  <Listener className="org.apache.catalina.core.ThreadLocalLeakPreventionListener" />

  <GlobalNamingResources>
    <Resource name="UserDatabase" auth="Container"
              type="org.apache.catalina.UserDatabase"
              description="User database that can be updated and saved"
              factory="org.apache.catalina.users.MemoryUserDatabaseFactory"
              pathname="conf/tomcat-users.xml" />
  </GlobalNamingResources>

  <Service name="Catalina">
    <Connector port="${HTTP_PORT}" protocol="HTTP/1.1"
               connectionTimeout="20000"
               redirectPort="8443"
               maxThreads="1000"
               minSpareThreads="100"
               acceptCount="800"
               enableLookups="false"
               compression="on"
               compressionMinSize="2048"
               compressableMimeType="text/html,text/xml,text/plain,text/css,text/javascript,application/javascript"
               URIEncoding="UTF-8" />

    <Engine name="Catalina" defaultHost="localhost">
      <Realm className="org.apache.catalina.realm.LockOutRealm">
        <Realm className="org.apache.catalina.realm.UserDatabaseRealm"
               resourceName="UserDatabase"/>
      </Realm>

      <Host name="localhost"  appBase="webapps"
            unpackWARs="true" autoDeploy="true">
        <Valve className="org.apache.catalina.valves.AccessLogValve" directory="logs"
               prefix="localhost_access_log" suffix=".txt"
               pattern="%h %l %u %t &quot;%r&quot; %s %b" />
      </Host>
    </Engine>
  </Service>
</Server>
EOF

# 添加日志轮转配置
mkdir ${TOMCAT_HOME}/base/conf/logrotate.d/
cat > ${TOMCAT_HOME}/base/conf/logrotate.d/tomcat << EOF
${TOMCAT_HOME}/logs/*.log {
    daily
    rotate 30
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
EOF

# 添加环境变量配置
cat > /etc/profile.d/tomcat.sh << EOF
export TOMCAT_HOME=${TOMCAT_HOME}
export CATALINA_HOME=${TOMCAT_HOME}/base
export CATALINA_BASE=${TOMCAT_HOME}/base
EOF

# 创建启动脚本
print_message "创建启动脚本..."
cat > ${TOMCAT_HOME}/bin/startup.sh << EOF
#!/bin/bash
export JAVA_HOME=${JAVA_HOME}
export PATH=\$JAVA_HOME/bin:\$PATH
export CATALINA_HOME=${TOMCAT_HOME}/base
export CATALINA_BASE=${TOMCAT_HOME}/base
export CATALINA_TMPDIR=${TOMCAT_HOME}/temp
export CATALINA_OUT=${TOMCAT_HOME}/logs/catalina.out

cd \$CATALINA_HOME
./bin/catalina.sh start
EOF

# 创建停止脚本
print_message "创建停止脚本..."
cat > ${TOMCAT_HOME}/bin/shutdown.sh << EOF
#!/bin/bash
export JAVA_HOME=${JAVA_HOME}
export PATH=\$JAVA_HOME/bin:\$PATH
export CATALINA_HOME=${TOMCAT_HOME}/base
export CATALINA_BASE=${TOMCAT_HOME}/base
export CATALINA_TMPDIR=${TOMCAT_HOME}/temp

cd \$CATALINA_HOME
./bin/catalina.sh stop
EOF

# 设置权限
print_message "设置权限..."
chmod +x ${TOMCAT_HOME}/bin/*.sh
chown -R ${TOMCAT_USER}:${TOMCAT_GROUP} ${TOMCAT_HOME}

# 创建服务文件
print_message "创建系统服务..."
cat > /usr/lib/systemd/system/tomcat.service << EOF
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
Environment=JAVA_HOME=${JAVA_HOME}
Environment=CATALINA_HOME=${TOMCAT_HOME}/base
Environment=CATALINA_BASE=${TOMCAT_HOME}/base
Environment=CATALINA_TMPDIR=${TOMCAT_HOME}/temp
Environment=CATALINA_OUT=${TOMCAT_HOME}/logs/catalina.out

User=${TOMCAT_USER}
Group=${TOMCAT_GROUP}

ExecStart=${TOMCAT_HOME}/bin/startup.sh
ExecStop=${TOMCAT_HOME}/bin/shutdown.sh

[Install]
WantedBy=multi-user.target
EOF

# 重载系统服务
systemctl daemon-reload

# 启动Tomcat
print_message "启动Tomcat服务..."
systemctl start tomcat
systemctl enable tomcat

# 检查服务状态
print_message "检查服务状态..."
if systemctl is-active tomcat >/dev/null 2>&1; then
    print_message "Tomcat服务已成功启动"
    print_message "访问地址: http://localhost:${HTTP_PORT}"
else
    print_error "Tomcat服务启动失败，请检查日志"
fi

print_message "安装完成！"
print_message "启动命令: systemctl start tomcat"
print_message "停止命令: systemctl stop tomcat"
print_message "重启命令: systemctl restart tomcat"
print_message "状态查看: systemctl status tomcat"