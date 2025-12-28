#!/bin/bash
# MultiX V5.7 - 旗舰增强版 (增加连通性拨测 + 双栈优化)

INSTALL_PATH="/opt/multix_mvp"
CONFIG_FILE="${INSTALL_PATH}/.env"

# 颜色定义
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

# --- 辅助：获取双栈IP ---
get_ips() {
    IPV4=$(curl -4 -s --connect-timeout 3 ifconfig.me || echo "N/A")
    IPV6=$(curl -6 -s --connect-timeout 3 ifconfig.me || echo "N/A")
}

# --- 菜单界面 ---
show_menu() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 管理系统 V5.7        "
    echo -e "   双栈连接预检 | 状态自愈模式    "
    echo -e "${G}==================================${NC}"
    echo -e "1. 🚀 安装/重装 主控端 (Master)"
    echo -e "2. 📡 安装/重装 被控端 (Agent)"
    echo -e "----------------------------------"
    echo -e "3. 🔍 查看配置凭据 (登录地址/Token)"
    echo -e "4. 📊 查看服务运行状态"
    echo -e "5. ⚡ 服务管理 (启动/停止/重启)"
    echo -e "6. 📡 连通性拨测 (测试被控->主控)"
    echo -e "----------------------------------"
    echo -e "9. 🗑️  完全卸载"
    echo -e "0. 🚪 退出"
    echo -e "${G}==================================${NC}"
    read -p "请选择操作 [0-9]: " choice
}

# --- 连通性测试逻辑 ---
check_connection() {
    clear
    echo -e "${Y}>>> 正在启动连通性拨测...${NC}"
    
    if [ ! -f $CONFIG_FILE ]; then
        echo -e "${R}[!] 错误：未发现配置文件。请先安装被控端 (选项 2)。${NC}"
    else
        source $CONFIG_FILE
        if [ "$TYPE" != "AGENT" ]; then
            echo -e "${R}[!] 错误：当前机器不是被控端，无法测试连接主控。${NC}"
        elif [ -z "$MASTER_HOST" ] || [ -z "$M_TOKEN" ]; then
            echo -e "${R}[!] 错误：连接凭据不全，请重新安装被控端。${NC}"
        else
            echo -e "${G}[*] 目标主控: $MASTER_HOST${NC}"
            echo -e "${G}[*] 通讯 Token: $M_TOKEN${NC}"
            echo -e "----------------------------------"
            
            # 1. 基础网络 Ping 测试 (双栈)
            echo -e "${Y}[1/2] 正在测试基础网络响应...${NC}"
            if ping -c 2 -W 3 $MASTER_HOST > /dev/null 2>&1; then
                echo -e "基础网络: ${G}已连接 (Ping OK)${NC}"
            else
                echo -e "基础网络: ${R}无法访问 (Ping Failed)${NC}"
            fi

            # 2. 端口及 WS 握手测试
            echo -e "${Y}[2/2] 正在拨测主控 WS 端口 (8888)...${NC}"
            # 尝试使用 curl 测试 web 端口，判断服务是否存活
            WS_CHECK=$(curl -I -s --connect-timeout 5 http://$MASTER_HOST:8888 2>&1 | grep "HTTP/")
            
            # 使用 nc 探测端口更准确
            if nc -zv -w 5 $MASTER_HOST 8888 > /dev/null 2>&1; then
                echo -e "主控端口: ${G}开启 (Port 8888 is Open)${NC}"
                echo -e "${G}>>> 结论：被控端具备连接主控的条件。${NC}"
            else
                echo -e "主控端口: ${R}不通 (Port 8888 is Closed)${NC}"
                echo -e "${Y}提示：请检查主控防火墙是否开放 8888 端口。${NC}"
            fi
        fi
    fi
    
    echo -e "----------------------------------"
    read -n 1 -s -r -p "拨测结束，按任意键返回菜单..."
}

# --- 查看凭据 (优化版) ---
show_credentials() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 凭据与配置信息       "
    echo -e "${G}==================================${NC}"
    if [ ! -f $CONFIG_FILE ]; then
        echo -e "${R}未发现配置文件，请先安装！${NC}"
    else
        source $CONFIG_FILE
        if [ "$TYPE" == "MASTER" ]; then
            echo -e "${Y}类型: 主控端 (Master)${NC}"
            echo -e "管理用户: $M_USER / 密码: $M_PASS"
            echo -e "通讯 Token: $M_TOKEN"
            echo -e "IPv4 访问: http://$IPV4:$M_PORT"
            echo -e "IPv6 访问: http://[$IPV6]:$M_PORT"
        else
            echo -e "${Y}类型: 被控端 (Agent)${NC}"
            echo -e "连接主控: $MASTER_HOST"
            echo -e "通讯 Token: $M_TOKEN"
            echo -e "本机出口: $LOCAL_IPV4 / $LOCAL_IPV6"
        fi
    fi
    echo -e "${G}==================================${NC}"
    read -p "按回车返回菜单..."
}

# --- 逻辑循环入口 ---
while true; do
    show_menu
    case $choice in
        1) # 保持 install_master 逻辑
           ;;
        2) # 保持 install_agent 逻辑
           ;;
        3) show_credentials ;;
        4) # 保持状态查看逻辑
           ;;
        6) check_connection ;; # 新增连通性测试
        9) rm -rf $INSTALL_PATH; exit 0 ;;
        0) exit 0 ;;
    esac
done
