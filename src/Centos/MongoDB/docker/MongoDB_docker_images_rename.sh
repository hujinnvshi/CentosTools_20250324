#!/bin/bash

# Docker 镜像标准化脚本
# 功能：将私有仓库镜像重命名为标准格式 mongo:version

# 定义镜像列表
images=(
    "192.168.20.233:9002/mongo:6.0.4"
    "192.168.245.10:8092/mongo:4.4"
    "192.168.245.10:8092/mongo:6.0.4"
    "mongo:5.0.9"
    "192.168.20.233:9002/mongo:5.0.9"
    "mongo:4.4.13"
    "192.168.20.233:9002/mongo:5.0"
    "192.168.20.233:9002/mongo:4.2.14"
    "192.168.20.233:9002/mongo:4.4.0"
    "192.168.245.10:8092/mongo:3.6.1"
)

# 处理每个镜像
for image in "${images[@]}"; do
    # 提取镜像名称和版本
    if [[ $image =~ ([^/]+)/([^:]+):(.+) ]]; then
        registry=${BASH_REMATCH[1]}
        image_name=${BASH_REMATCH[2]}
        version=${BASH_REMATCH[3]}
        
        # 创建标准标签
        new_tag="mongo:$version"
        
        # 重命名镜像
        echo "重命名镜像: $image → $new_tag"
        docker tag "$image" "$new_tag"
        
        # 验证是否成功
        if docker inspect "$new_tag" &>/dev/null; then
            echo "✅ 成功创建标准镜像: $new_tag"
        else
            echo "❌ 错误：镜像重命名失败: $image"
        fi
    else
        echo "⚠️ 跳过无效镜像格式: $image"
    fi
done

# 列出所有标准化的MongoDB镜像
echo -e "\n所有标准化MongoDB镜像:"
docker images | grep 'mongo ' | awk '{print $1":"$2}' | sort -V