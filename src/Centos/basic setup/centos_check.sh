#!/bin/bash
# 查看是否有cdrom 设备
ls /dev/ | grep sr

ll /etc/yum.repos.d

yum install -y iperf3 vim htop

docker version

iperf3 -c 172.16.48.191 -t 60 -P 4