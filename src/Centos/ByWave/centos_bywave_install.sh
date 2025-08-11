#!/bin/bash
# 自动生成 Shadowsocks-libev 配置并选择最快节点启动
# 用法: ./gen_and_start_ss.sh 订阅链接

SUB_URL="$1"
OUTPUT_DIR="/etc/shadowsocks-libev/configs"

if [[ -z "$SUB_URL" ]]; then
    echo "用法: $0 订阅链接"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
TMP_FILE=$(mktemp)

echo "📥 正在下载订阅..."
curl -sL "$SUB_URL" -o "$TMP_FILE"

# 检测是否 Base64
if base64 -d "$TMP_FILE" >/dev/null 2>&1; then
    base64 -d "$TMP_FILE" > "${TMP_FILE}_decoded"
    mv "${TMP_FILE}_decoded" "$TMP_FILE"
fi

i=1
NODES=()

echo "🛠 正在解析节点..."
while read -r line; do
    [[ -z "$line" ]] && continue
    [[ "${line:0:5}" != "ss://" ]] && continue

    url="${line#ss://}"
    url="${url%%#*}" # 去掉备注

    plugin_opts=""
    if [[ "$url" == *"?"* ]]; then
        plugin_opts="${url#*\?}"
        url="${url%%\?*}"
    fi

    userinfo="${url%@*}"
    serverinfo="${url#*@}"

    method_pass=$(echo "$userinfo" | base64 -d 2>/dev/null || echo "$userinfo")
    method="${method_pass%%:*}"
    password="${method_pass#*:}"

    server="${serverinfo%%:*}"
    port="${serverinfo##*:}"

    decoded_opts=$(printf '%b' "${plugin_opts//%/\\x}")
    safe_opts=$(printf '%s' "$decoded_opts" | sed 's/\\/\\\\/g; s/"/\\"/g')

    config_file="$OUTPUT_DIR/node${i}.json"
    cat > "$config_file" <<EOF
{
    "server": "$server",
    "server_port": $port,
    "local_address": "0.0.0.0",
    "local_port": 1080,
    "password": "$password",
    "timeout": 300,
    "method": "$method",
    "plugin": "obfs-local",
    "plugin_opts": "$safe_opts",
    "fast_open": true
}
EOF

    NODES+=("$server|$config_file")
    echo "✅ 已生成: $config_file"
    ((i++))
done < "$TMP_FILE"

rm -f "$TMP_FILE"

echo "📡 正在测速..."
BEST_NODE=""
BEST_PING=99999

for entry in "${NODES[@]}"; do
    server="${entry%%|*}"
    config="${entry##*|}"

    ping_ms=$(ping -c 1 -W 1 "$server" 2>/dev/null | grep 'time=' | awk -F'time=' '{print $2}' | cut -d' ' -f1)
    ping_ms=${ping_ms%.*}  # 去小数
    if [[ -z "$ping_ms" ]]; then
        ping_ms=99999
    fi

    echo "🌐 节点 $server 延迟: ${ping_ms}ms"

    if (( ping_ms < BEST_PING )); then
        BEST_PING=$ping_ms
        BEST_NODE="$config"
    fi
done

if [[ -z "$BEST_NODE" ]]; then
    echo "❌ 没有可用节点"
    exit 1
fi

echo "🚀 启动最快节点 ($BEST_NODE) 延迟 ${BEST_PING}ms..."
pkill -f ss-local
nohup ss-local -c "$BEST_NODE" -u >/dev/null 2>&1 &

echo "✅ 已启动，SOCKS5 代理监听在 127.0.0.1:1080"
