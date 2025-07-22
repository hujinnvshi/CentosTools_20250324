# #!/bin/bash

# =====================================================
# FIO 磁盘性能测试脚本
# 版本: 1.2
# 功能: 创建测试数据 -> 执行性能测试 -> 生成报告 -> 清理数据
# =====================================================

# 配置参数
TEST_PATH="/data/fdisk"           # 测试路径
TEST_FILE="${TEST_PATH}/fio_test" # 测试文件名
SIZE="5G"                         # 测试文件大小
RUNTIME=60                        # 每个测试运行时间(秒)
OUTPUT_FILE="${TEST_PATH}/fio_report_$(date +%Y%m%d_%H%M%S).txt" # 报告文件

# 检查依赖
check_dependencies() {
    if ! command -v fio &> /dev/null; then
        echo "错误: fio 未安装，请先安装 fio"
        echo "安装命令: sudo yum install fio -y"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo "警告: jq 未安装，部分报告功能受限"
        echo "建议安装: sudo yum install jq -y"
    fi
}

# 创建测试目录和文件
prepare_test() {
    echo "=== 准备测试环境 ==="
    echo "测试路径: ${TEST_PATH}"
    echo "测试文件: ${TEST_FILE}"
    echo "文件大小: ${SIZE}"
    
    # 创建测试目录
    sudo mkdir -p "${TEST_PATH}"
    sudo chmod 777 "${TEST_PATH}"
    
    # 创建测试文件
    echo "创建测试文件..."
    fio --name=prepare --filename="${TEST_FILE}" --size="${SIZE}" \
        --rw=write --bs=1M --ioengine=libaio --iodepth=64 \
        --direct=1 --numjobs=1 --runtime=30 --group_reporting \
        > /dev/null 2>&1
    
    # 清除缓存
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
    
    echo "测试环境准备完成"
    echo "=========================================="
}

# 运行性能测试
run_performance_test() {
    local test_name=$1
    local rw=$2
    local bs=$3
    local iodepth=$4
    local numjobs=$5
    local mixread=${6:-50}  # 默认50%读
    
    echo "运行测试: ${test_name}..."
    
    # 准备JSON输出文件名
    local json_output="${TEST_PATH}/fio_${test_name}_$(date +%s).json"
    
    # 运行测试
    fio --name="${test_name}" --filename="${TEST_FILE}" \
        --rw="${rw}" --bs="${bs}" --ioengine=libaio --iodepth="${iodepth}" \
        --direct=1 --numjobs="${numjobs}" --runtime="${RUNTIME}" \
        --group_reporting --output-format=json --output="${json_output}" \
        ${rwmixread:+--rwmixread=$mixread}
    
    # 解析结果
    parse_results "${json_output}" "${test_name}"
    
    # 清理临时JSON文件
    rm -f "${json_output}"
}

# 解析测试结果
parse_results() {
    local json_file=$1
    local test_name=$2
    
    if ! command -v jq &> /dev/null; then
        echo "警告: jq 未安装，跳过详细结果解析"
        return
    fi
    
    # 提取关键指标
    local iops_read=$(jq '.jobs[0].read.iops' "${json_file}")
    local iops_write=$(jq '.jobs[0].write.iops' "${json_file}")
    local bw_read=$(jq '.jobs[0].read.bw' "${json_file}")
    local bw_write=$(jq '.jobs[0].write.bw' "${json_file}")
    local lat_read=$(jq '.jobs[0].read.lat_ns.mean' "${json_file}")
    local lat_write=$(jq '.jobs[0].write.lat_ns.mean' "${json_file}")
    local lat_read_p95=$(jq '.jobs[0].read.lat_ns.percentile."95.000000"' "${json_file}")
    local lat_write_p95=$(jq '.jobs[0].write.lat_ns.percentile."95.000000"' "${json_file}")
    
    # 转换单位
    bw_read_mb=$(echo "scale=2; ${bw_read} / 1024" | bc)
    bw_write_mb=$(echo "scale=2; ${bw_write} / 1024" | bc)
    lat_read_ms=$(echo "scale=3; ${lat_read} / 1000000" | bc)
    lat_write_ms=$(echo "scale=3; ${lat_write} / 1000000" | bc)
    lat_read_p95_ms=$(echo "scale=3; ${lat_read_p95} / 1000000" | bc)
    lat_write_p95_ms=$(echo "scale=3; ${lat_write_p95} / 1000000" | bc)
    
    # 保存到报告
    echo "===== ${test_name} =====" | tee -a "${OUTPUT_FILE}"
    echo "读取性能:" | tee -a "${OUTPUT_FILE}"
    echo "  IOPS: ${iops_read}" | tee -a "${OUTPUT_FILE}"
    echo "  带宽: ${bw_read_mb} MB/s" | tee -a "${OUTPUT_FILE}"
    echo "  平均延迟: ${lat_read_ms} ms" | tee -a "${OUTPUT_FILE}"
    echo "  95%延迟: ${lat_read_p95_ms} ms" | tee -a "${OUTPUT_FILE}"
    
    if [ "${iops_write}" != "null" ]; then
        echo "写入性能:" | tee -a "${OUTPUT_FILE}"
        echo "  IOPS: ${iops_write}" | tee -a "${OUTPUT_FILE}"
        echo "  带宽: ${bw_write_mb} MB/s" | tee -a "${OUTPUT_FILE}"
        echo "  平均延迟: ${lat_write_ms} ms" | tee -a "${OUTPUT_FILE}"
        echo "  95%延迟: ${lat_write_p95_ms} ms" | tee -a "${OUTPUT_FILE}"
    fi
    
    echo "------------------------------------------" | tee -a "${OUTPUT_FILE}"
}

# 生成最终报告
generate_report() {
    echo "=== 测试报告 ===" | tee "${OUTPUT_FILE}"
    echo "测试时间: $(date)" | tee -a "${OUTPUT_FILE}"
    echo "测试路径: ${TEST_PATH}" | tee -a "${OUTPUT_FILE}"
    echo "测试文件: ${TEST_FILE}" | tee -a "${OUTPUT_FILE}"
    echo "文件大小: ${SIZE}" | tee -a "${OUTPUT_FILE}"
    echo "测试时长: ${RUNTIME} 秒/项" | tee -a "${OUTPUT_FILE}"
    echo "==========================================" | tee -a "${OUTPUT_FILE}"
}

# 清理测试数据
cleanup() {
    echo "=== 清理测试环境 ==="
    echo "删除测试文件: ${TEST_FILE}"
    rm -f "${TEST_FILE}"
    echo "测试环境清理完成"
}

# 主函数
main() {
    # 检查依赖
    check_dependencies
    
    # 创建报告文件
    generate_report
    
    # 准备测试环境
    prepare_test
    
    # 执行性能测试
    echo "=== 开始性能测试 ==="
    
    # 顺序读写测试
    run_performance_test "Seq_Read_1M_QD8" "read" "1M" "8" "1"
    run_performance_test "Seq_Write_1M_QD8" "write" "1M" "8" "1"
    
    # 随机读写测试
    run_performance_test "Rand_Read_4K_QD32" "randread" "4k" "32" "4"
    run_performance_test "Rand_Write_4K_QD32" "randwrite" "4k" "32" "4"
    
    # 混合读写测试
    run_performance_test "Mixed_RW_4K_QD32" "randrw" "4k" "32" "4" "70"
    
    # 高队列深度测试
    run_performance_test "Rand_Read_4K_QD128" "randread" "4k" "128" "8"
    
    echo "=== 性能测试完成 ==="
    echo "=========================================="
    
    # 清理测试环境
    cleanup
    
    # 显示报告位置
    echo "测试报告已保存至: ${OUTPUT_FILE}"
}

# 执行主函数
main