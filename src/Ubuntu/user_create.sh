#!/bin/bash

# 创建管理员用户
USERNAME="admin"
PASSWORD="Secsmart#612"

# 创建用户
sudo useradd -m -s /bin/bash $USERNAME

# 设置密码
echo "$USERNAME:$PASSWORD" | sudo chpasswd

# 授予管理员权限
sudo usermod -aG sudo $USERNAME

# 设置家目录权限
sudo chmod 700 /home/$USERNAME

echo "用户 $USERNAME 已创建并授予管理员权限"