#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
文件分块处理程序：针对tar文件实现随机大小分块（30-100MB），严格遵循命名/存储规范，保障完整性
"""
import os
import sys
import random
import hashlib
import argparse
import logging
import shutil
from typing import Optional

# ===================== 全局配置 =====================
# 分块大小范围（字节）：30MB ~ 100MB
MIN_CHUNK_SIZE = 30 * 1024 * 1024  # 31457280 字节
MAX_CHUNK_SIZE = 100 * 1024 * 1024  # 104857600 字节
# 目标存储目录
TARGET_DIR = "/data/dmp/"
# 日志配置
LOG_FILE = os.path.join(TARGET_DIR, "file_chunker.log")
LOG_FORMAT = "%(asctime)s - %(levelname)s - %(module)s:%(lineno)d - %(message)s"

# ===================== 日志初始化 =====================
def init_logger() -> logging.Logger:
    """初始化日志系统：同时输出到控制台和文件"""
    logger = logging.getLogger("FileChunker")
    logger.setLevel(logging.INFO)
    
    # 避免重复添加处理器
    if logger.handlers:
        return logger
    
    # 控制台处理器
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(logging.Formatter(LOG_FORMAT))
    
    # 文件处理器（确保日志目录可写）
    os.makedirs(TARGET_DIR, exist_ok=True)
    file_handler = logging.FileHandler(LOG_FILE, encoding="utf-8")
    file_handler.setFormatter(logging.Formatter(LOG_FORMAT))
    
    logger.addHandler(console_handler)
    logger.addHandler(file_handler)
    return logger

logger = init_logger()

# ===================== 工具函数 =====================
def check_target_directory(required_space: int) -> None:
    """
    检查目标目录：存在性、写入权限、可用空间
    :param required_space: 原始文件大小（字节），确保可用空间充足
    """
    # 1. 创建目录（若不存在）
    try:
        os.makedirs(TARGET_DIR, mode=0o755, exist_ok=True)
        logger.info(f"目标目录检查完成：{TARGET_DIR}（已确保存在）")
    except OSError as e:
        logger.error(f"创建目标目录失败：{e}", exc_info=True)
        raise
    
    # 2. 检查写入权限（创建临时文件验证）
    test_file = os.path.join(TARGET_DIR, ".write_test.tmp")
    try:
        with open(test_file, "wb") as f:
            f.write(b"test")
        os.remove(test_file)
        logger.info("目标目录写入权限检查通过")
    except PermissionError:
        logger.error(f"目标目录无写入权限：{TARGET_DIR}", exc_info=True)
        raise
    except OSError as e:
        logger.error(f"写入权限检查失败：{e}", exc_info=True)
        raise
    
    # 3. 检查可用空间
    try:
        disk_usage = shutil.disk_usage(TARGET_DIR)
        available_space = disk_usage.free
        if available_space < required_space:
            raise OSError(
                f"目标目录可用空间不足！需{required_space/1024/1024:.2f}MB，仅剩余{available_space/1024/1024:.2f}MB"
            )
        logger.info(
            f"磁盘空间检查通过：可用{available_space/1024/1024:.2f}MB，需求{required_space/1024/1024:.2f}MB"
        )
    except OSError as e:
        logger.error(f"磁盘空间检查失败：{e}", exc_info=True)
        raise

def generate_random_chunk_size(seed: Optional[int] = None) -> int:
    """
    生成30-100MB范围内的随机分块大小（字节），支持种子复现
    :param seed: 随机种子（None则使用文件路径哈希值）
    :return: 随机分块大小（字节）
    """
    if seed is not None:
        random.seed(seed)
        logger.info(f"随机种子已设置：{seed}（确保分块大小可复现）")
    
    chunk_size = random.randint(MIN_CHUNK_SIZE, MAX_CHUNK_SIZE)
    logger.debug(f"生成随机分块大小：{chunk_size} 字节（{chunk_size/1024/1024:.2f}MB）")
    return chunk_size

def calculate_md5(data: bytes) -> str:
    """
    计算字节数据的MD5值（32位小写）
    :param data: 分块字节数据
    :return: 32位小写MD5哈希值
    """
    md5_obj = hashlib.md5()
    md5_obj.update(data)
    return md5_obj.hexdigest()

def get_file_size(file_path: str) -> int:
    """获取文件大小（字节）"""
    try:
        return os.path.getsize(file_path)
    except FileNotFoundError:
        logger.error(f"文件不存在：{file_path}", exc_info=True)
        raise
    except OSError as e:
        logger.error(f"获取文件大小失败：{e}", exc_info=True)
        raise

# ===================== 核心分块函数 =====================
def chunk_tar_file(input_file: str, seed: Optional[int] = None) -> None:
    """
    核心分块逻辑：流式读取tar文件，按随机大小分块，生成指定命名规则的文件
    :param input_file: 输入tar文件路径
    :param seed: 随机种子（确保分块大小可复现）
    """
    # 1. 基础检查
    if not os.path.isfile(input_file):
        raise FileNotFoundError(f"输入文件不存在：{input_file}")
    
    # 2. 获取原始文件信息
    original_file_size = get_file_size(input_file)
    logger.info(f"开始处理文件：{input_file}，总大小：{original_file_size/1024/1024:.2f}MB")
    
    # 3. 检查目标目录
    check_target_directory(original_file_size)
    
    # 4. 初始化分块参数
    block_number = 1
    total_written = 0  # 已写入的总字节数
    chunk_sizes = []   # 记录每个块的大小，用于最终验证
    
    # 5. 流式读取并分块
    with open(input_file, "rb") as f_in:
        while True:
            # 生成随机分块大小（最后一块用剩余字节）
            remaining = original_file_size - total_written
            if remaining <= 0:
                break
            
            # 最后一块若不足30MB，直接使用剩余字节
            if remaining < MIN_CHUNK_SIZE:
                chunk_size = remaining
                logger.info(f"最后一块，使用剩余字节：{chunk_size/1024/1024:.2f}MB")
            else:
                chunk_size = generate_random_chunk_size(seed)
                # 防止最后一次读取超过剩余字节
                chunk_size = min(chunk_size, remaining)
            
            # 读取分块数据（流式，避免内存占用）
            chunk_data = f_in.read(chunk_size)
            if not chunk_data:
                break
            
            # 计算MD5
            md5_value = calculate_md5(chunk_data)
            logger.debug(f"块{block_number} MD5计算完成：{md5_value}")
            
            # 生成文件名（严格遵循规则）
            file_name = f"oracle_expdp_{block_number}_{md5_value}.dmp"
            file_path = os.path.join(TARGET_DIR, file_name)
            
            # 写入分块文件
            try:
                with open(file_path, "wb") as f_out:
                    f_out.write(chunk_data)
                # 验证写入大小
                written_size = get_file_size(file_path)
                if written_size != len(chunk_data):
                    raise OSError(f"块{block_number}写入不完整：预期{len(chunk_data)}字节，实际{written_size}字节")
                
                # 记录信息
                chunk_sizes.append(written_size)
                total_written += written_size
                logger.info(
                    f"块{block_number}处理完成 | "
                    f"大小：{written_size/1024/1024:.2f}MB | "
                    f"MD5：{md5_value} | "
                    f"路径：{file_path}"
                )
                
                # 块编号递增
                block_number += 1
                
            except OSError as e:
                logger.error(f"块{block_number}写入失败：{e}", exc_info=True)
                # 清理失败的文件
                if os.path.exists(file_path):
                    os.remove(file_path)
                raise
        
    # 6. 最终验证
    logger.info(f"分块完成！共生成{block_number-1}个块")
    logger.info(f"原始文件大小：{original_file_size}字节，已写入总大小：{total_written}字节")
    
    if total_written != original_file_size:
        raise OSError(f"分块总大小与原文件不一致！原文件{original_file_size}字节，分块{total_written}字节")
    else:
        logger.info("✅ 分块完整性验证通过：总大小与原文件一致")
    
    # 输出每个块的大小统计
    logger.info("分块大小明细：")
    for i, size in enumerate(chunk_sizes, 1):
        logger.info(f"  块{i}：{size/1024/1024:.2f}MB")

# ===================== 命令行接口 & 主函数 =====================
def parse_args() -> argparse.Namespace:
    """解析命令行参数"""
    parser = argparse.ArgumentParser(description="Tar文件分块处理程序（30-100MB随机分块）")
    parser.add_argument(
        "-i", "--input", 
        required=True, 
        help="输入tar文件的完整路径（必填）"
    )
    parser.add_argument(
        "-s", "--seed", 
        type=int, 
        default=None, 
        help="随机种子（可选，用于复现分块大小）"
    )
    return parser.parse_args()

def main() -> None:
    """程序主入口"""
    try:
        # 解析参数
        args = parse_args()
        
        # 执行分块
        chunk_tar_file(args.input, args.seed)
        
        logger.info("🎉 所有分块处理完成！")
    except Exception as e:
        logger.error(f"程序执行失败：{e}", exc_info=True)
        sys.exit(1)

if __name__ == "__main__":
    main()