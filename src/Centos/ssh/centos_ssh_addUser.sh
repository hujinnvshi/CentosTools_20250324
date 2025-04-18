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

# 添加用户函数
add_user_with_ssh() {
    local username="hiveadmin"
    local password="Secsmart#612"
    local group="hadoop"
    local home_dir="/data/${username}"
    
    # 检查是否为root用户
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用root用户执行此脚本"
    fi
    
    # 创建用户组
    if ! getent group ${group} > /dev/null; then
        print_message "创建用户组 ${group}"
        groupadd ${group} || print_error "创建用户组失败"
    fi
    
    # 创建工作目录
    print_message "创建工作目录 ${home_dir}"
    mkdir -p ${home_dir} || print_error "创建工作目录失败"
    
    # 创建用户
    print_message "创建用户 ${username}"
    useradd -g ${group} -d ${home_dir} -m -s /bin/bash ${username} || print_error "创建用户失败"
    
    # 设置密码
    print_message "设置用户密码"
    echo "${username}:${password}" | chpasswd || print_error "设置密码失败"
    
    # 配置SSH目录
    print_message "配置SSH免密登录"
    local ssh_dir="${home_dir}/.ssh"
    mkdir -p ${ssh_dir}
    
    # 生成SSH密钥
    su - ${username} -c "ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa"
    su - ${username} -c "cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys"
    
    # 设置SSH目录权限
    chown -R ${username}:${group} ${ssh_dir}
    chmod 700 ${ssh_dir}
    chmod 600 ${ssh_dir}/authorized_keys
    
    # 设置目录权限
    chown -R ${username}:${group} ${home_dir}
    chmod 755 ${home_dir}
    
    print_message "用户创建完成！"
    print_message "用户名：${username}"
    print_message "密码：${password}"
    print_message "主目录：${home_dir}"
    print_message "SSH密钥已生成"
}

# 执行函数
add_user_with_ssh