#!/bin/bash

iostat -x -c -d 5 -m | awk '
BEGIN {
    print "开始监控系统IO状态，每5秒刷新一次...\n";
    # CPU指标翻译对照
    cpu_fields["%user"] = "用户进程";
    cpu_fields["%nice"] = "优先级调整";
    cpu_fields["%system"] = "系统进程";
    cpu_fields["%iowait"] = "IO等待";
    cpu_fields["%steal"] = "虚拟占用";
    cpu_fields["%idle"] = "空闲";
    
    # 设备指标翻译对照
    dev_fields["rrqm/s"] = "读合并数/s";
    dev_fields["wrqm/s"] = "写合并数/s";
    dev_fields["r/s"] = "读请求/s";
    dev_fields["w/s"] = "写请求/s";
    dev_fields["rMB/s"] = "读取(MB/s)";
    dev_fields["wMB/s"] = "写入(MB/s)";
    dev_fields["avgrq-sz"] = "平均请求大小";
    dev_fields["avgqu-sz"] = "平均队列长度";
    dev_fields["await"] = "平均响应(ms)";
    dev_fields["r_await"] = "读响应(ms)";
    dev_fields["w_await"] = "写响应(ms)";
    dev_fields["svctm"] = "服务时间(ms)";
    dev_fields["%util"] = "设备利用率";
}

# CPU统计行处理
/^avg-cpu:/ {
    # 打印中文标题
    printf "CPU统计:   "
    # 翻译每个指标
    for (i=2; i<=NF; i++) {
        if ($i in cpu_fields) {
            printf "%-10s", cpu_fields[$i]
        }
    }
    printf "\n"
    next
}

# 设备标题行处理
/^Device:/ {
    # 打印设备头
    printf "%-12s", "设备:"
    # 翻译每个指标
    for (i=2; i<=NF; i++) {
        if ($i in dev_fields) {
            printf "%-10s", dev_fields[$i]
        }
    }
    printf "\n"
    next
}

# 数据行处理 (CPU统计)
/^\s+[0-9]+\.[0-9]+\s+[0-9]+\.[0-9]+\s+[0-9]+\.[0-9]+\s+[0-9]+\.[0-9]+\s+[0-9]+\.[0-9]+\s+[0-9]+\.[0-9]+$/ {
    printf "%-14s", " "
    for (i=1; i<=NF; i++) {
        printf "%-10.2f", $i
    }
    printf "\n"
    next
}

# 数据行处理 (设备统计)
!/^Linux/ && !/^$/ {
    printf "%-12s", $1
    for (i=2; i<=NF; i++) {
        # 调整MB/s数据格式
        if (($(i-1) ~ /rMB\/s|wMB\/s/ || $i ~ /[0-9]+\.[0-9]+/) && $i ~ /\.[0-9]+/) {
            printf "%-10.2f", $i
        } else {
            printf "%-10s", $i
        }
    }
    printf "\n"
}

# 系统信息行处理
/^Linux/ {
    print "系统信息:", $0
    printf "%60s\n", "================================"
}
'