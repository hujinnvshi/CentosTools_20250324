#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 输出带颜色的信息函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    print_error "请使用 root 用户执行此脚本"
    exit 1
fi

# 备份原有的 repo 文件
print_message "备份原有的 repo 文件..."
mkdir -p /etc/yum.repos.d/backup
mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/backup/

# 下载阿里云 repo 文件
print_message "下载阿里云 repo 文件..."
curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
if [ $? -ne 0 ]; then
    print_error "下载阿里云 repo 文件失败"
    exit 1
fi

# 清理并重建 yum 缓存
print_message "清理并重建 yum 缓存..."
yum clean all
yum makecache

# 安装 epel-release
print_message "安装 epel-release..."
yum install -y epel-release

# 配置 EPEL 源为阿里云镜像
print_message "配置 EPEL 源为阿里云镜像..."
sed -i 's|^#baseurl=http://download.fedoraproject.org/pub|baseurl=https://mirrors.aliyun.com|' /etc/yum.repos.d/epel.repo
sed -i 's|^metalink|#metalink|' /etc/yum.repos.d/epel.repo

# 再次清理并重建 yum 缓存
print_message "更新 yum 缓存..."
yum clean all
yum makecache

# 安装 vim 进行测试
print_message "安装 vim..."
yum install -y vim

# 验证配置
print_message "验证 yum 源配置..."
yum repolist

# 检查 vim 安装结果
if command -v vim &> /dev/null; then
    print_message "vim 安装成功！"
    vim --version | head -n 1
else
    print_error "vim 安装失败"
fi

print_message "YUM 源配置完成！"