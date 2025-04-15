#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 日志文件
LOG_FILE="/var/log/yum_config_$(date +%Y%m%d_%H%M%S).log"

# 输出函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a ${LOG_FILE}
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a ${LOG_FILE}
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a ${LOG_FILE}
}

# 环境检查
check_environment() {
    print_message "开始环境检查..."
    
    # 检查系统版本
    if ! grep -qs "CentOS Linux release 7" /etc/redhat-release; then
        print_error "此脚本仅支持 CentOS 7.x 系统"
        exit 1
    fi
    
    # 检查网络连接
    if ! ping -c 1 mirrors.aliyun.com &> /dev/null; then
        print_error "无法访问阿里云镜像站，请检查网络连接"
        exit 1
    fi
    
    # 检查必要工具
    for tool in curl sed; do
        if ! command -v ${tool} &> /dev/null; then
            print_warning "未找到 ${tool}，正在安装..."
            yum install -y ${tool}
        fi
    done
}

# YUM 配置优化
optimize_yum() {
    print_message "优化 YUM 配置..."
    
    # 配置 YUM 参数
    cat > /etc/yum.conf.new << EOF
[main]
cachedir=/var/cache/yum/\$basearch/\$releasever
keepcache=1
debuglevel=2
logfile=/var/log/yum.log
exactarch=1
obsoletes=1
gpgcheck=1
plugins=1
installonly_limit=5
bugtracker_url=http://bugs.centos.org/set_project.php?project_id=23&ref=http://bugs.centos.org/bug_report_page.php?category=yum
distroverpkg=centos-release
timeout=120
retries=10
http_caching=packages
multilib_policy=best
max_parallel_downloads=10
EOF

    mv /etc/yum.conf /etc/yum.conf.backup
    mv /etc/yum.conf.new /etc/yum.conf
}

# 备份配置
backup_config() {
    print_message "备份现有配置..."
    BACKUP_DIR="/etc/yum.repos.d/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p ${BACKUP_DIR}
    cp -f /etc/yum.repos.d/*.repo ${BACKUP_DIR}/ 2>/dev/null || true
    cp -f /etc/yum.conf ${BACKUP_DIR}/ 2>/dev/null || true
}

# 配置源
configure_repos() {
    print_message "配置软件源..."
    
    # 清理现有源
    rm -f /etc/yum.repos.d/*.repo
    
    # 下载阿里云源
    curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
    
    # 卸载并重新安装 EPEL
    print_message "重新配置 EPEL..."
    if rpm -q epel-release &>/dev/null; then
        print_message "卸载已有 EPEL..."
        yum remove -y epel-release
    fi
    
    print_message "安装 EPEL..."
    yum install -y epel-release
    
    # 配置 EPEL 镜像
    if [ -f /etc/yum.repos.d/epel.repo ]; then
        print_message "配置 EPEL 镜像源..."
        # 修正 EPEL 镜像地址
        sed -i 's|^#baseurl=http://download.fedoraproject.org/pub/epel|baseurl=https://mirrors.aliyun.com/epel|' /etc/yum.repos.d/epel.repo
        sed -i 's|^metalink|#metalink|' /etc/yum.repos.d/epel.repo
        
        # 验证 EPEL 配置
        yum clean all --enablerepo=epel
        yum makecache --enablerepo=epel
    else
        print_error "EPEL 配置文件不存在"
        exit 1
    fi
}

# 安装基础软件包
install_packages() {
    print_message "安装基础软件包..."    
    
    # 基础工具包列表
    BASIC_PACKAGES="vim wget curl net-tools lsof telnet tcpdump"
    
    yum install -y ${BASIC_PACKAGES}
}

# 验证配置
verify_config() {
    print_message "验证配置..."
    
    # 检查源可用性
    yum repolist > ${LOG_FILE}.repolist
    
    # 测试软件安装
    if ! yum install -y vim; then
        print_error "软件安装测试失败"
        return 1
    fi
    
    # 检查下载速度
    print_message "测试下载速度..."
    time yum makecache
}

# 主函数
main() {
    print_message "开始配置 YUM..."

    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 用户执行此脚本"
        exit 1
    fi
    
    # 执行配置步骤
    check_environment
    backup_config
    optimize_yum
    configure_repos
    
    # 清理缓存
    print_message "清理并重建缓存..."
    yum clean all
    yum makecache
    
    install_packages
    verify_config
    
    print_message "YUM 配置完成！"
    print_message "配置日志：${LOG_FILE}"
    print_message "配置备份：${BACKUP_DIR}"
}

# 执行主函数
main

# 业已核验之次数： 
# - ⭐️ 172.16.48.171 时间：2025-04-11 16:21:50