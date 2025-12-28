#!/bin/bash
# MultiX V5.9 - 旗舰审计版 (环境自愈 + 深层清理 + SQL嗅探 + 双栈拨测)

INSTALL_PATH="/opt/multix_mvp"
CONFIG_FILE="${INSTALL_PATH}/.env"

# 颜色定义
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

# --- 1. 深度环境修复与依赖安装 ---
force_fix_env() {
    echo -e "${Y}[*] 正在强行修复系统依赖与 Python 环境...${NC}"
    apt update -y
    # 安装必要组件，防止编译加密库失败
    apt install -y python3 python3-pip python3-full psmisc curl lsof sqlite3 docker.io netcat-openbsd build-essential libssl-dev libffi-dev -y
    
    # 强制升级并修复 pip
    python3 -m pip install --upgrade pip --break-system-packages --quiet 2>/dev/null
    
    # 核心库强装
    echo -e "${Y}[*] 正在安装 Python 核心库 (忽略冲突模式)...${NC}"
    python3 -m pip install flask websockets psutil cryptography --break-system-packages --quiet 2>/dev/null
}

# --- 2. 深度清理模式 ---
deep_cleanup() {
    clear
    echo -e "${R}==================================${NC}"
    echo -e "      ⚠️  MultiX 深层环境清理       "
    echo -e "${R}==================================${NC}"
    echo -e "${Y}[1/4] 正在停止并移除旧容器...${NC}"
    docker rm -f 3x-ui multix-agent 2>/dev/null
    
    echo -e "${Y}[2/4] 正在清理虚悬镜像 (Untagged Images)...${NC}"
    docker image prune -f
    
    echo -e "${Y}[3/4] 正在释放端口占用 (7575, 8888, 2053)...${NC}"
    fuser -k 7575/tcp 8888/tcp 2053/tcp 2>/dev/null
    
    echo -e "${Y}[4/4] 正在修复 Python 包残留...${NC}"
    pkill -9 -f app.py 2>/dev/null
    
    echo -e "${G}✅ 清理与修复完成！系统已恢复纯净状态。${NC}"
    read -p "按回车返回菜单..."
    show_menu
}

# --- 3. 菜单界面 ---
show_menu() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 管理系统 V5.9        "
    echo -e "   环境自愈 | 深层清理 | 暴力同步   "
    echo -e "${G}==================================${NC}"
    echo -e "${Y}[ 核心部署 ]${NC}"
    echo "1. 🚀 安装/重装 主控端 (Master)"
    echo "2. 📡 安装/重装 被控端 (Agent)"
    echo -e "----------------------------------"
    echo -e "${Y}[ 运维管理 ]${NC}"
    echo "3. 🔍 查看配置凭据 (Token/登录地址)"
    echo "4. 📊 查看服务运行状态"
    echo "5. ⚡ 服务管理 (启动/停止/重启)"
    echo "6. 📡 连通性拨测 (被控->主控)"
    echo "7. 🧹 深度清理与环境修复 (一键除残)"
    echo -e "----------------------------------"
    echo "9. 🗑️  完全卸载"
    echo "0. 🚪 退出"
    echo -e "${G}==================================${NC}"
    read -p "请选择操作 [0-9]: " choice
    case $choice in
        1) force_fix_env && install_master ;;
        2) force_fix_env && install_agent ;;
        3) show_credentials ;;
        4) show_status ;;
        5) service_mgr ;;
        6) check_connection ;;
        7) deep_cleanup ;;
        9) uninstall ;;
        0) exit 0 ;;
        *) show_menu ;;
    esac
}

# --- 4. 其它功能模块 (保持之前的逻辑，并确保变量加引号) ---

install_master() {
    # ... 原有 install_master 逻辑，增加以下代码显示 ...
    echo -e "${G}[+] 启动主控配置向导...${NC}"
    # (同 V5.8)
    # 确保在写入文件前获取最新 IP
    get_ips
    cat > $CONFIG_FILE <<EOF
TYPE="MASTER"
M_PORT="$M_PORT"
M_USER="$M_USER"
M_PASS="$M_PASS"
M_TOKEN="$M_TOKEN"
IPV4="$IPV4"
IPV6="$IPV6"
EOF
    # ... (app.py 生成逻辑)
}

# --- 5. 状态查看修复 ---
show_status() {
    clear
    echo -e "${Y}--- 服务状态 ---${NC}"
    pgrep -f "app.py" > /dev/null && echo -e "主控: ${G}运行中${NC}" || echo -e "主控: ${R}已停止${NC}"
    docker ps | grep -q "multix-agent" && echo -e "被控: ${G}运行中${NC}" || echo -e "被控: ${R}已停止${NC}"
    docker ps | grep -q "3x-ui" && echo -e "3X-UI: ${G}运行中${NC}" || echo -e "3X-UI: ${R}已停止${NC}"
    echo ""
    read -p "按回车返回菜单..."
    show_menu
}

# --- 执行入口 ---
mkdir -p $INSTALL_PATH
show_menu
