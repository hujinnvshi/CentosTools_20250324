# 删除 GPT 分区表
# sudo parted /dev/sdb mklabel gpt
# 删除 MBR 分区表
# sudo parted /dev/sdb mklabel msdos
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import subprocess
import sys

# 分区配置
PARTITIONS = [
    {"mount_point": "/data/log1", "size": "120", "label": "log_data"},
    {"mount_point": "/data/1", "size": "40", "label": "app_data"},
    {"mount_point": "/docker", "size": "20", "label": "docker_data"}
]

DISK = "/dev/sdb"
FS_TYPE = "xfs"  # CentOS 7默认文件系统

def run_command(cmd, description):
    """执行系统命令并检查结果"""
    print(f"🚀 执行: {description}")
    print(f"  命令: {' '.join(cmd)}")
    try:
        subprocess.run(cmd, check=True)
        print("✅ 操作成功")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ 操作失败: {e}")
        return False

def check_root():
    """检查是否以root用户运行"""
    if os.geteuid() != 0:
        print("❌ 请使用root用户运行此脚本")
        sys.exit(1)

def create_partitions():
    """创建分区"""
    print(f"\n🔧 开始分区磁盘 {DISK}")
    
    # 创建GPT分区表
    if not run_command(["parted", "-s", DISK, "mklabel", "gpt"], "创建GPT分区表"):
        sys.exit(1)
    
    # 创建分区
    start = "0%"
    for i, part in enumerate(PARTITIONS, start=1):
        size_gb = part["size"]
        
        # 计算结束位置
        if i == 1:
            # 第一个分区从0%开始
            end = f"{size_gb}GB"
        else:
            # 后续分区从上一个分区的结束位置开始
            prev_size = int(PARTITIONS[i-2]["size"])
            cumulative_size = sum(int(p["size"]) for p in PARTITIONS[:i-1])
            end = f"{cumulative_size + int(size_gb)}GB"
        
        if not run_command([
            "parted", "-s", "-a", "optimal", DISK,
            "mkpart", "primary", start, end
        ], f"创建分区 {i}: {size_gb}GB ({part['mount_point']})"):
            sys.exit(1)
        
        # 设置分区标签
        partition = f"{DISK}{i}"
        if not run_command(["parted", "-s", DISK, "name", str(i), part['label']], 
                          f"设置分区标签: {partition} -> {part['label']}"):
            sys.exit(1)
        
        # 更新下一个分区的起始位置
        start = end
    
    # 刷新分区表
    subprocess.run(["partprobe", DISK], check=True)
    print("✅ 分区创建完成")

def format_partitions():
    """格式化分区"""
    print("\n💾 格式化分区")
    for i, part in enumerate(PARTITIONS, start=1):
        partition = f"{DISK}{i}"
        if not run_command(["mkfs.xfs", "-L", part['label'], partition], 
                          f"格式化 {partition} 为 XFS"):
            sys.exit(1)
    print("✅ 格式化完成")

def create_mount_points():
    """创建挂载点目录"""
    print("\n📂 创建挂载目录")
    for part in PARTITIONS:
        mount_point = part["mount_point"]
        if not os.path.exists(mount_point):
            os.makedirs(mount_point, exist_ok=True)
            print(f"✅ 创建目录: {mount_point}")
        else:
            print(f"⚠️ 目录已存在: {mount_point}")

def mount_partitions():
    """挂载分区并配置自动挂载"""
    print("\n🔗 挂载分区")
    for i, part in enumerate(PARTITIONS, start=1):
        partition = f"{DISK}{i}"
        mount_point = part["mount_point"]
        
        # 临时挂载
        if not run_command(["mount", partition, mount_point], 
                          f"挂载 {partition} 到 {mount_point}"):
            sys.exit(1)
        
        # 获取UUID
        uuid = get_uuid(partition)
        if not uuid:
            print(f"❌ 无法获取 {partition} 的UUID")
            sys.exit(1)
        
        # 配置自动挂载
        fstab_entry = f"UUID={uuid} {mount_point} {FS_TYPE} defaults 0 0"
        
        # 检查是否已存在相同挂载点的条目
        if not fstab_entry_exists(mount_point):
            try:
                with open("/etc/fstab", "a") as f:
                    f.write(fstab_entry + "\n")
                print(f"✅ 添加自动挂载配置: {fstab_entry}")
            except IOError as e:
                print(f"❌ 写入/etc/fstab失败: {e}")
                sys.exit(1)
        else:
            print(f"⚠️ 跳过，/etc/fstab中已存在 {mount_point} 的挂载配置")

def get_uuid(partition):
    """获取分区的UUID"""
    try:
        result = subprocess.check_output(
            ["blkid", "-s", "UUID", "-o", "value", partition],
            universal_newlines=True
        )
        return result.strip()
    except subprocess.CalledProcessError:
        return None

def fstab_entry_exists(mount_point):
    """检查/etc/fstab中是否已存在相同挂载点的条目"""
    try:
        with open("/etc/fstab", "r") as f:
            for line in f:
                if line.strip().startswith("#"):
                    continue
                parts = line.split()
                if len(parts) >= 2 and parts[1] == mount_point:
                    return True
    except IOError:
        return False

def verify_mounts():
    """验证挂载结果"""
    print("\n🔍 验证挂载结果")
    run_command(["mount", "-a"], "挂载所有文件系统")
    run_command(["df", "-h"], "显示磁盘使用情况")
    
    # 检查所有挂载点
    all_mounted = True
    for part in PARTITIONS:
        if not os.path.ismount(part["mount_point"]):
            print(f"❌ 挂载失败: {part['mount_point']}")
            all_mounted = False
    
    if all_mounted:
        print("✅ 所有分区已成功挂载")
    else:
        print("❌ 部分分区挂载失败，请检查")
        sys.exit(1)

def main():
    print("="*60)
    print(f"📀 磁盘分区与挂载脚本")
    print(f"💽 目标磁盘: {DISK}")
    print(f"📂 挂载配置:")
    for part in PARTITIONS:
        print(f"  - {part['mount_point']}: {part['size']}GB ({part['label']})")
    print("="*60)
    
    # 执行检查
    check_root()
    
    # 确认操作
    confirm = input("\n⚠️ 此操作将清除磁盘所有数据并创建新分区，是否继续? (y/N): ")
    if confirm.lower() != 'y':
        print("操作已取消")
        sys.exit(0)
    
    # 执行分区和挂载流程
    create_partitions()
    format_partitions()
    create_mount_points()
    mount_partitions()
    verify_mounts()
    
    print("\n🎉 所有操作已完成! 建议重启系统验证自动挂载")
    print("="*60)

if __name__ == "__main__":
    main()