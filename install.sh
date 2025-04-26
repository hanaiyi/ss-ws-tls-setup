#!/bin/bash

# ====================
# Shadowsocks-libev + WebSocket + TLS 全自动部署脚本
# 适配 Ubuntu 22.04 LTS
# ====================

# --- 基础输入 ---
read -p "请输入你的域名（已解析到服务器IP）: " DOMAIN
read -p "请输入你的连接密码（任意字符串）: " PASSWORD
PORT=443
WS_PATH="/ss"

# --- 系统更新 ---
echo "✅ 更新系统中..."
apt update -y
apt upgrade -y

# --- 安装必要软件 ---
echo "✅ 安装 Shadowsocks-libev 和常用工具..."
apt install -y shadowsocks-libev wget curl unzip socat ufw software-properties-common gnupg2 lsb-release

# --- 安装 v2ray-plugin ---
echo "✅ 下载 v2ray-plugin..."
wget -O /tmp/v2ray-plugin.tar.gz https://github.com/shadowsocks/v2ray-plugin/releases/download/v1.3.2/v2ray-plugin-linux-amd64-v1.3.2.tar.gz
tar -xzf /tmp/v2ray-plugin.tar.gz -C /tmp/
mv /tmp/v2ray-plugin_linux_amd64 /usr/local/bin/v2ray-plugin
chmod +x /usr/local/bin/v2ray-plugin

# --- 配置 Shadowsocks ---
echo "✅ 配置 Shadowsocks-libev..."
mkdir -p /etc/shadowsocks-libev
cat > /etc/shadowsocks-libev/config.json << EOF
{
  "server":"127.0.0.1",
  "server_port": 8388,
  "password":"$PASSWORD",
  "timeout":300,
  "method":"aes-256-gcm",
  "mode":"tcp_and_udp",
  "plugin":"v2ray-plugin",
  "plugin_opts":"server;path=$WS_PATH;host=$DOMAIN"
}
EOF

systemctl enable shadowsocks-libev
systemctl restart shadowsocks-libev

# --- 安装 Caddy 2 ---
echo "✅ 安装 Caddy2..."
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install caddy -y

# --- 配置 Caddy ---
echo "✅ 配置 Caddy反代..."
cat > /etc/caddy/Caddyfile << EOF
$DOMAIN {
    reverse_proxy $WS_PATH 127.0.0.1:8388 {
        transport http {
            versions h2c
        }
    }
    encode gzip
}
EOF

systemctl enable caddy
systemctl restart caddy

# --- 配置防火墙 ---
echo "✅ 开启防火墙并放行必要端口..."
ufw allow 80
ufw allow 443
ufw allow 8388
ufw --force enable

# --- 启用 TCP BBR 加速 ---
echo "✅ 开启 TCP BBR 加速..."
modprobe tcp_bbr
echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

# --- 完成 ---
echo "=============================="
echo "✅ 部署完成！连接信息如下："
echo "服务器: $DOMAIN"
echo "端口: 443"
echo "密码: $PASSWORD"
echo "加密: aes-256-gcm"
echo "插件: v2ray-plugin"
echo "插件参数: path=$WS_PATH;host=$DOMAIN;tls"
echo "=============================="

# --- 生成配置文件 ---
echo "✅ 正在生成配置文件..."
SS_BASE64=$(echo -n "aes-256-gcm:$PASSWORD" | base64 -w 0)
SS_URI="ss://$SS_BASE64@$DOMAIN:443?plugin=v2ray-plugin;path=%2Fss;host=$DOMAIN;tls#SS-WebSocket-TLS"

# 生成Clash配置文件
cat > ss-config.yaml << EOF
port: 7890
socks-port: 7891
allow-lan: true
mode: Rule
log-level: info
external-controller: 127.0.0.1:9090

proxies:
  - name: SS-WebSocket-TLS
    type: ss
    server: $DOMAIN
    port: 443
    cipher: aes-256-gcm
    password: $PASSWORD
    plugin: v2ray-plugin
    plugin-opts:
      mode: websocket
      tls: true
      host: $DOMAIN
      path: $WS_PATH

proxy-groups:
  - name: 节点选择
    type: select
    proxies:
      - SS-WebSocket-TLS
      - DIRECT

rules:
  - MATCH, 节点选择
EOF

echo "==============================="
echo "✅ 配置文件已生成："
echo "SS链接: $SS_URI"
echo "Clash配置文件: $(pwd)/ss-config.yaml"
echo "==============================="
