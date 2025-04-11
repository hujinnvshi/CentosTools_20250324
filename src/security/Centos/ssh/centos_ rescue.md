Centos 7.9 进入紧急救援模式详细步骤

#!/bin/bash

cat << 'EOF'
CentOS 7.9 进入紧急救援模式步骤说明：

1. 重启系统
   - 重启服务器
   - 在GRUB引导界面快速按'e'键进入编辑模式

2. 编辑GRUB引导参数
   - 找到以'linux16'或'linuxefi'开头的行
   - 在该行末尾添加以下参数（三选一）：
     a) rd.break：进入switch_root前的紧急模式
     b) emergency：进入紧急模式
     c) rescue：进入救援模式
   - 按Ctrl+X启动系统

3. 重新挂载根目录（只适用于rd.break模式）
   mount -o remount,rw /sysroot
   chroot /sysroot
   
4. 修改密码（示例）
   passwd root

5. 如果开启了SELinux，需要执行：
   touch /.autorelabel

6. 退出并重启
   exit        # 退出chroot环境（如果使用）
   exit        # 退出紧急模式
   reboot -f   # 强制重启系统

注意事项：
1. 建议使用rd.break模式，更安全可控
2. 操作前最好做好数据备份
3. 如果系统有SELinux，必须执行autorelabel
4. 重启后系统恢复正常需要一定时间

常见问题处理：
1. 如果无法进入GRUB：
   - 多次按ESC或Shift键
   - 检查BIOS引导顺序

2. 如果提示只读文件系统：
   - 执行remount命令：mount -o remount,rw /

3. SELinux重新标记时间较长：
   - 耐心等待，不要强制关机

4. 如果忘记root密码：
   - 使用rd.break模式进入
   - 重新设置密码即可
EOF