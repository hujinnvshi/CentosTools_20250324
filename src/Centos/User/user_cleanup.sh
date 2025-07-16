#!/bin/bash

# 设置要清理的用户名
USERNAME="gxnt3csyh"

# 确认操作
read -p "即将删除用户 $USERNAME 及其主目录，是否继续？(y/n): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "操作已取消"
    exit 0
fi

# 检查用户是否存在
if ! id "$USERNAME" &>/dev/null; then
    echo "错误：用户 $USERNAME 不存在"
    exit 1
fi

# 删除用户及其主目录
echo "正在删除用户 $USERNAME..."
userdel -r "$USERNAME"
if [ $? -ne 0 ]; then
    echo "错误：删除用户失败"
    exit 1
fi
echo "用户 $USERNAME 已成功删除"

# 检查用户是否在wheel组中
if grep -q "^wheel:" /etc/group && grep -q "$USERNAME" /etc/group; then
    echo "正在从wheel组中移除用户 $USERNAME..."
    # 备份group文件
    cp /etc/group /etc/group.bak
    # 从wheel组中移除用户
    sed -i "s/\(^wheel:[^:]*:\)\(.*\)\b$USERNAME\b\(.*\)/\1\2\3/" /etc/group
    if [ $? -ne 0 ]; then
        echo "错误：从wheel组中移除用户失败，恢复原配置"
        cp /etc/group.bak /etc/group
        exit 1
    fi
    echo "用户 $USERNAME 已从wheel组中移除"
fi

# 检查sudoers文件是否有备份
if [ -f /etc/sudoers.bak ]; then
    echo "检测到sudoers文件备份，正在检查是否需要恢复..."
    
    # 比较当前sudoers与备份文件
    diff /etc/sudoers /etc/sudoers.bak >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        # 检查修改是否仅为wheel组配置
        if grep -q "^%wheel ALL=(ALL) ALL" /etc/sudoers && ! grep -q "^%wheel ALL=(ALL) ALL" /etc/sudoers.bak; then
            echo "正在恢复sudoers文件..."
            cp /etc/sudoers.bak /etc/sudoers
            
            # 验证sudoers文件语法
            visudo -c >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                echo "错误：恢复后的sudoers文件语法验证失败，保持现有配置"
                cp /etc/sudoers /etc/sudoers.bak
                exit 1
            fi
            echo "sudoers文件已恢复"
        else
            echo "sudoers文件有其他修改，保留现有配置"
        fi
    else
        echo "sudoers文件未修改，无需恢复"
    fi
    
    # 删除备份文件
    rm -f /etc/sudoers.bak
fi

echo "用户 $USERNAME 的清理操作已完成"