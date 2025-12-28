#!/bin/bash

# ==============================================================================
# 🚀 MultiX - Nezha Server Status Manager (Docker Edition)
# Description: 面板与监控端的一站式运维管理工具
# Version: 3.5.0 (Final)
# Author: Gemini
# ==============================================================================

# --- 全局配置与颜色定义 ---
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
PLAIN='\033[0m'

# 基础目录与配置
BASE_DIR="/opt/multix"
CONF_FILE="${BASE_DIR}/config.env"
SCRIPT_PATH="${BASE_DIR}/manager.sh"
LINK_PATH="/usr/bin/multix"

# 默认镜像与配置
IMG_DASHBOARD="ghcr.io/naiba/nezha-dashboard"
IMG_AGENT="ghcr.io/naiba/nezha-agent"
DEFAULT_DASH_PORT=8008
DEFAULT_GRPC_PORT=5555

# 确保基础目录存在
mkdir -p "$BASE_DIR"

# --- 基础工具函数 ---

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：请使用 root 权限运行此脚本！${PLAIN}"
        exit 1
    fi
}

install_dependencies() {
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}检测到未安装 Docker，正在自动安装...${PLAIN}"
        if [ -f /etc/debian_version ]; then
            apt-get update && apt-get install -y curl
        elif [ -f /etc/redhat-release ]; then
            yum install -y curl
        fi
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker
        systemctl start docker
    fi

    # 检查 bc (用于进度条计算)
    if ! command -v bc &> /dev/null; then
        if [ -f /etc/debian_version ]; then
            apt-get install -y bc
        elif [ -f /etc/redhat-release ]; then
            yum install -y bc
        fi
    fi
}

install_shortcut() {
    # 将当前脚本复制到标准目录并创建软连接
    if [ "$0" != "$SCRIPT_PATH" ]; then
        cp "$0" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
    fi
    
    if [ ! -L "$LINK_PATH" ] || [ "$(readlink "$LINK_PATH")" != "$SCRIPT_PATH" ]; then
        ln -sf "$SCRIPT_PATH" "$LINK_PATH"
        # echo -e "${GREEN}快捷指令 'multix' 已创建！${PLAIN}"
    fi
}

load_config() {
    if [ -f "$CONF_FILE" ]; then
        source "$CONF_FILE"
    else
        cat > "$CONF_FILE" <<EOF
# MultiX Config
NZ_DASHBOARD_PORT=$DEFAULT_DASH_PORT
NZ_GRPC_PORT=$DEFAULT_GRPC_PORT
NZ_SERVER=""
NZ_TOKEN=""
EOF
        source "$CONF_FILE"
    fi
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

# --- 核心检测逻辑 ---

# 进度条生成: draw_bar <percent>
draw_bar() {
    local percent=$1
    local total=10
    # 防止 bc 缺失报错，兜底逻辑
    if ! command -v bc &> /dev/null; then
        echo "[${percent}%]"
        return
    fi
    local filled=$(echo "scale=0; $percent * $total / 100" | bc)
    local empty=$((total - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="▓"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    
    if [ "$percent" -ge 80 ]; then
        echo -e "${RED}[${bar}]${PLAIN}"
    elif [ "$percent" -ge 60 ]; then
        echo -e "${YELLOW}[${bar}]${PLAIN}"
    else
        echo -e "${GREEN}[${bar}]${PLAIN}"
    fi
}

# 环境冲突检测
check_env_status() {
    CONFLICT_MSG=""
    ENV_SAFE=true
    
    # 1. 检测 Systemd 服务残留
    if systemctl is-active --quiet nezha-dashboard || [ -f /etc/systemd/system/nezha-dashboard.service ]; then
        ENV_SAFE=false
        CONFLICT_MSG+="[Systemd:nezha-dashboard] "
    fi
    if systemctl is-active --quiet nezha-agent || [ -f /etc/systemd/system/nezha-agent.service ]; then
        ENV_SAFE=false
        CONFLICT_MSG+="[Systemd:nezha-agent] "
    fi

    # 2. 检测非本工具管理的 Docker 容器 (同名冲突)
    # 这里的逻辑是：如果容器存在，但不是用本脚本的标准方式启动的（这里简化为检查是否存在，如果存在且已停止也算占用）
    # 实际上，只要 Docker 容器名已存在，install 函数就会报错，所以这里只重点报 Systemd 的错
    
    if [ "$ENV_SAFE" = true ]; then
        ENV_DISPLAY="${GREEN}✅ 通过 (无残留)${PLAIN}"
    else
        ENV_DISPLAY="${RED}❌ 警告 (发现冲突)${PLAIN}"
    fi
}

get_system_info() {
    # 简单获取各类信息
    KERNEL_VER=$(uname -r)
    OS_INFO=$(grep PRETTY_NAME /etc/os-release | cut -d '"' -f 2)
    UPTIME_INFO=$(uptime -p | sed 's/up //')
    CPU_MODEL=$(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    [ -z "$CPU_MODEL" ] && CPU_MODEL="Unknown"
    
    # 内存
    MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
    MEM_PER=0
    [ "$MEM_TOTAL" -gt 0 ] && MEM_PER=$(awk "BEGIN {print int($MEM_USED/$MEM_TOTAL*100)}")
    MEM_BAR=$(draw_bar $MEM_PER)
    
    # Swap
    SWAP_TOTAL=$(free -m | awk '/Swap:/ {print $2}')
    SWAP_USED=$(free -m | awk '/Swap:/ {print $3}')
    SWAP_PER=0
    [ "$SWAP_TOTAL" -gt 0 ] && SWAP_PER=$(awk "BEGIN {print int($SWAP_USED/$SWAP_TOTAL*100)}")
    SWAP_BAR=$(draw_bar $SWAP_PER)
    
    # 磁盘 (根目录)
    DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
    DISK_PER=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    DISK_BAR=$(draw_bar $DISK_PER)
}

get_container_status() {
    # Dashboard
    if docker ps --format '{{.Names}}' | grep -q "^nezha-dashboard$"; then
        STATUS_D="${GREEN}● 运行中${PLAIN}"
        ID_D=$(docker ps -f name=nezha-dashboard --format "{{.ID}}")
        PORT_D="${NZ_DASHBOARD_PORT:-$DEFAULT_DASH_PORT}"
    elif docker ps -a --format '{{.Names}}' | grep -q "^nezha-dashboard$"; then
        STATUS_D="${RED}● 已停止${PLAIN}"
        ID_D=$(docker ps -a -f name=nezha-dashboard --format "{{.ID}}")
        PORT_D="${NZ_DASHBOARD_PORT:-$DEFAULT_DASH_PORT}"
    else
        STATUS_D="${PLAIN}● 未安装${PLAIN}"
        ID_D="--"
        PORT_D="--"
    fi
    
    # Agent
    if docker ps --format '{{.Names}}' | grep -q "^nezha-agent$"; then
        STATUS_A="${GREEN}● 运行中${PLAIN}"
        ID_A=$(docker ps -f name=nezha-agent --format "{{.ID}}")
        SERVER_A="${NZ_SERVER:-Local}"
    elif docker ps -a --format '{{.Names}}' | grep -q "^nezha-agent$"; then
        STATUS_A="${RED}● 已停止${PLAIN}"
        ID_A=$(docker ps -a -f name=nezha-agent --format "{{.ID}}")
        SERVER_A="${NZ_SERVER:-Local}"
    else
        STATUS_A="${PLAIN}● 未安装${PLAIN}"
        ID_A="--"
        SERVER_A="--"
    fi
}

# --- 菜单 UI ---

show_menu() {
    clear
    check_env_status
    get_system_info
    get_container_status
    
    echo -e " ┌── [ 🖥️ System Information ] ──────────────────────────────────────────────┐"
    echo -e " │  OS      : $(printf "%-58s" "$OS_INFO") │"
    echo -e " │  Kernel  : $(printf "%-30s" "$KERNEL_VER") CPU: $(printf "%-22s" "${CPU_MODEL:0:20}...") │"
    echo -e " │  Res     : Mem ${MEM_BAR} ${MEM_PER}%  | Swap ${SWAP_BAR} ${SWAP_PER}% | Disk ${DISK_BAR} ${DISK_PER}%     │"
    echo -e " └─────────────────────────────────────────────────────────────────────────┘"
    echo -e " ┌── [ 🛡️ Environment Status ] ──────────────────────────────────────────────┐"
    echo -e " │  检测结果 : ${ENV_DISPLAY}"
    if [ "$ENV_SAFE" = false ]; then
        echo -e " │  详情提示 : ${RED}${CONFLICT_MSG}${PLAIN}"
    fi
    echo -e " └─────────────────────────────────────────────────────────────────────────┘"
    echo -e " ┌── [ 📦 Container Status ] ────────────────────────────────────────────────┐"
    echo -e " │  Dashboard : ${STATUS_D}   (ID: $(printf "%-12s" "$ID_D"))   端口: $(printf "%-14s" "$PORT_D")│"
    echo -e " │  Agent     : ${STATUS_A}   (ID: $(printf "%-12s" "$ID_A"))   Server: $(printf "%-12s" "$SERVER_A")│"
    echo -e " └─────────────────────────────────────────────────────────────────────────┘"
    echo -e ""
    
    # 如果环境有冲突，锁定安装选项的显示（视觉上加括号警告）
    if [ "$ENV_SAFE" = false ]; then
        echo -e " [ ${RED}🚫 安装已被锁定 (请先执行 11 清理)${PLAIN} ]      [ 🔧 服务管理 ]"
    else
        echo -e " [ 🚀 安装与更新 ]                       [ 🔧 服务管理 ]"
    fi
    
    echo -e "  1. 安装/更新 面板端 (Master)          4. 启动服务 (Start)"
    echo -e "  2. 安装/更新 监控端 (Agent)           5. 停止服务 (Stop)"
    echo -e "  3. 更新本脚本                         6. 重启服务 (Restart)"
    echo -e "                                        7. 查看日志 (Logs)"
    echo -e ""
    echo -e " [ ⚙️ 配置管理 ]                       [ 🗑️ 卸载与清理 ]"
    echo -e "  8. 修改面板端口                       11. 卸载与清理中心"
    echo -e "  9. 修改连接密钥                       12. 切换语言 (TODO)"
    echo -e "  10. 修改服务端IP"
    echo -e ""
    echo -e " ---------------------------------------------------------------------------"
    echo -e "  0. 退出脚本"
    echo -e " ---------------------------------------------------------------------------"
    
    if [ "$ENV_SAFE" = false ]; then
        echo -e " ${RED}⚠️  检测到环境冲突，请先输入 [11] -> [2] 清理旧环境！${PLAIN}"
    fi
    read -p " 请输入数字 [0-12]: " choice
    handle_choice $choice
}

# --- 核心逻辑 ---

select_target() {
    echo -e "\n > 请选择目标："
    echo -e "   1. 面板端 (Dashboard)"
    echo -e "   2. 监控端 (Agent)"
    echo -e "   3. 全部 (All)"
    read -p "   请输入 [1-3]: " t
    echo "$t"
}

manage_service() {
    local action=$1
    local target=$(select_target)
    case $target in
        1) svcs="nezha-dashboard";;
        2) svcs="nezha-agent";;
        3) svcs="nezha-dashboard nezha-agent";;
        *) return;;
    esac
    
    for s in $svcs; do
        if [ "$action" == "logs" ]; then
            echo -e "${YELLOW}查看 $s 最后20行日志 (Ctrl+C退出)...${PLAIN}"
            docker logs -f --tail 20 $s
        else
            echo -e "${YELLOW}正在 $action $s ...${PLAIN}"
            docker $action $s
        fi
    done
    read -p "按回车继续..."
}

install_dashboard() {
    if [ "$ENV_SAFE" = false ]; then
        echo -e "${RED}错误：环境冲突，请先执行清理！${PLAIN}"; sleep 2; return
    fi

    echo -e "${GREEN}>>> 准备安装 Dashboard...${PLAIN}"
    [ -z "$NZ_DASHBOARD_PORT" ] && read -p "设置面板端口 (默认8008): " NZ_DASHBOARD_PORT
    NZ_DASHBOARD_PORT=${NZ_DASHBOARD_PORT:-$DEFAULT_DASH_PORT}
    save_config
    
    docker rm -f nezha-dashboard 2>/dev/null
    docker pull $IMG_DASHBOARD
    docker run -d \
        --name nezha-dashboard \
        --restart always \
        -p ${NZ_DASHBOARD_PORT}:8008 \
        -p ${NZ_GRPC_PORT}:5555 \
        -v ${BASE_DIR}/dashboard_data:/dashboard/data \
        $IMG_DASHBOARD
        
    echo -e "${GREEN}安装完成！${PLAIN}"; read -p "按回车继续..."
}

install_agent() {
    if [ "$ENV_SAFE" = false ]; then
        echo -e "${RED}错误：环境冲突，请先执行清理！${PLAIN}"; sleep 2; return
    fi
    
    echo -e "${GREEN}>>> 准备安装 Agent...${PLAIN}"
    if [ -z "$NZ_SERVER" ] || [ -z "$NZ_TOKEN" ]; then
        read -p "输入面板IP/域名: " NZ_SERVER
        read -p "输入连接密钥: " NZ_TOKEN
        save_config
    fi
    
    docker rm -f nezha-agent 2>/dev/null
    docker pull $IMG_AGENT
    docker run -d \
        --name nezha-agent \
        --restart always \
        --network host \
        -e Server="${NZ_SERVER}:${NZ_GRPC_PORT}" \
        -e Secret="${NZ_TOKEN}" \
        -e TLS="false" \
        $IMG_AGENT
        
    echo -e "${GREEN}安装完成！${PLAIN}"; read -p "按回车继续..."
}

modify_config() {
    local key=$1
    local txt=$2
    echo -e "${YELLOW}当前 $txt: ${!key} ${PLAIN}"
    read -p "请输入新值: " val
    if [ -n "$val" ]; then
        export $key="$val"
        save_config
        echo -e "${GREEN}配置已保存，正在重启服务以生效...${PLAIN}"
        docker restart nezha-dashboard nezha-agent 2>/dev/null
        sleep 1
    fi
}

menu_cleanup() {
    clear
    echo -e " > [ 🗑️ 卸载与清理 ]"
    echo -e "   ----------------------------------------------------------------"
    echo -e "   1. 卸载本服务 (Uninstall All)"
    echo -e "      [范围] 容器 + 快捷指令(multix) + 脚本文件 + (可选:数据)"
    echo -e "      [结果] 彻底清除本工具在系统中的痕迹。"
    echo -e ""
    echo -e "   2. 清理旧环境 (Fix Conflicts)"
    echo -e "      [范围] 系统中残留的旧版 3X 服务、Systemd、进程。"
    echo -e "      [结果] 修复环境检测红字，为安装本工具铺路。"
    echo -e "   ----------------------------------------------------------------"
    echo -e "   0. 返回主菜单"
    echo -e ""
    read -p " 请输入 [0-2]: " c_choice
    
    case $c_choice in
        1)
            echo -e "${YELLOW}正在删除容器...${PLAIN}"
            docker rm -f nezha-dashboard nezha-agent 2>/dev/null
            echo -e "${YELLOW}正在删除快捷指令...${PLAIN}"
            rm -f "$LINK_PATH"
            
            echo -e "${YELLOW}是否同时删除配置文件和数据? (y/n)${PLAIN}"
            read -p "> " del_data
            if [ "$del_data" == "y" ]; then
                rm -rf "$BASE_DIR"
                echo -e "${GREEN}数据已删除。${PLAIN}"
            else
                # 如果不删数据，但脚本要自删，需要确保脚本不是唯一的
                echo -e "${YELLOW}数据已保留在 $BASE_DIR ${PLAIN}"
            fi
            
            echo -e "${GREEN}卸载完成。脚本将自我删除。再见！${PLAIN}"
            rm -f "$SCRIPT_PATH"
            exit 0
            ;;
        2)
            echo -e "${YELLOW}正在停止旧版 Systemd 服务...${PLAIN}"
            systemctl stop nezha-dashboard nezha-agent 2>/dev/null
            systemctl disable nezha-dashboard nezha-agent 2>/dev/null
            rm -f /etc/systemd/system/nezha-dashboard.service /etc/systemd/system/nezha-agent.service
            systemctl daemon-reload
            
            echo -e "${YELLOW}正在清理旧版文件 (/opt/nezha)...${PLAIN}"
            rm -rf /opt/nezha
            rm -f /usr/local/bin/nezha-agent
            
            echo -e "${YELLOW}正在强制结束残留进程...${PLAIN}"
            killall -9 nezha-dashboard 2>/dev/null
            killall -9 nezha-agent 2>/dev/null
            
            echo -e "${GREEN}旧环境清理完毕！${PLAIN}"
            read -p "按回车重新检测..."
            ;;
    esac
}

handle_choice() {
    case $1 in
        1) install_dashboard ;;
        2) install_agent ;;
        3) 
            echo -e "${YELLOW}更新功能暂未对接远程源，请手动下载覆盖。${PLAIN}"
            sleep 1 
            ;;
        4) manage_service "start" ;;
        5) manage_service "stop" ;;
        6) manage_service "restart" ;;
        7) manage_service "logs" ;;
        8) modify_config "NZ_DASHBOARD_PORT" "面板端口" ;;
        9) modify_config "NZ_TOKEN" "连接密钥" ;;
        10) modify_config "NZ_SERVER" "服务端IP" ;;
        11) menu_cleanup ;;
        12) echo "Coming soon..."; sleep 1 ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效输入${PLAIN}"; sleep 1 ;;
    esac
}

# --- 入口 ---
check_root
install_dependencies
install_shortcut
load_config

while true; do
    show_menu
done
