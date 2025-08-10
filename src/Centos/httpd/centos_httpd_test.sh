#!/bin/bash

# 循环执行三次操作
for i in {1..3}; do
    echo "========== 开始第 $i 次执行 =========="
    
    # 执行卸载脚本
    echo "执行卸载脚本..."
    ./centos_httpd_uninstall.sh
    echo "卸载脚本执行完成"
    
    # 执行安装脚本
    echo "执行安装脚本..."
    ./centos_httpd_install.sh
    echo "安装脚本执行完成"
    
    # 执行路径更新脚本
    echo "执行路径更新脚本..."
    ./centos_httpd_path_update.sh
    echo "路径更新脚本执行完成"
    
    echo "========== 第 $i 次执行完成 =========="
    echo ""
    
    # 添加延迟（可选）
    sleep 2
done

echo "所有操作已完成！"