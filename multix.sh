#!/bin/bash

# ==============================================================================
# 🚀 MultiX - Nezha Server Status Manager (Docker Edition)
# Version: 5.0.0 (Smart Config)
# Description: 面板与监控端的一站式运维管理工具
# ==============================================================================

# --- 全局配置 ---
BASE_DIR="/opt/multix"
CONF_FILE="${BASE_DIR}/config.env"
SCRIPT_PATH="${BASE_DIR}/manager.sh"
LINK_PATH="/usr/bin/multix"

# 默认参数
IMG_DASHBOARD="ghcr.io/naiba/nezha-dashboard"
IMG_AGENT="ghcr.io/naiba/nezha-agent"
DEFAULT_DASH_PORT=8008
DEFAULT_GRPC_PORT=5555

# 颜色
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
PLAIN='\033[0m'
GRAY='\033[90m'

# 确保目录
mkdir -p "$BASE_DIR"

# --- 基础函数 ---

check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}错误：必须使用 root 权限运行！${PLAIN}" && exit 1
}

install_dependencies() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}正在安装 Docker...${PLAIN}"
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker; systemctl start docker
    fi
    if ! command -v bc &> /dev/null; then
        [ -f /etc/debian_version ] && apt-get install -y bc
        [ -f /etc/redhat-release ] && yum install -y bc
    fi
}

install_shortcut() {
    if [ "$0" != "$SCRIPT_PATH" ]; then
        cp "$0" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
    fi
    ln -sf "$SCRIPT_PATH" "$LINK_PATH"
}

# --- 配置管理 ---
load_config() {
    if [ -f "$CONF_FILE" ]; then source "$CONF_FILE"; fi
    CURRENT_DASH_PORT=${NZ_DASHBOARD_PORT:-$DEFAULT_DASH_PORT}
    CURRENT_GRPC_PORT=${NZ_GRPC_PORT:-$DEFAULT_GRPC_PORT}
}

save_config() {
    cat > "$CONF_FILE" <<EOF
# MultiX Config
NZ_DASHBOARD_PORT=${NZ_DASHBOARD_PORT:-$DEFAULT_DASH_PORT}
NZ_GRPC_PORT=${NZ_GRPC_PORT:-$DEFAULT_GRPC_PORT}
NZ_SERVER="${NZ_SERVER}"
NZ_TOKEN="${NZ_TOKEN}"
EOF
}

# --- 环境检测 ---
check_env_status() {
    ENV_SAFE=true
    CONFLICT_MSG=""
    
    # 检查 Systemd 残留
    if systemctl is-active --quiet nezha-dashboard || [ -f /etc/systemd/system/nezha-dashboard.service ]; then
        ENV_SAFE=false; CONFLICT_MSG+="[Systemd: Dashboard] "
    fi
    if systemctl is-active --quiet nezha-agent || [ -f /etc/systemd/system/nezha-agent.service ]; then
        ENV_SAFE=false; CONFLICT_MSG+="[Systemd: Agent] "
    fi
    
    if [ "$ENV_SAFE" = true ]; then
        ENV_DISPLAY="${GREEN}✅ 通过${PLAIN}"
    else
        ENV_DISPLAY="${RED}❌ 冲突${PLAIN}"
    fi
}

# --- UI 辅助 ---
draw_bar() {
    local percent=$1; local total=10
    ! command -v bc &> /dev/null && echo "[${percent}%]" && return
    local filled=$(echo "scale=0; $percent * $total / 100" | bc)
    local empty=$((total - filled))
    local bar=""; for ((i=0; i<filled; i++)); do bar+="▓"; done; for ((i=0; i<empty; i++)); do bar+="░"; done
    if [ "$percent" -ge 80 ]; then echo -e "${RED}[${bar}]${PLAIN}"; elif [ "$percent" -ge 60 ]; then echo -e "${YELLOW}[${bar}]${PLAIN}"; else echo -e "${GREEN}[${bar}]${PLAIN}"; fi
}

get_system_info() {
    KERNEL_VER=$(uname -r)
    OS_INFO=$(grep PRETTY_NAME /etc/os-release | cut -d '"' -f 2)
    [ -z "$OS_INFO" ] && OS_INFO=$(cat /etc/os-release | grep -i pretty_name | cut -d = -f 2)
    MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
    MEM_PER=0; [ "$MEM_TOTAL" -gt 0 ] && MEM_PER=$(awk "BEGIN {print int($MEM_USED/$MEM_TOTAL*100)}")
    MEM_BAR=$(draw_bar $MEM_PER)
    
    DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    DISK_PER=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    DISK_BAR=$(draw_bar $DISK_PER)
}

# 检测容器是否存在且运行
check_container_running() {
    local name=$1
    if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
        return 0 # Running
    else
        return 1 # Not running
    fi
}

get_container_status() {
    # Dashboard
    if check_container_running "nezha-dashboard"; then
        STATUS_D="${GREEN}● 运行中${PLAIN}"; ID_D=$(docker ps -f name=nezha-dashboard --format "{{.ID}}")
        IS_DASH_INSTALLED=true
    elif docker ps -a --format '{{.Names}}' | grep -q "^nezha-dashboard$"; then
        STATUS_D="${RED}● 已停止${PLAIN}"; ID_D=$(docker ps -a -f name=nezha-dashboard --format "{{.ID}}")
        IS_DASH_INSTALLED=true
    else
        STATUS_D="${GRAY}● 未安装${PLAIN}"; ID_D="--"
        IS_DASH_INSTALLED=false
    fi
    # Agent
    if check_container_running "nezha-agent"; then
        STATUS_A="${GREEN}● 运行中${PLAIN}"; ID_A=$(docker ps -f name=nezha-agent --format "{{.ID}}")
        IS_AGENT_INSTALLED=true
    elif docker ps -a --format '{{.Names}}' | grep -q "^nezha-agent$"; then
        STATUS_A="${RED}● 已停止${PLAIN}"; ID_A=$(docker ps -a -f name=nezha-agent --format "{{.ID}}")
        IS_AGENT_INSTALLED=true
    else
        STATUS_A="${GRAY}● 未安装${PLAIN}"; ID_A="--"
        IS_AGENT_INSTALLED=false
    fi
}

# --- 核心功能：查看配置 (智能分层) ---
view_config() {
    clear
    IPV4=$(curl -s4m3 https://ip.gs)
    [ -z "$IPV4" ] && IPV4="127.0.0.1"
    
    echo -e " > [ 📋 配置详情中心 ]"
    echo -e " ================================================================"
    
    # --- 主控区块 ---
    echo -e " [ 💻 主控面板 (Master/Dashboard) ]"
    if [ "$IS_DASH_INSTALLED" = true ]; then
        echo -e "   状态     : ${STATUS_D}"
        echo -e "   访问地址 : ${CYAN}http://${IPV4}:${NZ_DASHBOARD_PORT:-$DEFAULT_DASH_PORT}${PLAIN}"
        echo -e "   Web 端口 : ${NZ_DASHBOARD_PORT:-$DEFAULT_DASH_PORT}"
        echo -e "   GRPC端口 : ${NZ_GRPC_PORT:-$DEFAULT_GRPC_PORT}"
        echo -e "   数据目录 : ${BASE_DIR}/dashboard_data"
        echo -e "   管理员   : (首位登录用户自动获得)"
    else
        echo -e "   状态     : ${GRAY}❌ 未安装 (请先执行选项 1 安装)${PLAIN}"
    fi
    
    echo -e " ----------------------------------------------------------------"
    
    # --- 监控区块 ---
    echo -e " [ 🔌 监控端 (Agent/Monitor) ]"
    if [ "$IS_AGENT_INSTALLED" = true ]; then
        echo -e "   状态     : ${STATUS_A}"
        echo -e "   连接目标 : ${CYAN}${NZ_SERVER:-"(未配置)"}${PLAIN}"
        echo -e "   通讯密钥 : ${CYAN}${NZ_TOKEN:-"(未配置)"}${PLAIN}"
        echo -e "   运行模式 : Host Network"
    else
        echo -e "   状态     : ${GRAY}❌ 未安装 (请先执行选项 2 安装)${PLAIN}"
    fi
    
    echo -e " ================================================================"
    read -p " 按回车键返回..."
}

# --- 核心功能：修改配置 (即时生效) ---
edit_config_menu() {
    clear
    echo -e " > [ ⚙️ 修改配置参数 (保存并尝试热重载) ]"
    echo -e "   ------------------------------------------------"
    
    # 根据安装状态显示选项
    if [ "$IS_DASH_INSTALLED" = true ]; then
        echo -e "   1. 修改面板端口 (当前: ${NZ_DASHBOARD_PORT:-$DEFAULT_DASH_PORT})"
    else
        echo -e "   1. 修改面板端口 ${GRAY}(未安装，仅保存配置)${PLAIN}"
    fi
    
    if [ "$IS_AGENT_INSTALLED" = true ]; then
        echo -e "   2. 修改连接IP   (当前: ${NZ_SERVER:-未设置})"
        echo -e "   3. 修改通讯密钥 (当前: ${NZ_TOKEN:-未设置})"
    else
        echo -e "   2. 修改连接IP   ${GRAY}(未安装，仅保存配置)${PLAIN}"
        echo -e "   3. 修改通讯密钥 ${GRAY}(未安装，仅保存配置)${PLAIN}"
    fi
    
    echo -e "   ------------------------------------------------"
    echo -e "   0. 返回"
    read -p " 请输入 [0-3]: " ec
    
    case $ec in
        1) 
           read -p "输入新端口: " np
           if [ -n "$np" ]; then
               NZ_DASHBOARD_PORT=$np
               save_config
               if [ "$IS_DASH_INSTALLED" = true ] && check_container_running "nezha-dashboard"; then
                   echo -e "${YELLOW}正在重启面板以应用配置...${PLAIN}"
                   docker restart nezha-dashboard
                   echo -e "${GREEN}✅ 端口已修改并生效！${PLAIN}"
               else
                   echo -e "${GREEN}✅ 配置已保存 (服务未运行，下次启动生效)${PLAIN}"
               fi
           fi
           ;;
        2) 
           read -p "输入新服务端IP: " nip
           if [ -n "$nip" ]; then
               NZ_SERVER=$nip
               save_config
               if [ "$IS_AGENT_INSTALLED" = true ] && check_container_running "nezha-agent"; then
                   echo -e "${YELLOW}正在重连监控端...${PLAIN}"
                   docker restart nezha-agent
                   echo -e "${GREEN}✅ IP已修改并生效！${PLAIN}"
               else
                   echo -e "${GREEN}✅ 配置已保存 (服务未运行，下次启动生效)${PLAIN}"
               fi
           fi
           ;;
        3) 
           read -p "输入新密钥: " nt
           if [ -n "$nt" ]; then
               NZ_TOKEN=$nt
               save_config
               if [ "$IS_AGENT_INSTALLED" = true ] && check_container_running "nezha-agent"; then
                   echo -e "${YELLOW}正在应用新密钥...${PLAIN}"
                   docker restart nezha-agent
                   echo -e "${GREEN}✅ 密钥已修改并生效！${PLAIN}"
               else
                   echo -e "${GREEN}✅ 配置已保存 (服务未运行，下次启动生效)${PLAIN}"
               fi
           fi
           ;;
        *) return ;;
    esac
    sleep 2
}

# --- 面板安装 ---
install_dashboard() {
    local mode=$1
    if [ "$ENV_SAFE" = false ]; then echo -e "${RED}环境冲突，请先去 [选项11] 清理！${PLAIN}"; sleep 2; return; fi

    echo -e "${GREEN}>>> 正在处理 Dashboard ($mode)...${PLAIN}"
    if [ "$mode" == "install" ]; then
        IPV4=$(curl -s4m3 https://ip.gs)
        read -p "1. 设置面板端口 [默认 $DEFAULT_DASH_PORT]: " input_port
        NZ_DASHBOARD_PORT=${input_port:-$CURRENT_DASH_PORT}
        save_config
    else
        NZ_DASHBOARD_PORT=$CURRENT_DASH_PORT
    fi

    docker rm -f nezha-dashboard 2>/dev/null
    docker pull $IMG_DASHBOARD
    docker run -d --name nezha-dashboard --restart always \
        -p ${NZ_DASHBOARD_PORT}:8008 -p ${NZ_GRPC_PORT}:5555 \
        -v ${BASE_DIR}/dashboard_data:/dashboard/data \
        $IMG_DASHBOARD
        
    if [ "$mode" == "install" ]; then
        echo -e "\n================================================================"
        echo -e "🎉 安装成功！访问地址: ${CYAN}http://${IPV4:-localhost}:${NZ_DASHBOARD_PORT}${PLAIN}"
        echo -e "⚠️  管理员: 首个注册用户自动成为管理员"
        echo -e "================================================================"
        read -p "按回车返回..."
    else
        echo -e "${GREEN}更新完成。${PLAIN}"; sleep 1
    fi
}

menu_dashboard() {
    clear
    echo -e " > [ 🔧 面板管理 ]"
    echo -e "   1. 安装 / 重装"
    echo -e "   2. 平滑更新版本"
    echo -e "   3. 查看日志"
    echo -e "   0. 返回"
    read -p " 请输入: " sd
    case $sd in
        1) install_dashboard "install" ;;
        2) install_dashboard "update" ;;
        3) docker logs -f --tail 50 nezha-dashboard ;;
        *) return ;;
    esac
}

# --- 监控安装 ---
install_agent() {
    local mode=$1
    if [ "$ENV_SAFE" = false ]; then echo -e "${RED}环境冲突，请先去 [选项11] 清理！${PLAIN}"; sleep 2; return; fi
    
    if [ "$mode" == "install" ]; then
        echo -e "${GREEN}>>> 配置监控端...${PLAIN}"
        read -p "1. 面板IP/域名: " input_server
        [ -n "$input_server" ] && NZ_SERVER=$input_server
        read -p "2. 通讯密钥: " input_token
        [ -n "$input_token" ] && NZ_TOKEN=$input_token
        save_config
    fi
    
    if [ -z "$NZ_SERVER" ] || [ -z "$NZ_TOKEN" ]; then
        echo -e "${RED}配置缺失，请先配置！${PLAIN}"; sleep 2; return
    fi
    
    docker rm -f nezha-agent 2>/dev/null
    docker pull $IMG_AGENT
    docker run -d --name nezha-agent --restart always --network host \
        -e Server="${NZ_SERVER}:${NZ_GRPC_PORT}" -e Secret="${NZ_TOKEN}" -e TLS="false" \
        $IMG_AGENT
    echo -e "${GREEN}操作完成。${PLAIN}"; sleep 1
}

menu_agent() {
    clear
    echo -e " > [ 🔧 监控管理 ]"
    echo -e "   1. 安装 / 重装"
    echo -e "   2. 平滑更新版本"
    echo -e "   3. 查看日志"
    echo -e "   0. 返回"
    read -p " 请输入: " sa
    case $sa in
        1) install_agent "install" ;;
        2) install_agent "update" ;;
        3) docker logs -f --tail 50 nezha-agent ;;
        *) return ;;
    esac
}

# --- 卸载清理 ---
menu_cleanup() {
    clear
    echo -e " > [ 🗑️ 卸载与清理 ]"
    echo -e "   1. 卸载本服务 (容器+快捷方式+脚本)"
    echo -e "   2. 清理旧环境 (3X-UI残留/Systemd服务)"
    echo -e "   0. 返回"
    read -p " 请输入: " cc
    case $cc in
        1)
            docker rm -f nezha-dashboard nezha-agent 2>/dev/null
            rm -f "$LINK_PATH"
            read -p "是否删除数据文件? (y/n): " dd
            [ "$dd" == "y" ] && rm -rf "$BASE_DIR"
            rm -f "$SCRIPT_PATH"; exit 0 ;;
        2)
            systemctl stop nezha-dashboard nezha-agent 2>/dev/null
            systemctl disable nezha-dashboard nezha-agent 2>/dev/null
            rm -f /etc/systemd/system/nezha-*.service
            systemctl daemon-reload
            rm -rf /opt/nezha
            killall -9 nezha-dashboard nezha-agent 2>/dev/null
            echo -e "${GREEN}清理完毕。${PLAIN}"; read -p "按回车继续..." ;;
    esac
}

# --- 服务管理 ---
manage_service() {
    local action=$1
    echo -e " > 对谁执行 $action ?"
    echo -e "   1. 面板 (Dashboard)"
    echo -e "   2. 监控 (Agent)"
    echo -e "   3. 全部 (All)"
    read -p " 请输入: " t
    case $t in
        1) svcs="nezha-dashboard";;
        2) svcs="nezha-agent";;
        3) svcs="nezha-dashboard nezha-agent";;
        *) return ;;
    esac
    docker $action $svcs
    echo -e "${GREEN}执行完成。${PLAIN}"; sleep 1
}

# --- 主菜单 ---
show_menu() {
    clear
    check_env_status
    get_system_info
    get_container_status
    
    echo -e " ┌── [ 🖥️ System Info ] ──────────────────────────────────────────────────┐"
    echo -e " │  OS      : $(printf "%-58s" "${OS_INFO:0:58}") │"
    echo -e " │  Kernel  : $(printf "%-30s" "$KERNEL_VER") CPU: $(printf "%-22s" "${KERNEL_VER:0:20}...") │"
    echo -e " │  Res     : Mem ${MEM_BAR} ${MEM_PER}%  | Disk ${DISK_BAR} ${DISK_PER}%                     │"
    echo -e " └─────────────────────────────────────────────────────────────────────────┘"
    echo -e " ┌── [ 🛡️ Environment ] ──────────────────────────────────────────────────┐"
    echo -e " │  Status  : ${ENV_DISPLAY}"
    if [ "$ENV_SAFE" = false ]; then echo -e " │  Conflict: ${RED}${CONFLICT_MSG}${PLAIN}"; fi
    echo -e " └─────────────────────────────────────────────────────────────────────────┘"
    echo -e " ┌── [ 📦 Containers ] ───────────────────────────────────────────────────┐"
    echo -e " │  Dashboard : ${STATUS_D}   (ID: $(printf "%-12s" "$ID_D"))"
    echo -e " │  Agent     : ${STATUS_A}   (ID: $(printf "%-12s" "$ID_A"))"
    echo -e " └─────────────────────────────────────────────────────────────────────────┘"
    
    if [ "$ENV_SAFE" = false ]; then
        echo -e " [ ${RED}🚫 安装锁定 (请选 11 清理)${PLAIN} ]            [ 🔧 服务管理 ]"
    else
        echo -e " [ 🚀 核心组件管理 ]                     [ 🔧 服务管理 ]"
    fi
    echo -e "  1. 面板管理 (Dashboard)               4. 启动服务 (Start)"
    echo -e "  2. 监控管理 (Agent)                   5. 停止服务 (Stop)"
    echo -e "  3. 更新脚本 (Script)                  6. 重启服务 (Restart)"
    echo -e "                                        7. 查看日志 (Logs)"
    echo -e ""
    echo -e " [ ⚙️ 配置中心 ]                        [ 🗑️ 卸载与清理 ]"
    echo -e "  8. 查看详细配置 (View Info)           11. 卸载与清理中心"
    echo -e "  9. 修改配置参数 (Edit Config)         12. 切换语言 (TODO)"
    echo -e ""
    echo -e " ---------------------------------------------------------------------------"
    echo -e "  0. 退出脚本"
    echo -e " ---------------------------------------------------------------------------"
    read -p " 请输入数字 [0-12]: " choice
    case $choice in
        1) menu_dashboard ;;
        2) menu_agent ;;
        3) echo "请手动更新。"; sleep 1 ;;
        4) manage_service "start" ;;
        5) manage_service "stop" ;;
        6) manage_service "restart" ;;
        7) manage_service "logs" ;;
        8) view_config ;;
        9) edit_config_menu ;;
        11) menu_cleanup ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效输入${PLAIN}"; sleep 1 ;;
    esac
}

check_root
install_dependencies
install_shortcut
load_config
while true; do show_menu; done
