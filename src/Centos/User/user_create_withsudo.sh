#!/bin/bash

# 设置用户名和密码(高性能测试机3用户)
USERNAME="gxnt3yh"
PASSWORD="Secsmart#612"

# 创建用户
echo "正在创建用户 $USERNAME..."
useradd $USERNAME
if [ $? -ne 0 ]; then
    echo "错误：创建用户失败"
    exit 1
fi

# 设置密码
echo "正在为用户 $USERNAME 设置密码..."
echo "$USERNAME:$PASSWORD" | chpasswd --encrypted
if [ $? -ne 0 ]; then
    echo "错误：设置密码失败"
    userdel -r $USERNAME  # 回滚用户创建
    exit 1
fi

# 将用户添加到wheel组
echo "正在将用户 $USERNAME 添加到wheel组..."
usermod -aG wheel $USERNAME
if [ $? -ne 0 ]; then
    echo "错误：添加用户到wheel组失败"
    userdel -r $USERNAME  # 回滚用户创建
    exit 1
fi

# 配置sudo权限
echo "正在配置sudo权限..."
if [ -f /etc/sudoers ]; then
    # 备份sudoers文件
    cp /etc/sudoers /etc/sudoers.bak
    
    # 确保wheel组用户可以使用sudo
    if ! grep -q "^%wheel" /etc/sudoers; then
        echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
    else
        # 如果已有%wheel行，确保其未被注释
        sed -i 's/^#\s*\(%wheel\s\+ALL=(ALL)\s\+ALL\)/\1/' /etc/sudoers
    fi
    
    # 验证sudoers文件语法
    visudo -c >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "错误：sudoers文件语法验证失败，恢复原始配置"
        cp /etc/sudoers.bak /etc/sudoers
        userdel -r $USERNAME  # 回滚用户创建
        exit 1
    fi
    echo "sudo权限配置成功"
else
    echo "错误：未找到sudoers文件"
    userdel -r $USERNAME  # 回滚用户创建
    exit 1
fi

echo "用户 $USERNAME 创建成功，密码为 $PASSWORD"
echo "使用方法：su - $USERNAME 然后运行需要sudo权限的命令"