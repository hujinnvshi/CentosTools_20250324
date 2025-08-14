
[Unit]
Description=Shadowsocks-libev Default Server Service
Documentation=man:shadowsocks-libev(8)
After=network.target network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/sysconfig/shadowsocks-libev
User=nobody
Group=nobody
LimitNOFILE=32768
ExecStart=/usr/bin/ss-local -c /etc/shadowsocks-libev/configs/node3.json -u
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target

vim /usr/lib/systemd/system/shadowsocks-libev.service

systemctl daemon-reload

systemctl restart shadowsocks-libev.service

systemctl status shadowsocks-libev.service
