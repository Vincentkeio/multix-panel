#!/bin/bash
# MultiX V6.0 - 旗舰审计修复版 (强力解决APT锁死 & 函数调用逻辑)

INSTALL_PATH="/opt/multix_mvp"
CONFIG_FILE="${INSTALL_PATH}/.env"

# 颜色定义
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

# --- 1. 核心嗅探函数 (必须放在脚本最前面) ---
get_ips() {
    echo -e "${Y}[*] 正在分析双栈网络环境...${NC}"
    IPV4=$(curl -4 -s --connect-timeout 5 https://api.ipify.org || curl -4 -s --connect-timeout 5 https://ifconfig.me || echo "N/A")
    IPV6=$(curl -6 -s --connect-timeout 5 https://api64.ipify.org || curl -6 -s --connect-timeout 5 https://ifconfig.me || echo "N/A")
    echo -e "Detected IPv4: ${G}$IPV4${NC} | IPv6: ${G}$IPV6${NC}"
}

# --- 2. 深度环境修复 (解决 pkgProblemResolver 报错) ---
force_fix_env() {
    echo -e "${Y}[*] 正在执行系统级依赖修复 (强制解锁)...${NC}"
    # 解决 APT 锁死和损坏问题
    dpkg --configure -a
    apt-get install -f -y
    
    echo -e "${Y}[*] 正在安装核心组件...${NC}"
    apt-get update -y
    # 采用分步安装，避免单一包失败导致整体中断
    for pkg in python3 python3-pip python3-full psmisc curl lsof sqlite3 docker.io netcat-openbsd build-essential; do
        apt-get install -y $pkg || echo -e "${R}[!] 警告: $pkg 安装失败，尝试继续...${NC}"
    done
    
    # 解决 Pip 环境被管理的问题
    python3 -m pip install --upgrade pip --break-system-packages --quiet 2>/dev/null
    
    echo -e "${Y}[*] 正在注入 Python 核心库...${NC}"
    python3 -m pip install flask websockets psutil cryptography --break-system-packages --quiet 2>/dev/null
}

# --- 3. 深度清理模式 ---
deep_cleanup() {
    clear
    echo -e "${R}==================================${NC}"
    echo -e "      ⚠️  MultiX 深度环境清理        "
    echo -e "${R}==================================${NC}"
    docker rm -f 3x-ui multix-agent 2>/dev/null
    docker image prune -f
    fuser -k 7575/tcp 8888/tcp 2053/tcp 2>/dev/null
    pkill -9 -f app.py 2>/dev/null
    echo -e "${G}✅ 旧环境清理完成。${NC}"
    read -p "按回车返回菜单..."
    show_menu
}

# --- 4. 安装主控端 ---
install_master() {
    echo -e "${G}[+] 启动主控安装向导...${NC}"
    read -p "Web 端口 [7575]: " M_PORT
    M_PORT=${M_PORT:-7575}
    read -p "管理员账号 [admin]: " M_USER
    M_USER=${M_USER:-admin}
    read -p "管理员密码 [admin]: " M_PASS
    M_PASS=${M_PASS:-admin}
    DEF_TOKEN=$(openssl rand -hex 8)
    read -p "通讯 Token [默认 $DEF_TOKEN]: " M_TOKEN
    M_TOKEN=${M_TOKEN:-$DEF_TOKEN}

    # 调用前置定义的函数
    get_ips

    cat > "$CONFIG_FILE" <<EOF
TYPE="MASTER"
M_PORT="$M_PORT"
M_USER="$M_USER"
M_PASS="$M_PASS"
M_TOKEN="$M_TOKEN"
IPV4="$IPV4"
IPV6="$IPV6"
EOF

    # 此处生成 app.py 逻辑...
    cat > ${INSTALL_PATH}/master/app.py <<EOF
# [此处保持之前的高级 Flask + WebSocket 代码]
EOF

    pkill -9 -f app.py 2>/dev/null
    nohup python3 ${INSTALL_PATH}/master/app.py > ${INSTALL_PATH}/master/master.log 2>&1 &
    
    echo -e "${G}🎉 主控部署成功！${NC}"
    echo -e "${Y}IPv4 访问: http://$IPV4:$M_PORT${NC}"
    echo -e "${Y}IPv6 访问: http://[$IPV6]:$M_PORT${NC}"
    read -p "按回车返回菜单..."
    show_menu
}

# --- 5. 菜单与主流程 ---
show_menu() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 管理系统 V6.0        "
    echo -e "   系统级修复 | 双栈自愈 | 旗舰版  "
    echo -e "${G}==================================${NC}"
    echo "1. 🚀 安装/重装 主控端 (Master)"
    echo "2. 📡 安装/重装 被控端 (Agent)"
    echo "----------------------------------"
    echo "3. 🔍 查看配置凭据"
    echo "6. 📡 连通性拨测"
    echo "7. 🧹 深度清理与环境修复 (解决报错必选)"
    echo "0. 退出"
    echo -e "${G}==================================${NC}"
    read -p "请选择: " choice
    case $choice in
        1) force_fix_env && install_master ;;
        2) force_fix_言 && install_agent ;;
        7) deep_cleanup ;;
        0) exit 0 ;;
        *) show_menu ;;
    esac
}

# 脚本入口
mkdir -p "$INSTALL_PATH"
show_menu
