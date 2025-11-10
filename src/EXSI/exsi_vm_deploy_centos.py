#!/usr/bin/env python3
"""
ESXi CentOS 7 虚拟机自动化部署脚本 (优化版)
功能：检查IP可用性、创建虚拟机、静默安装CentOS 7
作者：Python开发工程师
日期：2025-11-10
版本：1.1
"""

import ipaddress
import socket
import ssl
import subprocess  # 新增：用于执行ping命令
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests
import urllib3
from pyVim.connect import Disconnect, SmartConnect
from pyVmomi import vim

# 禁用SSL警告（仅用于测试环境）
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

class ESXiVMDeployer:
    def __init__(self, esxi_host, username, password):
        """
        初始化ESXi连接参数
        
        Args:
            esxi_host: ESXi主机IP地址
            username: ESXi用户名
            password: ESXi密码
        """
        self.esxi_host = '172.16.47.183'
        self.username = 'root'
        self.password = 'Secsmart#612'
        self.service_instance = None
        
        # 虚拟机配置参数
        self.config = {
            'iso_path': '/CentOS-7-x86_64-DVD-2009.iso',  # ISO文件路径
            'vm_name_prefix': 'c79',  # 虚拟机名前缀
            'usage': 'general',  # 虚拟机用途
            'cpus': 8,  # CPU核心数
            'memory_mb': 16384,  # 内存大小(MB)
            'disk_size_gb': 40,  # 磁盘大小(GB)
            'disk_type': 'thin',  # 磁盘类型：thin（精简置备）
            'username': 'admin',  # 系统用户名
            'password': 'Secsmart#612',  # 系统密码
            'root_password': 'Rede@612@Mixed',  # root密码
            'timezone': 'Asia/Shanghai',  # 时区
            'subnet': '172.16.47.0/24',  # IP子网
            'gateway': '172.16.47.1',  # 默认网关 (新增)
            'dns_servers': '8.8.8.8'  # DNS服务器 (新增)
        }

    def connect_esxi(self):
        """
        连接到ESXi主机
        """
        try:
            # 创建SSL上下文（跳过证书验证，仅用于测试环境）
            context = ssl.create_default_context()
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
            
            # 连接到ESXi
            self.service_instance = SmartConnect(
                host=self.esxi_host,
                user=self.username,
                pwd=self.password,
                sslContext=context
            )
            print(f"✅ 成功连接到ESXi主机: {self.esxi_host}")
            return True
            
        except Exception as e:
            print(f"❌ 连接ESXi主机失败: {str(e)}")
            return False

    def check_ip_availability(self, ip_address):
        """
        检查IP地址是否可用（结合ping和端口扫描）
        优化点：使用ping命令进行基础连通性检查，结果更可靠[7](@ref)。
        
        Args:
            ip_address: 要检查的IP地址
            
        Returns:
            bool: IP是否可用
        """
        ip_str = str(ip_address)
        
        # 方法1: 使用ping命令检查基础连通性 (适用于在线主机)
        try:
            # 发送1个ICMP包，超时1秒 (Linux/macOS: -c 1, Windows: -n 1)
            result = subprocess.run(
                ['ping', '-c', '1', '-W', '1', ip_str] if sys.platform != 'win32' else ['ping', '-n', '1', '-w', '1000', ip_str],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                print(f"   IP {ip_str} 响应ping，可能已被占用")
                return False
        except (subprocess.TimeoutExpired, FileNotFoundError):
            # ping命令超时或未找到是正常的，说明IP可能可用
            pass
        except Exception as e:
            print(f"   ⚠️ 检查IP {ip_str} ping时出现异常: {e}")
        
        # 方法2: 检查常见服务端口 (适用于禁ping但运行服务的主机)
        ports = [22, 80, 443, 3389, 21, 23, 53]  # 常见服务端口
        for port in ports:
            try:
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                    sock.settimeout(1)
                    result = sock.connect_ex((ip_str, port))
                    if result == 0:
                        print(f"   IP {ip_str} 端口 {port} 开放，可能已被占用")
                        return False
            except Exception:
                continue
                
        print(f"   ✅ IP {ip_str} 可用")
        return True

    def find_available_ips(self, count=5):
        """
        在子网中查找可用的IP地址
        
        Args:
            count: 需要查找的IP数量
            
        Returns:
            list: 可用的IP地址列表
        """
        print(f"🔍 在子网 {self.config['subnet']} 中查找可用IP地址...")
        
        available_ips = []
        network = ipaddress.IPv4Network(self.config['subnet'], strict=False)
        
        # 排除网络地址、广播地址和网关地址
        excluded_ips = {network.network_address, network.broadcast_address}
        if hasattr(self.config, 'gateway'):
            try:
                excluded_ips.add(ipaddress.IPv4Address(self.config['gateway']))
            except ipaddress.AddressValueError:
                pass
        
        # 尝试从子网中段开始检查（避免头尾常用地址）
        host_list = list(network.hosts())
        if not host_list:
            print("❌ 子网中无可用主机地址")
            return available_ips
            
        start_index = max(0, len(host_list) // 3)  # 从1/3处开始检查
        check_ips = host_list[start_index:start_index + 50]  # 检查50个IP
        
        # 使用多线程加速IP检查
        with ThreadPoolExecutor(max_workers=10) as executor:
            future_to_ip = {
                executor.submit(self.check_ip_availability, ip): ip 
                for ip in check_ips
                if ip not in excluded_ips
            }
            
            for future in as_completed(future_to_ip):
                ip = future_to_ip[future]
                try:
                    if future.result() and len(available_ips) < count:
                        available_ips.append(ip)
                        print(f"🎯 找到可用IP: {ip} ({len(available_ips)}/{count})")
                        
                    if len(available_ips) >= count:
                        executor.shutdown(wait=False, cancel_futures=True)
                        break
                except Exception as e:
                    print(f"⚠️ 检查IP {ip} 时出错: {e}")
        
        return available_ips[:count]

    def create_kickstart_config(self, ip_address):
        """
        创建CentOS 7的kickstart自动安装配置文件
        优化点：明确配置网关和DNS，确保网络可用性[7](@ref)。
        
        Args:
            ip_address: 虚拟机IP地址
            
        Returns:
            str: kickstart配置内容
        """
        ks_config = f"""
# CentOS 7 自动安装配置
# 系统语言
lang en_US.UTF-8
# 键盘布局
keyboard us
# 网络配置
network --bootproto=static --ip={ip_address} --netmask=255.255.255.0 --gateway={self.config['gateway']} --nameserver={self.config['dns_servers']} --hostname=c79_{ip_address}_{self.config['usage']}
# 根密码
rootpw --plaintext {self.config['root_password']}
# 系统认证
auth --enableshadow --passalgo=sha512
# 时区配置
timezone {self.config['timezone']} --utc
# 系统服务
services --disabled="firewalld,NetworkManager" --enabled="network,sshd"
# 安装源
url --url=http://mirror.centos.org/centos/7/os/x86_64/
# 系统引导配置
bootloader --location=mbr --boot-drive=sda
# 清除磁盘并初始化
clearpart --all --initlabel
# 磁盘分区
part /boot --fstype="ext4" --size=500
part swap --recommended
part / --fstype="ext4" --grow --size=1
# 最小化安装
%packages --nobase
@core
%end
# 用户创建
user --name={self.config['username']} --password={self.config['password']} --groups=wheel
# 后安装脚本
%post
# 配置sudo权限
echo "{self.config['username']} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/{self.config['username']}
chmod 440 /etc/sudoers.d/{self.config['username']}
# 配置SSH
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
# 创建授权密钥目录
mkdir -p /home/{self.config['username']}/.ssh
chmod 700 /home/{self.config['username']}/.ssh
chown {self.config['username']}:{self.config['username']} /home/{self.config['username']}/.ssh
# 设置主机名
echo "c79_{ip_address}_{self.config['usage']}" > /etc/hostname
# 启用服务
systemctl enable sshd
systemctl enable network
# 清理
yum clean all
%end
# 重启系统
reboot
"""
        return ks_config

    def create_virtual_machine(self, ip_address):
        """
        创建虚拟机
        主要修正点：设备控制器关联逻辑、ISO挂载方式[7](@ref)。
        
        Args:
            ip_address: 虚拟机IP地址
            
        Returns:
            bool: 创建是否成功
        """
        try:
            content = self.service_instance.RetrieveContent()
            datacenter = content.rootFolder.childEntity[0]
            vmfolder = datacenter.vmFolder
            host_folder = datacenter.hostFolder
            if not host_folder.childEntity:
                print("❌ 未找到可用的主机资源")
                return False
            resource_pool = host_folder.childEntity[0].resourcePool
            
            # 虚拟机名称
            vm_name = f"{self.config['vm_name_prefix']}_{ip_address}_{self.config['usage']}"
            print(f"  开始创建虚拟机: {vm_name}")
            
            # 虚拟机配置规范
            vm_config = vim.vm.ConfigSpec()
            vm_config.name = vm_name
            vm_config.numCPUs = self.config['cpus']
            vm_config.memoryMB = self.config['memory_mb']
            vm_config.guestId = 'centos7_64Guest'  # CentOS 7 64位
            vm_config.version = 'vmx-13'  # 虚拟机版本
            
            # 设备变更列表
            device_changes = []
            
            # 1. 添加SCSI控制器 (用于磁盘)
            scsi_controller = vim.vm.device.VirtualLsiLogicController()
            scsi_controller.key = 1000  # 为控制器分配一个唯一的key
            scsi_controller.busNumber = 0
            scsi_controller.sharedBus = vim.vm.device.VirtualSCSIController.Sharing.noSharing
            scsi_controller_spec = vim.vm.device.VirtualDeviceSpec()
            scsi_controller_spec.operation = vim.vm.device.VirtualDeviceSpec.Operation.add
            scsi_controller_spec.device = scsi_controller
            device_changes.append(scsi_controller_spec)
            
            # 2. 添加虚拟磁盘（精简置备）并关联到SCSI控制器
            disk_spec = vim.vm.device.VirtualDeviceSpec()
            disk_spec.operation = vim.vm.device.VirtualDeviceSpec.Operation.add
            disk_spec.fileOperation = vim.vm.device.VirtualDeviceSpec.FileOperation.create
            disk_spec.device = vim.vm.device.VirtualDisk()
            disk_spec.device.key = 2000  # 为磁盘分配一个唯一的key
            disk_spec.device.unitNumber = 0
            disk_spec.device.capacityInKB = self.config['disk_size_gb'] * 1024 * 1024
            disk_spec.device.controllerKey = scsi_controller.key  # 关联到SCSI控制器
            
            # 设置磁盘备份规范（精简置备）
            disk_spec.device.backing = vim.vm.device.VirtualDisk.FlatVer2BackingInfo()
            disk_spec.device.backing.diskMode = 'persistent'
            disk_spec.device.backing.thinProvisioned = True  # 精简置备
            disk_spec.device.backing.fileName = ''  # ESXi会自动生成文件名
            device_changes.append(disk_spec)
            
            # 3. 添加IDE控制器 (用于CD-ROM)
            ide_controller = vim.vm.device.VirtualIDEController()
            ide_controller.key = 3000  # 为控制器分配一个唯一的key
            ide_controller.busNumber = 0
            ide_controller_spec = vim.vm.device.VirtualDeviceSpec()
            ide_controller_spec.operation = vim.vm.device.VirtualDeviceSpec.Operation.add
            ide_controller_spec.device = ide_controller
            device_changes.append(ide_controller_spec)
            
            # 4. 添加CD/DVD驱动器用于ISO安装，并关联到IDE控制器
            cdrom_spec = vim.vm.device.VirtualDeviceSpec()
            cdrom_spec.operation = vim.vm.device.VirtualDeviceSpec.Operation.add
            cdrom_spec.device = vim.vm.device.VirtualCdrom()
            cdrom_spec.device.key = 4000  # 为CD-ROM分配一个唯一的key
            cdrom_spec.device.controllerKey = ide_controller.key  # 关联到IDE控制器
            cdrom_spec.device.unitNumber = 0
            
            # 配置CD-ROM backing 为ISO文件
            cdrom_backing = vim.vm.device.VirtualCdrom.IsoBackingInfo()
            cdrom_backing.fileName = self.config['iso_path']  # ISO文件路径
            
            cdrom_spec.device.backing = cdrom_backing
            cdrom_spec.device.connectable = vim.vm.device.VirtualDevice.ConnectInfo()
            cdrom_spec.device.connectable.startConnected = True
            cdrom_spec.device.connectable.allowGuestControl = False  # 客户机不能断开
            device_changes.append(cdrom_spec)
            
            # 5. 添加网络适配器
            network_adapter = vim.vm.device.VirtualE1000()
            network_adapter.key = 5000  # 为网络适配器分配一个唯一的key
            network_adapter.addressType = 'generated'
            
            # 查找并设置网络（这里使用第一个找到的网络，请根据实际情况调整）
            network = None
            for child in datacenter.network:
                if hasattr(child, 'name') and child.name == 'VM Network':
                    network = child
                    break
            if network is None and datacenter.network:
                network = datacenter.network[0]
                
            network_adapter.backing = vim.vm.device.VirtualE1000.NetworkBackingInfo()
            network_adapter.backing.deviceName = getattr(network, 'name', 'VM Network') if network else 'VM Network'
            network_adapter.backing.network = network
            network_adapter.backing.useAutoDetect = False if network else True
            
            network_adapter.wakeOnLanEnabled = True
            network_adapter.connectable = vim.vm.device.VirtualDevice.ConnectInfo()
            network_adapter.connectable.startConnected = True
            network_adapter.connectable.allowGuestControl = True
            
            network_adapter_spec = vim.vm.device.VirtualDeviceSpec()
            network_adapter_spec.operation = vim.vm.device.VirtualDeviceSpec.Operation.add
            network_adapter_spec.device = network_adapter
            device_changes.append(network_adapter_spec)
            
            # 将所有设备变更添加到虚拟机配置
            vm_config.deviceChange = device_changes
            
            # 设置启动选项（从CD-ROM启动）
            vm_config.bootOptions = vim.vm.BootOptions()
            vm_config.bootOptions.bootOrder = [
                vim.vm.BootOptions.BootableCdromDevice(),
                vim.vm.BootOptions.BootableDiskDevice()
            ]
            
            # 创建虚拟机
            print(f"    正在创建虚拟机配置...")
            task = vmfolder.CreateVM_Task(config=vm_config, pool=resource_pool)
            print(f"    已提交创建任务，等待完成...")
            self.wait_for_task(task)
            
            if task.info.state == 'success':
                print(f"    ✅ 虚拟机 {vm_name} 创建成功")
                
                # 获取创建的虚拟机对象
                vm = task.info.result
                
                # 配置虚拟机额外设置（注解）
                self.configure_vm_extra_settings(vm, vm_name)
                
                # 确保CD-ROM已连接（重新配置一次以确保ISO挂载）
                self.ensure_cdrom_connected(vm)
                
                return True
            else:
                print(f"    ❌ 虚拟机创建失败: {task.info.error}")
                return False
                
        except Exception as e:
            print(f"    ❌ 创建虚拟机时出错: {str(e)}")
            import traceback
            traceback.print_exc()
            return False

    def ensure_cdrom_connected(self, vm):
        """
        确保虚拟机的CD-ROM已连接并配置了ISO
        """
        try:
            # 查找CD-ROM设备
            cdrom = None
            for device in vm.config.hardware.device:
                if isinstance(device, vim.vm.device.VirtualCdrom):
                    cdrom = device
                    break
            
            if cdrom:
                # 创建CD-ROM备份规范
                backing = vim.vm.device.VirtualCdrom.IsoBackingInfo()
                backing.fileName = self.config['iso_path']
                
                # 创建设备连接信息
                connectable = vim.vm.device.VirtualDevice.ConnectInfo()
                connectable.startConnected = True
                connectable.allowGuestControl = False
                
                # 创建设备规格
                dev_spec = vim.vm.device.VirtualDeviceSpec()
                dev_spec.operation = vim.vm.device.VirtualDeviceSpec.Operation.edit
                dev_spec.device = cdrom
                dev_spec.device.backing = backing
                dev_spec.device.connectable = connectable
                
                # 应用配置
                vm_spec = vim.vm.ConfigSpec()
                vm_spec.deviceChange = [dev_spec]
                
                task = vm.ReconfigVM_Task(vm_spec)
                self.wait_for_task(task)
                if task.info.state == 'success':
                    print("    ✅ CD-ROM ISO挂载确认完成")
                else:
                    print("    ⚠️ CD-ROM配置可能未完全生效")
        except Exception as e:
            print(f"    ⚠️ 配置CD-ROM时出错: {e}")

    def configure_vm_extra_settings(self, vm, vm_name):
        """
        配置虚拟机的额外设置
        
        Args:
            vm: 虚拟机对象
            vm_name: 虚拟机名称
        """
        try:
            # 配置虚拟机注解（包含安装信息）
            spec = vim.vm.ConfigSpec()
            spec.annotation = f"""虚拟机自动部署信息：
名称: {vm_name}
创建时间: {time.strftime('%Y-%m-%d %H:%M:%S')}
IP地址: {vm_name.split('_')[1]}
用途: {self.config['usage']}
系统: CentOS 7 最小化安装
用户: {self.config['username']}
备注: 通过自动化脚本部署"""
            
            task = vm.ReconfigVM_Task(spec=spec)
            self.wait_for_task(task)
            print(f"    📝 虚拟机注解配置完成")
            
        except Exception as e:
            print(f"    ⚠️ 配置虚拟机额外设置时出错: {e}")

    def wait_for_task(self, task):
        """
        等待任务完成
        优化点：添加超时机制和状态轮询[7](@ref)。
        
        Args:
            task: 要等待的任务对象
        """
        timeout = 300  # 5分钟超时
        start_time = time.time()
        
        while task.info.state not in [vim.TaskInfo.State.success, vim.TaskInfo.State.error]:
            if time.time() - start_time > timeout:
                print("    ⚠️ 任务等待超时")
                break
            time.sleep(5)  # 每5秒检查一次

    def deploy_vms(self, vm_count=1):
        """
        主部署方法
        
        Args:
            vm_count: 要部署的虚拟机数量
        """
        print("🚀 开始ESXi虚拟机自动化部署...")
        
        # 1. 连接ESXi
        if not self.connect_esxi():
            sys.exit(1)
        
        # 2. 查找可用IP
        available_ips = self.find_available_ips(vm_count)
        if not available_ips:
            print("❌ 未找到可用的IP地址")
            # 断开连接后再退出
            if self.service_instance:
                Disconnect(self.service_instance)
            sys.exit(1)
        
        print(f"📋 找到可用IP列表: {[str(ip) for ip in available_ips]}")
        
        # 3. 创建虚拟机
        successful_deployments = []
        
        for i, ip in enumerate(available_ips, 1):
            print(f"\n📦 正在部署第 {i}/{len(available_ips)} 个虚拟机 (IP: {ip})")
            
            try:
                # 生成kickstart配置
                ks_config = self.create_kickstart_config(ip)
                print(f"    生成kickstart配置完成")
                
                # 创建虚拟机
                if self.create_virtual_machine(ip):
                    successful_deployments.append(ip)
                    print(f"    ✅ 虚拟机部署完成: c79_{ip}_{self.config['usage']}")
                else:
                    print(f"    ❌ 虚拟机部署失败: {ip}")
                
                # 添加延迟，避免同时创建过多虚拟机给ESXi带来压力
                if i < len(available_ips):  # 最后一个不需要延迟
                    print("    ⏳ 等待5秒后继续...")
                    time.sleep(5)
                    
            except Exception as e:
                print(f"    ❌ 部署虚拟机 {ip} 时发生异常: {e}")
                import traceback
                traceback.print_exc()
                continue
        
        # 4. 输出部署结果
        print(f"\n{'🎉 部署完成！' if successful_deployments else '❌ 部署结果'}")
        print(f"   成功部署: {len(successful_deployments)} 个虚拟机")
        if successful_deployments:
            print(f"   IP列表: {[str(ip) for ip in successful_deployments]}")
        
        # 5. 断开连接
        Disconnect(self.service_instance)
        print("🔌 已断开ESXi连接")

def main():
    """
    主函数 - 配置和启动部署流程
    """
    # ESXi连接配置（请根据实际情况修改）
    ESXI_HOST = "192.168.1.100"  # ESXi主机IP
    ESXI_USERNAME = "root"       # ESXi用户名
    ESXI_PASSWORD = "your_password"  # ESXi密码
    
    # 创建部署器实例
    deployer = ESXiVMDeployer(ESXI_HOST, ESXI_USERNAME, ESXI_PASSWORD)
    
    # 配置参数（可选修改）
    deployer.config.update({
        'usage': 'web-server',  # 修改虚拟机用途
        'subnet': '172.16.47.0/24',  # 修改子网
        'gateway': '172.16.47.1',  # 网关
        'dns_servers': '8.8.8.8'  # DNS服务器
    })
    
    try:
        # 部署虚拟机（数量可调整）
        deployer.deploy_vms(vm_count=1)
        
    except KeyboardInterrupt:
        print("\n⚠️ 用户中断部署过程")
        # 确保断开连接
        if deployer.service_instance:
            Disconnect(deployer.service_instance)
    except Exception as e:
        print(f"❌ 部署过程中发生错误: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()