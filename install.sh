#!/bin/bash

# ====================
# Shadowsocks-libev + HTTP混淆 全自动部署脚本
# 支持HTTP混淆和订阅功能
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
ENABLE_SUB=true  # 是否启用订阅功能
AUTH_PATH=$(openssl rand -hex 8)  # 订阅随机路径

# 允许用户修改默认值
read -p "请输入你的域名 (默认: $DOMAIN): " input_domain
DOMAIN=${input_domain:-$DOMAIN}

read -p "请输入你的连接密码 (默认: $PASSWORD): " input_password
PASSWORD=${input_password:-$PASSWORD}

read -p "请输入端口号 (默认: $PORT): " input_port
PORT=${input_port:-$PORT}

read -p "请输入混淆参数 (默认: $OBFS_PARAM): " input_obfs_param
OBFS_PARAM=${input_obfs_param:-$OBFS_PARAM}

read -p "是否启用订阅功能? (y/n, 默认: y): " input_sub
if [[ "$input_sub" == "n" || "$input_sub" == "N" ]]; then
    ENABLE_SUB=false
fi

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

# --- 设置订阅系统 ---
if [ "$ENABLE_SUB" = true ]; then
    echo "✅ 配置订阅系统..."
    
    # 安装所需软件
    apt install -y nginx php-fpm

    # 创建目录
    SUB_DIR="/var/www/html/sub"
    mkdir -p $SUB_DIR
    mkdir -p $SUB_DIR/$AUTH_PATH

    # 配置Nginx
    cat > /etc/nginx/conf.d/subscription.conf << EOF
server {
    listen 80;
    root $SUB_DIR;
    index index.php index.html;

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
    }
}
EOF

    # 创建订阅生成PHP脚本
    cat > $SUB_DIR/$AUTH_PATH/index.php << EOF
<?php
header('Access-Control-Allow-Origin: *');
header('Cache-Control: no-cache');

\$servers = [
    [
        'name' => '$TITLE',
        'type' => 'ss',
        'server' => '$SERVER_IP',
        'port' => $PORT,
        'password' => '$PASSWORD',
        'cipher' => '$METHOD',
        'plugin' => 'obfs',
        'plugin-opts' => [
            'mode' => 'http',
            'host' => '$OBFS_PARAM'
        ]
    ]
    // 这里可以添加更多服务器
];

// 转换为各种客户端格式
\$format = isset(\$_GET['format']) ? \$_GET['format'] : 'base64';

switch(\$format) {
    case 'clash':
        header('Content-Type: text/yaml');
        header('Content-Disposition: attachment; filename="clash_config.yaml"');
        
        echo "port: 7890\n";
        echo "socks-port: 7891\n";
        echo "allow-lan: true\n";
        echo "mode: Rule\n";
        echo "log-level: info\n";
        echo "external-controller: 127.0.0.1:9090\n\n";
        
        echo "proxies:\n";
        foreach(\$servers as \$server) {
            echo "  - name: " . \$server['name'] . "\n";
            echo "    type: " . \$server['type'] . "\n";
            echo "    server: " . \$server['server'] . "\n";
            echo "    port: " . \$server['port'] . "\n";
            echo "    cipher: " . \$server['cipher'] . "\n";
            echo "    password: " . \$server['password'] . "\n";
            if (isset(\$server['plugin']) && \$server['plugin']) {
                echo "    plugin: " . \$server['plugin'] . "\n";
                echo "    plugin-opts:\n";
                echo "      mode: " . \$server['plugin-opts']['mode'] . "\n";
                echo "      host: " . \$server['plugin-opts']['host'] . "\n";
            }
            echo "\n";
        }
        
        echo "proxy-groups:\n";
        echo "  - name: 🚀 节点选择\n";
        echo "    type: select\n";
        echo "    proxies:\n";
        foreach(\$servers as \$server) {
            echo "      - " . \$server['name'] . "\n";
        }
        echo "      - DIRECT\n\n";
        
        echo "rules:\n";
        echo "  - MATCH,🚀 节点选择\n";
        break;
        
    case 'surge':
        header('Content-Type: text/plain');
        echo "[General]\n";
        echo "loglevel = notify\n\n";
        echo "[Proxy]\n";
        foreach(\$servers as \$server) {
            echo \$server['name'] . " = ss, " . \$server['server'] . ", " . \$server['port'] . ", ";
            echo "encrypt-method=" . \$server['cipher'] . ", password=" . \$server['password'] . ", ";
            if (isset(\$server['plugin']) && \$server['plugin'] == 'obfs') {
                echo "obfs=http, obfs-host=" . \$server['plugin-opts']['host'];
            }
            echo "\n";
        }
        break;
        
    case 'quan':
        header('Content-Type: text/plain');
        echo "[SERVER]\n";
        foreach(\$servers as \$server) {
            echo \$server['name'] . " = shadowsocks, " . \$server['server'] . ", " . \$server['port'] . ", ";
            echo \$server['cipher'] . ", " . \$server['password'] . ", upstream-proxy=false, upstream-proxy-auth=false";
            if (isset(\$server['plugin']) && \$server['plugin'] == 'obfs') {
                echo ", obfs=http, obfs-host=" . \$server['plugin-opts']['host'];
            }
            echo "\n";
        }
        break;
        
    case 'sip002':
        header('Content-Type: text/plain');
        \$links = [];
        foreach(\$servers as \$server) {
            \$method_pwd = base64_encode(\$server['cipher'] . ":" . \$server['password']);
            \$plugin_str = '';
            if (isset(\$server['plugin']) && \$server['plugin']) {
                \$plugin_str = "?plugin=" . urlencode("obfs-local;obfs=http;obfs-host=" . \$server['plugin-opts']['host']);
            }
            \$links[] = "ss://" . \$method_pwd . "@" . \$server['server'] . ":" . \$server['port'] . \$plugin_str . "#" . urlencode(\$server['name']);
        }
        echo implode("\n", \$links);
        break;
        
    case 'json':
        header('Content-Type: application/json');
        echo json_encode(\$servers);
        break;
        
    case 'base64':
    default:
        // 生成标准SS URI链接并Base64编码
        \$links = [];
        foreach(\$servers as \$server) {
            \$method_pwd = base64_encode(\$server['cipher'] . ":" . \$server['password']);
            \$plugin_str = '';
            if (isset(\$server['plugin']) && \$server['plugin']) {
                \$plugin_str = "?plugin=" . urlencode("obfs-local;obfs=http;obfs-host=" . \$server['plugin-opts']['host']);
            }
            \$links[] = "ss://" . \$method_pwd . "@" . \$server['server'] . ":" . \$server['port'] . \$plugin_str . "#" . urlencode(\$server['name']);
        }
        echo base64_encode(implode("\n", \$links));
}
?>
EOF

    # 设置权限
    chmod -R 755 $SUB_DIR
    chown -R www-data:www-data $SUB_DIR

    # 开放防火墙
    ufw allow 80

    # 重启Nginx
    systemctl restart nginx

    # 生成订阅URL
    SUB_URL="http://$SERVER_IP/$AUTH_PATH"

    echo ""
    echo "✅ 订阅系统配置完成！"
    echo "订阅链接: $SUB_URL"
    echo ""
    echo "支持的格式:"
    echo "- 标准Base64订阅 (所有客户端): $SUB_URL"
    echo "- Clash配置订阅: $SUB_URL?format=clash"
    echo "- Surge配置订阅: $SUB_URL?format=surge"
    echo "- Quantumult配置订阅: $SUB_URL?format=quan"
    echo "- SIP002格式订阅: $SUB_URL?format=sip002"
    echo "- JSON格式: $SUB_URL?format=json"
fi

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