
# 安装依赖

sudo yum install -y epel-release stress-ng sysstat gnuplot coreutils

sudo yum install -y libcgroup-tools epel-release stress-ng sysstat


# 执行测试（默认5分钟，4倍核心数）
chmod +x cpu_stress_test.sh
./cpu_stress_test.sh

# 自定义测试（10分钟，6倍核心数）
./cpu_stress_test.sh 10 6

# 查看报告
less cpu_stress_report_*.csv