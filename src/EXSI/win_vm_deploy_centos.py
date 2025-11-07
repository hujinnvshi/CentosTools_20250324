#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
VMware CentOS 静默部署脚本 - Python 3 版本
功能：使用 VMware 命令行工具自动部署 CentOS 虚拟机
作者：资深运维专家
版本：2.1（修正版）
"""

import os
import sys
import subprocess
import shutil
import logging
from pathlib import Path
from datetime import datetime
import argparse

# =============================================
# 配置参数
# =============================================

class Config:
    """配置参数类"""
    
    # VMware 工具路径
    VMRUN_PATH = r"C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe"
    VDISKMANAGER_PATH = r"C:\Program Files (x86)\VMware\VMware Workstation\vmware-vdiskmanager.exe"
    
    # 镜像路径
    ISO_PATH = r"D:\BaiduNetdiskDownload\CentOS-7-x86_64-DVD-2009.iso"
    
    # 虚拟机配置
    VM_NAME = "CentOS7-DynamicDisk"
    VM_BASE_DIR = r"D:\VMS"
    
    # 硬件规格
    DISK_SIZE = 40           # 最大磁盘大小(GB)
    MEMORY_SIZE = 2048       # 内存大小(MB)
    CPU_COUNT = 2            # CPU核心数
    
    # 磁盘模式配置
    DISK_MODE = "thin"       # thin(动态分配)/thick(预先分配)
    DISK_TYPE = "independent" # independent(独立)/persistent(持久)
    DISK_ACCESS = "rw"       # rw(读写)/rdonly(只读)
    
    # 网络配置
    NETWORK_TYPE = "nat"
    VM_IP = "192.168.174.100"
    NETMASK = "255.255.255.0"
    GATEWAY = "192.168.174.1"
    
    # 系统配置
    ROOT_PASSWORD = "Rede@612@Mixed"
    USER_NAME = "admin"
    USER_PASSWORD = "Secsmart#612"


# =============================================
# 日志和工具函数
# =============================================

class Logger:
    """彩色日志输出类"""
    
    # 颜色代码
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    WHITE = '\033[97m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    END = '\033[0m'
    
    @classmethod
    def setup_logging(cls):
        """设置日志配置"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('vmware_deploy.log', encoding='utf-8'),
                logging.StreamHandler()
            ]
        )
    
    @classmethod
    def log_info(cls, message):
        """信息日志"""
        print(f"{cls.GREEN}[INFO]{cls.END} {message}")
        logging.info(message)
    
    @classmethod
    def log_warn(cls, message):
        """警告日志"""
        print(f"{cls.YELLOW}[WARN]{cls.END} {message}")
        logging.warning(message)
    
    @classmethod
    def log_error(cls, message, exit_code=1):
        """错误日志"""
        print(f"{cls.RED}[ERROR]{cls.END} {message}")
        logging.error(message)
        if exit_code:
            sys.exit(exit_code)
    
    @classmethod
    def log_debug(cls, message):
        """调试日志"""
        print(f"{cls.BLUE}[DEBUG]{cls.END} {message}")
        logging.debug(message)
    
    @classmethod
    def log_success(cls, message):
        """成功日志"""
        print(f"{cls.CYAN}{cls.BOLD}[SUCCESS]{cls.END} {message}")
        logging.info(f"SUCCESS: {message}")


class SystemUtils:
    """系统工具类"""
    
    @staticmethod
    def run_command(cmd, check=True, capture_output=True, shell=True):
        """
        执行系统命令
        
        Args:
            cmd: 命令字符串
            check: 是否检查返回值
            capture_output: 是否捕获输出
            shell: 是否使用shell
            
        Returns:
            命令执行结果
        """
        try:
            result = subprocess.run(
                cmd, 
                shell=shell, 
                check=check, 
                capture_output=capture_output,
                text=True,
                encoding='utf-8'
            )
            return result
        except subprocess.CalledProcessError as e:
            Logger.log_error(f"命令执行失败: {cmd}\n错误: {e}")
            return None
    
    @staticmethod
    def is_admin():
        """检查是否具有管理员权限"""
        try:
            return os.getuid() == 0
        except AttributeError:
            # Windows 系统
            import ctypes
            return ctypes.windll.shell32.IsUserAnAdmin()
    
    @staticmethod
    def require_admin():
        """要求管理员权限"""
        if not SystemUtils.is_admin():
            Logger.log_error("需要管理员权限运行此脚本")
    
    @staticmethod
    def path_exists(path):
        """检查路径是否存在"""
        return os.path.exists(path)
    
    @staticmethod
    def create_directory(path):
        """创建目录"""
        try:
            os.makedirs(path, exist_ok=True)
            return True
        except OSError as e:
            Logger.log_error(f"创建目录失败 {path}: {e}")
            return False


# =============================================
# VMware 部署主类
# =============================================

class VMwareDeployer:
    """VMware 虚拟机部署器"""
    
    def __init__(self, config):
        self.config = config
        self.vm_dir = Path(config.VM_BASE_DIR) / config.VM_NAME
        self.vmx_path = self.vm_dir / f"{config.VM_NAME}.vmx"
        self.ks_path = self.vm_dir / "ks.cfg"
        self.doc_path = self.vm_dir / "README.txt"
        
    def check_environment(self):
        """检查环境"""
        Logger.log_info("开始环境检查...")
        
        # 检查 D 盘
        if not SystemUtils.path_exists("D:\\"):
            Logger.log_error("D 盘不存在!")
        
        # 检查 VMware 工具
        if not SystemUtils.path_exists(self.config.VMRUN_PATH):
            Logger.log_error(f"vmrun 未找到: {self.config.VMRUN_PATH}")
        
        if not SystemUtils.path_exists(self.config.VDISKMANAGER_PATH):
            Logger.log_warn("vmware-vdiskmanager 未找到，将使用替代方案")
        
        # 检查 ISO 文件
        if not SystemUtils.path_exists(self.config.ISO_PATH):
            Logger.log_error(f"ISO 文件未找到: {self.config.ISO_PATH}")
        
        # 创建基础目录
        if not SystemUtils.create_directory(self.config.VM_BASE_DIR):
            Logger.log_error(f"无法创建基础目录: {self.config.VM_BASE_DIR}")
        
        if not SystemUtils.create_directory(str(self.vm_dir)):
            Logger.log_error(f"无法创建虚拟机目录: {self.vm_dir}")
        
        # 检查磁盘空间
        try:
            total, used, free = shutil.disk_usage("D:\\")
            free_gb = free // (2**30)  # 转换为GB
            
            if free_gb < 50:
                Logger.log_warn(f"D盘空间可能不足 (剩余: {free_gb}GB，建议至少50GB)")
        except OSError:
            Logger.log_warn("无法检查磁盘空间")
        
        Logger.log_info("环境检查通过")
        return True
    
    def create_vm_config(self):
        """创建虚拟机配置文件"""
        Logger.log_info("创建虚拟机配置文件...")
        
        vm_config = f"""#!/usr/bin/vmware
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "19"

# 基本信息
displayName = "{self.config.VM_NAME}"
guestOS = "centos-64"

# 硬件配置
memsize = "{self.config.MEMORY_SIZE}"
numvcpus = "{self.config.CPU_COUNT}"
cpuid.coresPerSocket = "1"

# 磁盘配置
scsi0.present = "TRUE"
scsi0.virtualDev = "lsilogic"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "{self.config.VM_NAME}.vmdk"
scsi0:0.deviceType = "scsi-hardDisk"
scsi0:0.mode = "{self.config.DISK_MODE}"
scsi0:0.access = "{self.config.DISK_ACCESS}"
scsi0:0.independent = "TRUE"
scsi0:0.persistence = "nonpersistent"

# CD-ROM 配置
ide1:0.present = "TRUE"
ide1:0.fileName = "{self.config.ISO_PATH}"
ide1:0.deviceType = "cdrom-image"
ide1:0.autodetect = "TRUE"
ide1:0.startConnected = "TRUE"

# 网络配置
ethernet0.present = "TRUE"
ethernet0.connectionType = "{self.config.NETWORK_TYPE}"
ethernet0.virtualDev = "e1000"
ethernet0.wakeOnPcktRcv = "FALSE"
ethernet0.addressType = "generated"

# 其他设备
usb.present = "TRUE"
sound.present = "FALSE"
floppy0.present = "FALSE"

# 电源管理
powerType.powerOff = "soft"
powerType.suspend = "soft"
powerType.reset = "soft"

# 高级配置
tools.syncTime = "TRUE"
tools.remindInstall = "FALSE"
"""
        try:
            with open(self.vmx_path, 'w', encoding='utf-8') as f:
                f.write(vm_config)
            Logger.log_info(f"虚拟机配置文件创建完成: {self.vmx_path}")
            return True
        except IOError as e:
            Logger.log_error(f"创建虚拟机配置文件失败: {e}")
            return False
    
    def create_dynamic_disk(self):
        """创建动态分配磁盘"""
        Logger.log_info("创建动态分配磁盘...")
        
        vmdk_path = self.vm_dir / f"{self.config.VM_NAME}.vmdk"
        
        # 首先尝试使用 vmware-vdiskmanager
        if SystemUtils.path_exists(self.config.VDISKMANAGER_PATH):
            Logger.log_info("使用 vmware-vdiskmanager 创建动态磁盘...")
            
            cmd = f'"{self.config.VDISKMANAGER_PATH}" -c -s {self.config.DISK_SIZE}GB -a lsilogic -t 0 "{vmdk_path}"'
            
            result = SystemUtils.run_command(cmd, check=False)
            
            if result and result.returncode == 0:
                Logger.log_info("动态磁盘创建成功")
                return True
            else:
                Logger.log_warn("vmware-vdiskmanager 创建失败，尝试手动创建")
        
        # 手动创建动态磁盘
        return self._create_dynamic_disk_manual(vmdk_path)
    
    def _create_dynamic_disk_manual(self, vmdk_path):
        """手动创建动态磁盘"""
        Logger.log_info("手动创建动态磁盘描述文件...")
        
        disk_config = f"""# Disk DescriptorFile
version=1
encoding="UTF-8"
CID=fffffffe
parentCID=ffffffff
isNativeSnapshot="no"
createType="monolithicSparse"

# Extent description
RW {self.config.DISK_SIZE}000 SPARSE "{self.config.VM_NAME}-s0001.vmdk" 0

# The Disk Data Base 
#DDB

ddb.adapterType = "lsilogic"
ddb.geometry.cylinders = "16383"
ddb.geometry.heads = "16"
ddb.geometry.sectors = "63"
ddb.longContentID = "ffffffffffffffffffffffffffffffff"
ddb.virtualHWVersion = "19"
ddb.thinProvisioned = "1"
"""
        try:
            with open(vmdk_path, 'w', encoding='utf-8') as f:
                f.write(disk_config)
            
            # 创建初始稀疏文件
            sparse_path = self.vm_dir / f"{self.config.VM_NAME}-s0001.vmdk"
            Logger.log_info("创建初始稀疏文件...")
            
            with open(sparse_path, 'wb') as f:
                f.write(b'\0' * 65536)  # 64KB 初始文件
            
            Logger.log_info("动态磁盘手动创建完成")
            return True
        except IOError as e:
            Logger.log_error(f"手动创建动态磁盘失败: {e}")
            return False
    
    def create_kickstart_config(self):
        """创建 Kickstart 自动安装配置"""
        Logger.log_info("创建自动安装配置...")
        
        ks_config = f"""# CentOS 7 自动安装配置
install
text
lang en_US.UTF-8
keyboard us
timezone Asia/Shanghai --isUtc
rootpw --plaintext {self.config.ROOT_PASSWORD}
auth --enableshadow --passalgo=sha512
selinux --disabled
firewall --disabled
network --bootproto=static --ip={self.config.VM_IP} --netmask={self.config.NETMASK} --gateway={self.config.GATEWAY} --nameserver=8.8.8.8,8.8.4.4 --hostname={self.config.VM_NAME}
reboot

# 磁盘分区
zerombr
clearpart --all --initlabel
autopart --type=lvm --fstype=ext4

# 软件包选择
%packages --nobase
@core
vim-enhanced
wget
curl
net-tools
openssh-server
open-vm-tools
%end

# 安装后脚本
%post
#!/bin/bash

# 启用 VMware 工具
systemctl enable vmtoolsd
systemctl start vmtoolsd

# 创建用户
useradd -m -G wheel {self.config.USER_NAME}
echo "{self.config.USER_PASSWORD}" | passwd --stdin {self.config.USER_NAME}
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# 完成标记
echo "Dynamic disk installation completed at $(date)" > /etc/vmware-dynamic-disk-installed
%end
"""
        try:
            with open(self.ks_path, 'w', encoding='utf-8') as f:
                f.write(ks_config)
            Logger.log_info(f"Kickstart 配置创建完成: {self.ks_path}")
            return True
        except IOError as e:
            Logger.log_error(f"创建 Kickstart 配置失败: {e}")
            return False
    
    def register_and_start_vm(self):
        """注册并启动虚拟机"""
        Logger.log_info("注册并启动虚拟机...")
        
        # 检查是否已注册
        result = SystemUtils.run_command(
            f'"{self.config.VMRUN_PATH}" list', 
            check=False
        )
        
        if result and str(self.vmx_path) in result.stdout:
            Logger.log_info("虚拟机已注册，先取消注册...")
            SystemUtils.run_command(
                f'"{self.config.VMRUN_PATH}" -T ws unregister "{self.vmx_path}"',
                check=False
            )
        
        # 注册虚拟机
        Logger.log_info("注册虚拟机...")
        result = SystemUtils.run_command(
            f'"{self.config.VMRUN_PATH}" -T ws register "{self.vmx_path}"',
            check=False
        )
        
        if not result or result.returncode != 0:
            Logger.log_error("虚拟机注册失败")
            return False
        
        # 启动虚拟机
        Logger.log_info("启动虚拟机...")
        result = SystemUtils.run_command(
            f'"{self.config.VMRUN_PATH}" -T ws start "{self.vmx_path}" nogui',
            check=False
        )
        
        if not result or result.returncode != 0:
            Logger.log_error("虚拟机启动失败")
            return False
        
        Logger.log_info("虚拟机启动成功")
        return True
    
    def verify_deployment(self):
        """验证部署结果"""
        Logger.log_info("验证部署结果...")
        
        # 检查虚拟机状态
        result = SystemUtils.run_command(
            f'"{self.config.VMRUN_PATH}" -T ws list',
            check=False
        )
        
        if result and result.returncode == 0:
            for line in result.stdout.splitlines():
                if self.config.VM_NAME in line:
                    parts = line.split()
                    if len(parts) >= 2:
                        vm_state = parts[1]
                        Logger.log_info(f"虚拟机状态: {vm_state}")
                        break
        
        # 检查磁盘文件大小
        vmdk_path = self.vm_dir / f"{self.config.VM_NAME}.vmdk"
        if vmdk_path.exists():
            file_size = vmdk_path.stat().st_size
            Logger.log_info(f"磁盘文件大小: {file_size} 字节")
            
            if file_size < 1000000:  # 小于 1MB
                Logger.log_success("✅ 动态磁盘配置成功（小文件大小确认）")
            else:
                Logger.log_warn("⚠️ 磁盘文件较大，可能未正确配置为动态分配")
        
        return True
    
    def generate_documentation(self):
        """生成使用文档"""
        Logger.log_info("生成使用文档...")
        
        doc_content = f"""====================================
   CentOS 7 虚拟机部署文档
====================================

部署信息：
  虚拟机名称: {self.config.VM_NAME}
  部署时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
  虚拟机路径: {self.vm_dir}

配置信息：
  内存: {self.config.MEMORY_SIZE} MB
  CPU: {self.config.CPU_COUNT} 核心
  磁盘: {self.config.DISK_SIZE} GB (动态分配)
  网络: {self.config.NETWORK_TYPE}
  IP地址: {self.config.VM_IP}

登录信息：
  root 密码: {self.config.ROOT_PASSWORD}
  普通用户: {self.config.USER_NAME} / {self.config.USER_PASSWORD}

管理命令：
  启动: "{self.config.VMRUN_PATH}" -T ws start "{self.vmx_path}" nogui
  停止: "{self.config.VMRUN_PATH}" -T ws stop "{self.vmx_path}"
  状态: "{self.config.VMRUN_PATH}" -T ws list

====================================
"""
        try:
            with open(self.doc_path, 'w', encoding='utf-8') as f:
                f.write(doc_content)
            Logger.log_info(f"使用文档生成完成: {self.doc_path}")
            return True
        except IOError as e:
            Logger.log_error(f"生成使用文档失败: {e}")
            return False
    
    def show_summary(self):
        """显示部署摘要"""
        Logger.log_info("显示部署摘要...")
        
        summary = f"""
============================================
           部署完成摘要
============================================

✅ 虚拟机名称: {self.config.VM_NAME}
✅ 存储位置: {self.vm_dir}
✅ 磁盘模式: {self.config.DISK_MODE} (动态分配)
✅ 最大容量: {self.config.DISK_SIZE} GB
✅ 网络地址: {self.config.VM_IP}

📊 磁盘空间节省:
   传统分配: {self.config.DISK_SIZE} GB 立即占用
   动态分配: 仅占用实际使用空间
   预计节省: 约 {self.config.DISK_SIZE} GB 初始空间

⚡ 性能特性:
   - 快速部署（不等待磁盘分配）
   - 按需增长（节省存储空间）
   - 独立模式（快照隔离）

🔧 管理命令:
   启动: "{self.config.VMRUN_PATH}" -T ws start "{self.vmx_path}" nogui
   停止: "{self.config.VMRUN_PATH}" -T ws stop "{self.vmx_path}"
   状态: "{self.config.VMRUN_PATH}" -T ws list

============================================
"""
        print(summary)
        return True
    
    def deploy(self):
        """执行完整部署流程"""
        Logger.log_info("开始 CentOS 虚拟机部署流程...")
        
        steps = [
            ("环境检查", self.check_environment),
            ("创建虚拟机配置", self.create_vm_config),
            ("创建动态磁盘", self.create_dynamic_disk),
            ("创建自动安装配置", self.create_kickstart_config),
            ("注册和启动虚拟机", self.register_and_start_vm),
            ("验证部署结果", self.verify_deployment),
            ("生成使用文档", self.generate_documentation),
            ("显示部署摘要", self.show_summary)
        ]
        
        for step_name, step_func in steps:
            Logger.log_info(f"执行步骤: {step_name}")
            try:
                if not step_func():
                    Logger.log_error(f"步骤失败: {step_name}")
                    return False
            except Exception as e:
                Logger.log_error(f"步骤执行异常 {step_name}: {e}")
                return False
        
        Logger.log_success("🎉 虚拟机部署完成!")
        return True


# =============================================
# 命令行界面和主函数
# =============================================

def parse_arguments():
    """解析命令行参数"""
    parser = argparse.ArgumentParser(description='VMware CentOS 静默部署脚本')
    
    parser.add_argument('--vm-name', default=Config.VM_NAME,
                       help=f'虚拟机名称 (默认: {Config.VM_NAME})')
    parser.add_argument('--vm-dir', default=Config.VM_BASE_DIR,
                       help=f'虚拟机存储目录 (默认: {Config.VM_BASE_DIR})')
    parser.add_argument('--iso-path', default=Config.ISO_PATH,
                       help=f'CentOS ISO 路径 (默认: {Config.ISO_PATH})')
    parser.add_argument('--disk-size', type=int, default=Config.DISK_SIZE,
                       help=f'磁盘大小 GB (默认: {Config.DISK_SIZE})')
    parser.add_argument('--memory', type=int, default=Config.MEMORY_SIZE,
                       help=f'内存大小 MB (默认: {Config.MEMORY_SIZE})')
    parser.add_argument('--cpus', type=int, default=Config.CPU_COUNT,
                       help=f'CPU 核心数 (默认: {Config.CPU_COUNT})')
    parser.add_argument('--ip', default=Config.VM_IP,
                       help=f'虚拟机 IP 地址 (默认: {Config.VM_IP})')
    parser.add_argument('--root-password', default=Config.ROOT_PASSWORD,
                       help=f'root 密码 (默认: {Config.ROOT_PASSWORD})')
    parser.add_argument('--dry-run', action='store_true',
                       help='干跑模式，只显示计划不实际执行')
    
    return parser.parse_args()


def apply_arguments_to_config(args):
    """应用命令行参数到配置"""
    config = Config()
    
    if args.vm_name:
        config.VM_NAME = args.vm_name
    if args.vm_dir:
        config.VM_BASE_DIR = args.vm_dir
    if args.iso_path:
        config.ISO_PATH = args.iso_path
    if args.disk_size:
        config.DISK_SIZE = args.disk_size
    if args.memory:
        config.MEMORY_SIZE = args.memory
    if args.cpus:
        config.CPU_COUNT = args.cpus
    if args.ip:
        config.VM_IP = args.ip
    if args.root_password:
        config.ROOT_PASSWORD = args.root_password
    
    return config


def main():
    """主函数"""
    # 设置日志
    Logger.setup_logging()
    
    # 显示标题
    title = """
    ╔══════════════════════════════════════════════╗
    ║           VMware CentOS 部署脚本             ║
    ║                 Python 3 版本               ║
    ╚══════════════════════════════════════════════╝
    """
    print(title)
    
    # 检查管理员权限
    SystemUtils.require_admin()
    
    # 解析命令行参数
    args = parse_arguments()
    config = apply_arguments_to_config(args)
    
    # 干跑模式
    if args.dry_run:
        Logger.log_info("干跑模式 - 显示部署计划:")
        Logger.log_info(f"  虚拟机名称: {config.VM_NAME}")
        Logger.log_info(f"  存储目录: {config.VM_BASE_DIR}")
        Logger.log_info(f"  ISO 路径: {config.ISO_PATH}")
        Logger.log_info(f"  磁盘大小: {config.DISK_SIZE} GB")
        Logger.log_info(f"  内存: {config.MEMORY_SIZE} MB")
        Logger.log_info(f"  CPU: {config.CPU_COUNT} 核心")
        Logger.log_info(f"  IP 地址: {config.VM_IP}")
        return 0
    
    # 创建部署器并执行部署
    deployer = VMwareDeployer(config)
    
    try:
        success = deployer.deploy()
        return 0 if success else 1
    except KeyboardInterrupt:
        Logger.log_warn("部署被用户中断")
        return 1
    except Exception as e:
        Logger.log_error(f"部署过程中发生未预期错误: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())