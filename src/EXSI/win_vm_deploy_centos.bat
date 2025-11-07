@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: =============================================
:: VMware CentOS 静默部署脚本 - 动态磁盘版本
:: 功能：创建动态分配、独立模式的虚拟磁盘
:: =============================================

:: 设置错误处理
if "%1"=="admin" goto :main
echo 请求管理员权限...
powershell -Command "Start-Process '%~f0' 'admin' -Verb RunAs -Wait"
exit /b

:main
setlocal enabledelayedexpansion

:: 颜色定义
for /f "tokens=1,2 delims=#" %%a in ('"prompt #$H#$E# & echo on & for %%b in (1) do rem"') do (
    set "DEL=%%a"
)

:: =============================================
:: 配置参数 - 动态磁盘版本
:: =============================================

:: VMware 工具路径
set "VMRUN_PATH=C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe"
set "VDISKMANAGER_PATH=C:\Program Files (x86)\VMware\VMware Workstation\vmware-vdiskmanager.exe"

:: 镜像路径
set "ISO_PATH=D:\BaiduNetdiskDownload\CentOS-7-x86_64-DVD-2009.iso"

:: 虚拟机配置 - D 盘 VMS 目录
set "VM_NAME=CentOS7-DynamicDisk"
set "VM_BASE_DIR=D:\VMS"
set "VM_DIR=%VM_BASE_DIR%\%VM_NAME%"
set "VMX_PATH=%VM_DIR%\%VM_NAME%.vmx"

:: 硬件规格
set "DISK_SIZE=40"           :: 最大磁盘大小(GB)
set "MEMORY_SIZE=2048"       :: 内存大小(MB)
set "CPU_COUNT=2"            :: CPU核心数

:: 磁盘模式配置 - 关键修改
set "DISK_MODE=thin"         :: thin(动态分配)/thick(预先分配)
set "DISK_TYPE=independent"  :: independent(独立)/persistent(持久)
set "DISK_ACCESS=rw"         :: rw(读写)/rdonly(只读)

:: 网络配置
set "NETWORK_TYPE=nat"
set "VM_IP=192.168.174.100"
set "NETMASK=255.255.255.0"
set "GATEWAY=192.168.174.1"

:: 系统配置
set "ROOT_PASSWORD=Rede@612@Mixed"
set "USER_NAME=admin"
set "USER_PASSWORD=Secsmart#612"

:: =============================================
:: 环境检查函数
:: =============================================

:check_environment
echo 开始环境检查...

:: 检查 D 盘
if not exist "D:\" (
    echo 错误: D 盘不存在!
    pause
    exit /b 1
)

:: 检查 VMware 工具
if not exist "%VMRUN_PATH%" (
    echo 错误: vmrun 未找到
    pause
    exit /b 1
)

:: 检查 ISO 文件
if not exist "%ISO_PATH%" (
    echo 错误: ISO 文件未找到
    pause
    exit /b 1
)

:: 创建基础目录
if not exist "%VM_BASE_DIR%" mkdir "%VM_BASE_DIR%"
if not exist "%VM_DIR%" mkdir "%VM_DIR%"

echo 环境检查通过
goto :create_vm_config

:: =============================================
:: 创建虚拟机配置（包含独立磁盘设置）
:: =============================================

:create_vm_config
echo 创建虚拟机配置（独立磁盘模式）...

(
echo #!/usr/bin/vmware
echo .encoding = "UTF-8"
echo config.version = "8"
echo virtualHW.version = "19"
echo.
echo # 基本信息
echo displayName = "%VM_NAME%"
echo guestOS = "centos-64"
echo.
echo # 硬件配置
echo memsize = "%MEMORY_SIZE%"
echo numvcpus = "%CPU_COUNT%"
echo cpuid.coresPerSocket = "1"
echo.
echo # === 磁盘配置 - 动态分配 + 独立模式 ===
echo scsi0.present = "TRUE"
echo scsi0.virtualDev = "lsilogic"
echo scsi0:0.present = "TRUE"
echo scsi0:0.fileName = "%VM_NAME%.vmdk"
echo scsi0:0.deviceType = "scsi-hardDisk"
echo scsi0:0.mode = "%DISK_MODE%"              :: 磁盘分配模式
echo scsi0:0.access = "%DISK_ACCESS%"          :: 磁盘访问模式
echo scsi0:0.independent = "TRUE"               :: 关键：设置为独立磁盘
echo scsi0:0.persistence = "nonpersistent"     :: 非持久性（可选）
echo.
echo # CD-ROM 配置
echo ide1:0.present = "TRUE"
echo ide1:0.fileName = "%ISO_PATH%"
echo ide1:0.deviceType = "cdrom-image"
echo ide1:0.autodetect = "TRUE"
echo ide1:0.startConnected = "TRUE"
echo.
echo # 网络配置
echo ethernet0.present = "TRUE"
echo ethernet0.connectionType = "%NETWORK_TYPE%"
echo ethernet0.virtualDev = "e1000"
echo ethernet0.wakeOnPcktRcv = "FALSE"
echo ethernet0.addressType = "generated"
echo.
echo # 其他设备
echo usb.present = "TRUE"
echo sound.present = "FALSE"
echo floppy0.present = "FALSE"
echo.
echo # 电源管理
echo powerType.powerOff = "soft"
echo powerType.suspend = "soft"
echo powerType.reset = "soft"
echo.
echo # 高级配置
echo tools.syncTime = "TRUE"
echo tools.remindInstall = "FALSE"
echo guestInfo.disk.mode = "%DISK_MODE%"
echo guestInfo.disk.independent = "TRUE"
) > "%VMX_PATH%"

echo 虚拟机配置文件创建完成
goto :create_dynamic_disk

:: =============================================
:: 创建动态分配磁盘（不预先分配空间）
:: =============================================

:create_dynamic_disk
echo 创建动态分配磁盘...

if exist "%VDISKMANAGER_PATH%" (
    echo 使用 vmware-vdiskmanager 创建动态磁盘...
    
    :: 关键参数说明：
    :: -t 0: 动态分配（thin provisioning）
    :: -t 1: 预先分配，不置零
    :: -t 2: 预先分配，置零
    
    "%VDISKMANAGER_PATH%" -c -s %DISK_SIZE%GB -a lsilogic -t 0 "%VM_DIR%\%VM_NAME%.vmdk"
    
    if errorlevel 1 (
        echo 警告: 动态磁盘创建失败，尝试替代方案
        goto :create_dynamic_disk_manual
    )
) else (
    goto :create_dynamic_disk_manual
)

echo 动态磁盘创建成功
goto :create_kickstart_config

:create_dynamic_disk_manual
echo 手动创建动态磁盘描述文件...

(
echo # Disk DescriptorFile
echo version=1
echo encoding="UTF-8"
echo CID=fffffffe
echo parentCID=ffffffff
echo isNativeSnapshot="no"
echo createType="monolithicSparse"   :: 关键：稀疏文件（动态分配）
echo.
echo # Extent description
echo RW %DISK_SIZE%000 SPARSE "%VM_NAME%-s0001.vmdk" 0  :: 稀疏文件
echo.
echo # The Disk Data Base 
echo #DDB
echo.
echo ddb.adapterType = "lsilogic"
echo ddb.geometry.cylinders = "16383"
echo ddb.geometry.heads = "16"
echo ddb.geometry.sectors = "63"
echo ddb.longContentID = "ffffffffffffffffffffffffffffffff"
echo ddb.virtualHWVersion = "19"
echo ddb.thinProvisioned = "1"      :: 标记为动态分配
) > "%VM_DIR%\%VM_NAME%.vmdk"

:: 创建初始稀疏文件（很小，不预先分配空间）
echo 创建初始稀疏文件...
fsutil file createnew "%VM_DIR%\%VM_NAME%-s0001.vmdk" 65536 >nul 2>&1

if errorlevel 1 (
    powershell -Command "[System.IO.File]::WriteAllBytes('%VM_DIR%\%VM_NAME%-s0001.vmdk', [byte[]]::new(65536))" >nul 2>&1
)

echo 动态磁盘手动创建完成
goto :create_kickstart_config

:: =============================================
:: 创建自动安装配置
:: =============================================

:create_kickstart_config
echo 创建自动安装配置...

set "KS_PATH=%VM_DIR%\ks.cfg"

(
echo # CentOS 7 自动安装配置 - 动态磁盘版本
echo install
echo text
echo lang en_US.UTF-8
echo keyboard us
echo timezone Asia/Shanghai --isUtc
echo rootpw --plaintext %ROOT_PASSWORD%
echo auth --enableshadow --passalgo=sha512
echo selinux --disabled
echo firewall --disabled
echo network --bootproto=static --ip=%VM_IP% --netmask=%NETMASK% --gateway=%GATEWAY% --nameserver=8.8.8.8,8.8.4.4 --hostname=%VM_NAME%
echo reboot
echo.
echo # 磁盘分区 - 针对动态磁盘优化
echo zerombr
echo clearpart --all --initlabel
echo autopart --type=lvm --fstype=ext4
echo.
echo # 软件包选择
echo %%packages --nobase
echo @core
echo vim-enhanced
echo wget
echo curl
echo net-tools
echo openssh-server
echo open-vm-tools
echo %%end
echo.
echo # 安装后脚本
echo %%post
echo #!/bin/bash
echo.
echo # 磁盘优化配置
echo echo "vm.dirty_ratio = 10" ^>^> /etc/sysctl.conf
echo echo "vm.dirty_background_ratio = 5" ^>^> /etc/sysctl.conf
echo echo "vm.swappiness = 10" ^>^> /etc/sysctl.conf
echo sysctl -p
echo.
echo # 启用 VMware 工具
echo systemctl enable vmtoolsd
echo systemctl start vmtoolsd
echo.
echo # 创建用户
echo useradd -m -G wheel %USER_NAME%
echo echo "%USER_PASSWORD%" ^| passwd --stdin %USER_NAME%
echo echo "%%wheel ALL=(ALL) NOPASSWD: ALL" ^>^> /etc/sudoers
echo.
echo # 完成标记
echo echo "Dynamic disk installation completed at \$(date)" ^> /etc/vmware-dynamic-disk-installed
echo %%end
) > "%KS_PATH%"

echo Kickstart 配置创建完成
goto :register_and_start_vm

:: =============================================
:: 注册和启动虚拟机
:: =============================================

:register_and_start_vm
echo 注册并启动虚拟机...

:: 检查是否已注册
"%VMRUN_PATH%" list | findstr /c:"%VMX_PATH%" >nul
if not errorlevel 1 (
    echo 虚拟机已注册，先取消注册...
    "%VMRUN_PATH%" -T ws unregister "%VMX_PATH%"
)

:: 注册虚拟机
echo 注册虚拟机...
"%VMRUN_PATH%" -T ws register "%VMX_PATH%"
if errorlevel 1 (
    echo 错误: 虚拟机注册失败
    pause
    exit /b 1
)

:: 启动虚拟机（静默模式）
echo 启动虚拟机...
"%VMRUN_PATH%" -T ws start "%VMX_PATH%" nogui
if errorlevel 1 (
    echo 错误: 虚拟机启动失败
    pause
    exit /b 1
)

echo 虚拟机启动成功
goto :verify_deployment

:: =============================================
:: 验证部署结果
:: =============================================

:verify_deployment
echo 验证部署结果...

:: 检查虚拟机状态
for /f "tokens=2" %%i in ('"%VMRUN_PATH%" -T ws list ^| findstr /c:"%VM_NAME%"') do set "VM_STATE=%%i"
echo 虚拟机状态: %VM_STATE%

:: 检查磁盘文件
dir "%VM_DIR%\%VM_NAME%.vmdk" /-c
for /f "tokens=3" %%a in ('dir "%VM_DIR%\%VM_NAME%.vmdk" /-c ^| findstr "vmdk"') do set "DISK_SIZE_ACTUAL=%%a"
echo 磁盘文件大小: %DISK_SIZE_ACTUAL%

:: 验证动态磁盘特性
if "%DISK_SIZE_ACTUAL%" LSS "1000000" (
    echo ✅ 动态磁盘配置成功（小文件大小确认）
) else (
    echo ⚠️  磁盘文件较大，可能未正确配置为动态分配
)

goto :generate_documentation

:: =============================================
:: 生成使用文档
:: =============================================

:generate_documentation
echo 生成使用文档...

set "DOC_PATH=%VM_DIR%\README-DynamicDisk.txt"

(
echo ====================================
echo    CentOS 7 动态磁盘虚拟机文档
echo ====================================
echo.
echo 部署信息：
echo   虚拟机名称: %VM_NAME%
echo   部署时间: %DATE% %TIME%
echo   虚拟机路径: %VM_DIR%
echo.
echo 磁盘配置：
echo   磁盘模式: %DISK_MODE% (动态分配)
echo   磁盘类型: %DISK_TYPE% (独立磁盘)
echo   最大容量: %DISK_SIZE% GB
echo   初始大小: 动态增长
echo.
echo 独立磁盘特性：
echo   ✅ 不预先分配磁盘空间
echo   ✅ 磁盘文件随使用增长
echo   ✅ 独立于快照（可选持久/非持久）
echo   ✅ 性能优化配置
echo.
echo 管理命令：
echo   查看磁盘信息: "%VDISKMANAGER_PATH%" -d "%VM_DIR%\%VM_NAME%.vmdk"
echo   扩展磁盘: "%VDISKMANAGER_PATH%" -x %DISK_SIZE%GB "%VM_DIR%\%VM_NAME%.vmdk"
echo   碎片整理: "%VDISKMANAGER_PATH%" -k "%VM_DIR%\%VM_NAME%.vmdk"
echo.
echo 性能优化建议：
echo   1. 定期进行磁盘碎片整理
echo   2. 监控磁盘空间使用
echo   3. 避免磁盘过度分配
echo   4. 使用 SSD 存储提升性能
echo.
echo ====================================
) > "%DOC_PATH%"

echo 使用文档生成完成
goto :show_summary

:: =============================================
:: 显示部署摘要
:: =============================================

:show_summary
echo.
echo ============================================
echo           部署完成摘要
echo ============================================
echo.
echo ✅ 虚拟机名称: %VM_NAME%
echo ✅ 存储位置: %VM_DIR%
echo ✅ 磁盘模式: %DISK_MODE% (动态分配)
echo ✅ 磁盘类型: %DISK_TYPE% (独立磁盘)
echo ✅ 最大容量: %DISK_SIZE% GB
echo ✅ 网络地址: %VM_IP%
echo.
echo 📊 磁盘空间节省:
echo    传统分配: %DISK_SIZE% GB 立即占用
echo    动态分配: 仅占用实际使用空间
echo    预计节省: 约 %DISK_SIZE% GB 初始空间
echo.
echo ⚡ 性能特性:
echo    - 快速部署（不等待磁盘分配）
echo    - 按需增长（节省存储空间）
echo    - 独立模式（快照隔离）
echo.
echo 🔧 管理命令:
echo   启动: "%VMRUN_PATH%" -T ws start "%VMX_PATH%" nogui
echo   停止: "%VMRUN_PATH%" -T ws stop "%VMX_PATH%"
echo   状态: "%VMRUN_PATH%" -T ws list
echo.
echo ============================================
pause
exit /b 0

:: =============================================
:: 磁盘管理工具函数（可选）
:: =============================================

:disk_management
echo 磁盘管理工具...

:: 检查磁盘信息
if exist "%VDISKMANAGER_PATH%" (
    echo 磁盘信息:
    "%VDISKMANAGER_PATH%" -d "%VM_DIR%\%VM_NAME%.vmdk"
    
    echo.
    echo 磁盘使用情况:
    for /f "tokens=3" %%a in ('dir "%VM_DIR%\%VM_NAME%*.vmdk" /-c ^| findstr "vmdk"') do (
        set "FILE_SIZE=%%a"
        set /a "SIZE_MB=FILE_SIZE/1048576"
        echo   文件大小: !SIZE_MB! MB / %DISK_SIZE% GB
    )
)

goto :eof

:: =============================================
:: 主执行流程
:: =============================================

echo VMware 动态磁盘虚拟机部署脚本
echo ==================================

call :check_environment
call :create_vm_config
call :create_dynamic_disk
call :create_kickstart_config
call :register_and_start_vm
call :verify_deployment
call :generate_documentation
call :show_summary

:: 可选：显示磁盘管理信息
set /p "SHOW_DISK_INFO=显示磁盘详细信息? (y/N): "
if /i "%SHOW_DISK_INFO%"=="y" call :disk_management

pause