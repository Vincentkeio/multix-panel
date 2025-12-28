#!/bin/bash
# MultiX V5.2 旗舰版一键安装脚本

G='\033[0;32m'
Y='\033[1;33m'
NC='\033[0m'

install_master() {
    echo -e "${G}>>> 主控端安装引导${NC}"
    read -p "设置 Web 管理端口 [7575]: " M_PORT
    M_PORT=${M_PORT:-7575}
    read -p "设置管理员用户 [admin]: " M_USER
    M_USER=${M_USER:-admin}
    read -p "设置管理员密码 [admin]: " M_PASS
    M_PASS=${M_PASS:-admin}
    TOKEN=$(openssl rand -hex 12)
    read -p "设置通讯 Token [$TOKEN]: " M_TOKEN
    M_TOKEN=${M_TOKEN:-$TOKEN}

    mkdir -p /opt/multix/master
    # 此处省略：写入 app.py 的逻辑 (同上文)
    
    # 写入配置库
    echo "TOKEN=$M_TOKEN" > /opt/multix/master/config.env
    
    # 设置 Systemd
    cat > /etc/systemd/system/multix-master.service <<EOF
[Unit]
Description=MultiX Master
After=network.target
[Service]
ExecStart=/usr/bin/python3 /opt/multix/master/app.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable --now multix-master
    echo -e "${G}主控端已启动！端口: $M_PORT, Token: $M_TOKEN${NC}"
}

# 快捷命令封装
cat > /usr/local/bin/multix <<'EOF'
#!/bin/bash
echo "1. 重启服务  2. 查看配置  3. 停止所有"
read -p "请选择: " opt
case $opt in
    1) systemctl restart multix-master || docker restart multix-agent ;;
    2) cat /opt/multix/*/config.env ;;
esac
EOF
chmod +x /usr/local/bin/multix
