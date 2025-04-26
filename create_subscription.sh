#!/bin/bash

# 订阅系统配置
SUB_DIR="/var/www/html/sub"
DOMAIN_OR_IP=$(curl -s http://ipinfo.io/ip)  # 如果有域名可以替换此处
PORT="80"  # 订阅服务器的端口
AUTH_PATH=$(openssl rand -hex 8)  # 随机生成的访问路径，增加安全性

# 安装依赖
apt update
apt install -y nginx php-fpm

# 创建目录
mkdir -p $SUB_DIR

# 配置Nginx
cat > /etc/nginx/conf.d/subscription.conf << EOF
server {
    listen 80;
    root $SUB_DIR;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
    }
}
EOF

# 重启Nginx
systemctl restart nginx

# 创建订阅生成PHP脚本
cat > $SUB_DIR/index.php << EOF
<?php
header('Content-Type: text/plain');
\$servers = [
    [
        'name' => '$TITLE',
        'type' => 'ss',
        'server' => '$DOMAIN_OR_IP',
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
        // Surge格式处理
        break;
        
    case 'json':
        header('Content-Type: application/json');
        echo json_encode(\$servers);
        break;
        
    case 'ss':
    case 'base64':
    default:
        // 生成标准SS URI链接并Base64编码
        \$links = [];
        foreach(\$servers as \$server) {
            \$method_pwd = base64_encode(\$server['cipher'] . ":" . \$server['password']);
            \$plugin_str = '';
            if (isset(\$server['plugin']) && \$server['plugin']) {
                \$plugin_str = "?plugin=" . urlencode(\$server['plugin'] . ";" . 
                               "obfs=" . \$server['plugin-opts']['mode'] . ";" . 
                               "obfs-host=" . \$server['plugin-opts']['host']);
            }
            \$links[] = "ss://" . \$method_pwd . "@" . \$server['server'] . ":" . 
                      \$server['port'] . \$plugin_str . "#" . urlencode(\$server['name']);
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

# 生成订阅URL
SUB_URL="http://$DOMAIN_OR_IP/$AUTH_PATH"

echo "=============================="
echo "✅ 订阅系统已配置完成！"
echo "订阅链接: $SUB_URL"
echo ""
echo "支持的格式:"
echo "- 默认Base64格式: $SUB_URL"
echo "- Clash配置: $SUB_URL?format=clash"
echo "- JSON格式: $SUB_URL?format=json"
echo "=============================="
