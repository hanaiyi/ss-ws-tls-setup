# ========= 系统准备 =========
echo "✅ 更新系统..."
apt update -y && apt upgrade -y

echo "✅ 安装必要组件..."
apt install -y shadowsocks-libev wget unzip curl gnupg2 lsb-release ufw socat

# ========= 安装 v2ray-plugin =========
echo "✅ 安装 v2ray-plugin..."
wget -qO- https://github.com/shadowsocks/v2ray-plugin/releases/download/v1.3.2/v2ray-plugin-linux-amd64-v1.3.2.tar.gz | tar xz
mv v2ray-plugin_linux_amd64 /usr/local/bin/v2ray-plugin
chmod +x /usr/local/bin/v2ray-plugin

# ========= 配置 Shadowsocks-libev =========
echo "✅ 配置 Shadowsocks..."
mkdir -p /etc/shadowsocks-libev
cat > /etc/shadowsocks-libev/config.json << EOF
{
    "server":"127.0.0.1",
    "server_port":$PORT,
    "password":"$PASSWORD",
    "timeout":300,
    "method":"aes-256-gcm",
    "mode":"tcp_and_udp",
    "plugin":"v2ray-plugin",
    "plugin_opts":"server;path=$PATH;host=$DOMAIN"
}
EOF

systemctl enable shadowsocks-libev
systemctl restart shadowsocks-libev

# ========= 安装 Caddy2 =========
echo "✅ 安装 Caddy2..."
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install caddy -y

echo "✅ 配置 Caddy..."
cat > /etc/caddy/Caddyfile << EOF
$DOMAIN {
    reverse_proxy $PATH 127.0.0.1:$PORT {
        transport http {
            versions h2c
        }
    }
    encode gzip
}
EOF

systemctl enable caddy
systemctl restart caddy

# ========= 防火墙放行 =========
echo "✅ 配置防火墙..."
ufw allow 80
ufw allow 443
ufw allow $PORT
ufw --force enable

# ========= 开启 BBR 加速 =========
echo "✅ 开启 TCP BBR 加速..."
modprobe tcp_bbr
echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
sysctl -w net.ipv4.tcp_congestion_control=bbr
sysctl -w net.core.default_qdisc=fq
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

# ========= 完成 =========
echo "=============================="
echo "✅ 部署完成！以下是你的连接信息："
echo "--------------------------------"
echo "服务器地址: $DOMAIN"
echo "端口: 443"
echo "密码: $PASSWORD"
echo "加密方式: aes-256-gcm"
echo "插件: v2ray-plugin"
echo "插件参数: path=$PATH;host=$DOMAIN;tls"
echo "--------------------------------"
echo "🌟 客户端请使用 WebSocket+TLS 连接！"
echo "=============================="
