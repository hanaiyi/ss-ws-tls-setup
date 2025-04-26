#!/bin/bash

# ====================
# Shadowsocks-libev + HTTP混淆 全自动部署脚本
# 适配 Ubuntu 22.04 LTS
# ====================

# --- 基础输入 ---
DOMAIN="example.com"  # 替换为您的域名
PASSWORD="haMLMXirByn6rGVh"  # 默认密码
PORT=12022  # 默认端口
OBFS_PARAM="b1af514584f3.microsoft.com"  # 混淆参数
METHOD="aes-128-gcm"  # 加密方式
FLAG="KR"  # 节点国家/地区标志
TITLE="�🇷 韩国 01丨1x KR"  # 节点标题

# 允许用户修改默认值
read -p "请输入你的域名 (默认: $DOMAIN): " input_domain
DOMAIN=${input_domain:-$DOMAIN}

read -p "请输入你的连接密码 (默认: $PASSWORD): " input_password
PASSWORD=${input_password:-$PASSWORD}

read -p "请输入端口号 (默认: $PORT): " input_port
PORT=${input_port:-$PORT}

read -p "请输入混淆参数 (默认: $OBFS_PARAM): " input_obfs_param
OBFS_PARAM=${input_obfs_param:-$OBFS_PARAM}

# --- 系统更新 ---
echo "✅ 更新系统中..."
apt update -y
apt upgrade -y

# --- 安装必要软件 ---
echo "✅ 安装 Shadowsocks-libev 和常用工具..."
apt install -y shadowsocks-libev simple-obfs wget curl unzip socat ufw software-properties-common

# --- 配置 Shadowsocks ---
echo "✅ 配置 Shadowsocks-libev..."
mkdir -p /etc/shadowsocks-libev
cat > /etc/shadowsocks-libev/config.json << EOF
{
  "server":"0.0.0.0",
  "server_port":$PORT,
  "password":"$PASSWORD",
  "timeout":300,
  "method":"$METHOD",
  "mode":"tcp_and_udp",
  "plugin":"obfs-server",
  "plugin_opts":"obfs=http;obfs-host=$OBFS_PARAM"
}
EOF

systemctl enable shadowsocks-libev
systemctl restart shadowsocks-libev

# --- 配置防火墙 ---
echo "✅ 开启防火墙并放行必要端口..."
ufw allow $PORT
ufw --force enable

# --- 启用 TCP BBR 加速 ---
echo "✅ 开启 TCP BBR 加速..."
modprobe tcp_bbr
echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

# --- 生成配置文件 ---
echo "✅ 正在生成配置文件..."
SERVER_IP=$(curl -s http://ipinfo.io/ip)
SS_BASE64=$(echo -n "$METHOD:$PASSWORD" | base64 -w 0)
SS_URI="ss://$SS_BASE64@$SERVER_IP:$PORT?plugin=obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3D$OBFS_PARAM#$TITLE"

# 生成Clash配置文件
cat > ss-obfs-config.yaml << EOF
port: 7890
socks-port: 7891
allow-lan: true
mode: Rule
log-level: info
external-controller: 127.0.0.1:9090

proxies:
  - name: $TITLE
    type: ss
    server: $SERVER_IP
    port: $PORT
    cipher: $METHOD
    password: $PASSWORD
    plugin: obfs
    plugin-opts:
      mode: http
      host: $OBFS_PARAM

proxy-groups:
  - name: 🚀 节点选择
    type: select
    proxies:
      - $TITLE
      - DIRECT

rules:
  - MATCH,🚀 节点选择
EOF

# 生成Shadowrocket配置
cat > shadowrocket-config.json << EOF
{
  "host": "$SERVER_IP",
  "file": "",
  "obfsParam": "$OBFS_PARAM",
  "alpn": "",
  "cert": "",
  "created": $(date +%s.%N | cut -b1-13),
  "updated": $(date +%s.%N | cut -b1-13),
  "mtu": "",
  "tfo": 1,
  "flag": "$FLAG",
  "privateKey": "",
  "hpkp": "",
  "uuid": "$(cat /proc/sys/kernel/random/uuid)",
  "type": "Shadowsocks",
  "downmbps": "",
  "ping": 30,
  "user": "",
  "ech": "",
  "plugin": "",
  "method": "$METHOD",
  "data": "local://$(openssl rand -hex 16)",
  "udp": 1,
  "filter": "",
  "protoParam": "",
  "reserved": "",
  "alterId": "",
  "upmbps": "",
  "keepalive": "",
  "port": "$PORT",
  "obfs": "http",
  "dns": "",
  "publicKey": "",
  "peer": "",
  "weight": $(date +%s),
  "title": "$TITLE",
  "proto": "",
  "password": "$PASSWORD",
  "shortId": "",
  "chain": "",
  "ip": ""
}
EOF

echo "=============================="
echo "✅ 部署完成！连接信息如下："
echo "服务器IP: $SERVER_IP"
echo "端口: $PORT"
echo "密码: $PASSWORD"
echo "加密: $METHOD"
echo "混淆: http"
echo "混淆参数: $OBFS_PARAM"
echo "=============================="
echo "SS链接: $SS_URI"
echo "Clash配置文件: $(pwd)/ss-obfs-config.yaml"
echo "Shadowrocket配置文件: $(pwd)/shadowrocket-config.json"
echo "=============================="