#!/bin/bash

# ==============================================================================
# 🚀 Server Status Manager (Master & Agent)
# description: 专为面板端和监控端设计的高级运维脚本 (V3.0)
# author: Gemini
# ==============================================================================

# --- 全局配置与颜色定义 ---
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
PLAIN='\033[0m'
BOLD='\033[1m'

# 配置文件路径
CONF_DIR="/opt/server_status"
CONF_FILE="${CONF_DIR}/config.env"
DOCKER_COMPOSE_CMD=""

# 确保目录存在
mkdir -p "$CONF_DIR"

# 默认配置
DEFAULT_DASHBOARD_PORT=8008
DEFAULT_GRPC_PORT=5555
DEFAULT_IMAGE_REPO="ghcr.io/naiba/nezha-dashboard"
DEFAULT_AGENT_IMAGE="ghcr.io/naiba/nezha-agent"

# --- 基础函数 ---

# 检查 Root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：请使用 root 权限运行此脚本！${PLAIN}"
        exit 1
    fi
}

# 检查并安装必要依赖
check_dependencies() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}正在安装 Docker...${PLAIN}"
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker
        systemctl start docker
    fi
    
    local pkgs=("bc" "jq" "curl")
    for pkg in "${pkgs[@]}"; do
        if ! command -v $pkg &> /dev/null; then
            if [ -f /etc/debian_version ]; then
                apt-get update && apt-get install -y $pkg
            elif [ -f /etc/redhat-release ]; then
                yum install -y $pkg
            fi
        fi
    done
}

# 读取/初始化配置
load_config() {
    if [ -f "$CONF_FILE" ]; then
        source "$CONF_FILE"
    else
        # 初始化空配置
        cat > "$CONF_FILE" <<EOF
# Server Status Config
NZ_DASHBOARD_PORT=$DEFAULT_DASHBOARD_PORT
NZ_GRPC_PORT=$DEFAULT_GRPC_PORT
NZ_TOKEN=""
NZ_SERVER=""
EOF
        source "$CONF_FILE"
    fi
}

save_config() {
    cat > "$CONF_FILE" <<EOF
# Server Status Config
NZ_DASHBOARD_PORT=${NZ_DASHBOARD_PORT:-$DEFAULT_DASHBOARD_PORT}
NZ_GRPC_PORT=${NZ_GRPC_PORT:-$DEFAULT_GRPC_PORT}
NZ_TOKEN="${NZ_TOKEN}"
NZ_SERVER="${NZ_SERVER}"
EOF
}

# --- UI 组件 ---

# 进度条生成函数: draw_bar <percent>
draw_bar() {
    local percent=$1
    local total_blocks=10
    local filled_blocks=$(echo "scale=0; $percent * $total_blocks / 100" | bc)
    local empty_blocks=$((total_blocks - filled_blocks))
    
    local bar=""
    for ((i=0; i<filled_blocks; i++)); do bar+="▓"; done
    for ((i=0; i<empty_blocks; i++)); do bar+="░"; done
    
    # 颜色逻辑：>80% 红色，>60% 黄色，其他绿色
    if [ "$percent" -ge 80 ]; then
        echo -e "${RED}[${bar}]${PLAIN}"
    elif [ "$percent" -ge 60 ]; then
        echo -e "${YELLOW}[${bar}]${PLAIN}"
    else
        echo -e "${GREEN}[${bar}]${PLAIN}"
    fi
}

# 获取系统信息
get_system_info() {
    # OS
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        OS_INFO="${PRETTY_NAME}"
    else
        OS_INFO="$(uname -s) $(uname -r)"
    fi
    
    # Kernel & TCP
    KERNEL_VER=$(uname -r)
    TCP_ALG=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    
    # CPU
    CPU_MODEL=$(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    [ -z "$CPU_MODEL" ] && CPU_MODEL="Unknown CPU"
    
    # Uptime
    UPTIME_INFO=$(uptime -p | sed 's/up //')
    
    # Memory
    MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
    if [ "$MEM_TOTAL" -gt 0 ]; then
        MEM_PERCENT=$(echo "$MEM_USED * 100 / $MEM_TOTAL" | bc)
    else
        MEM_PERCENT=0
    fi
    MEM_BAR=$(draw_bar $MEM_PERCENT)
    
    # Swap
    SWAP_TOTAL=$(free -m | awk '/Swap:/ {print $2}')
    SWAP_USED=$(free -m | awk '/Swap:/ {print $3}')
    if [ "$SWAP_TOTAL" -gt 0 ]; then
        SWAP_PERCENT=$(echo "$SWAP_USED * 100 / $SWAP_TOTAL" | bc)
    else
        SWAP_PERCENT=0
    fi
    SWAP_BAR=$(draw_bar $SWAP_PERCENT)
    
    # Disk (Root)
    DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
    DISK_PERCENT=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    DISK_BAR=$(draw_bar $DISK_PERCENT)
}

# 获取容器状态
get_container_status() {
    # Dashboard
    if docker ps | grep -q "nezha-dashboard"; then
        DASH_STATUS="${GREEN}● 运行中${PLAIN}"
        DASH_ID=$(docker ps -f name=nezha-dashboard --format "{{.ID}}")
        DASH_PORT_SHOW="${NZ_DASHBOARD_PORT:-$DEFAULT_DASHBOARD_PORT}"
    else
        DASH_STATUS="${RED}● 已停止${PLAIN}"
        DASH_ID="--"
        DASH_PORT_SHOW="--"
    fi
    
    # Agent
    if docker ps | grep -q "nezha-agent"; then
        AGENT_STATUS="${GREEN}● 运行中${PLAIN}"
        AGENT_ID=$(docker ps -f name=nezha-agent --format "{{.ID}}")
        AGENT_SERVER_SHOW="${NZ_SERVER:-Local}"
    else
        AGENT_STATUS="${RED}● 已停止${PLAIN}"
        AGENT_ID="--"
        AGENT_SERVER_SHOW="--"
    fi
}

# 显示主菜单
show_menu() {
    clear
    get_system_info
    get_container_status
    
    echo -e " ┌── [ 🖥️ System Information ] ──────────────────────────────────────────────┐"
    echo -e " │  OS      : $(printf "%-60s" "$OS_INFO") │"
    echo -e " │  Kernel  : $(printf "%-30s" "$KERNEL_VER") [ TCP: ${TCP_ALG} ]          │"
    echo -e " │  CPU     : $(printf "%-60s" "$CPU_MODEL") │"
    echo -e " │  Uptime  : $(printf "%-60s" "$UPTIME_INFO") │"
    echo -e " ├─────────────────────────────────────────────────────────────────────────┤"
    echo -e " │  Memory  : ${MEM_BAR}  $(printf "%-5s" "$MEM_USED")M / $(printf "%-5s" "$MEM_TOTAL")M ($(printf "%3s" "$MEM_PERCENT")%)                              │"
    echo -e " │  Swap    : ${SWAP_BAR}  $(printf "%-5s" "$SWAP_USED")M / $(printf "%-5s" "$SWAP_TOTAL")M ($(printf "%3s" "$SWAP_PERCENT")%)                              │"
    echo -e " │  Disk    : ${DISK_BAR}  $(printf "%-5s" "$DISK_USED")  / $(printf "%-5s" "$DISK_TOTAL")  ($(printf "%3s" "$DISK_PERCENT")%)                              │"
    echo -e " └─────────────────────────────────────────────────────────────────────────┘"
    echo -e " ┌── [ 📦 Container Status ] ────────────────────────────────────────────────┐"
    echo -e " │  Dashboard (Master) : ${DASH_STATUS}   (ID: $(printf "%-8s" "$DASH_ID"))   端口: $(printf "%-14s" "$DASH_PORT_SHOW")│"
    echo -e " │  Agent     (Client) : ${AGENT_STATUS}   (ID: $(printf "%-8s" "$AGENT_ID"))   Server: $(printf "%-12s" "$AGENT_SERVER_SHOW")│"
    echo -e " └─────────────────────────────────────────────────────────────────────────┘"
    echo -e ""
    echo -e " [ 🚀 安装与更新中心 ]                 [ 🔧 服务运行管理 (含子菜单) ]"
    echo -e "  1. 安装/更新 面板端 (Master)          4. 启动服务 (Start)"
    echo -e "  2. 安装/更新 监控端 (Agent)           5. 停止服务 (Stop)"
    echo -e "  3. 更新本脚本 (Update Script)         6. 重启服务 (Restart)"
    echo -e "                                        7. 查看日志 (Logs)"
    echo -e ""
    echo -e " [ ⚙️ 配置修改 (自动重载) ]            [ 🗑️ 容器与选项 ]"
    echo -e "  8. 修改面板端口 (Port)                11. 删除/卸载 容器"
    echo -e "  9. 修改连接密钥 (Token)               12. 切换语言 (Language)"
    echo -e "  10. 修改服务端IP (Agent Only)"
    echo -e ""
    echo -e " ---------------------------------------------------------------------------"
    echo -e "  0. 退出脚本"
    echo -e " ---------------------------------------------------------------------------"
    read -p " 请输入数字 [0-12]: " choice
    handle_choice $choice
}

# --- 逻辑处理 ---

# 子菜单选择器
select_target_component() {
    echo -e ""
    echo -e " > 请选择操作对象："
    echo -e "   1. 仅面板端 (Dashboard)"
    echo -e "   2. 仅监控端 (Agent)"
    echo -e "   3. 全部 (All)"
    read -p "   请输入 [1-3]: " sub_choice
    echo "$sub_choice"
}

# 服务管理逻辑
manage_service() {
    local action=$1 # start, stop, restart, logs
    local target=$(select_target_component)
    
    case $target in
        1) targets=("nezha-dashboard");;
        2) targets=("nezha-agent");;
        3) targets=("nezha-dashboard" "nezha-agent");;
        *) echo -e "${RED}无效选择${PLAIN}"; return;;
    esac
    
    for container in "${targets[@]}"; do
        if [ "$action" == "logs" ]; then
            echo -e "${YELLOW}正在查看 $container 的最后 20 行日志 (Ctrl+C 退出)...${PLAIN}"
            docker logs -f --tail 20 $container
        else
            echo -e "${YELLOW}正在 $action $container ...${PLAIN}"
            docker $action $container
        fi
    done
    echo -e "${GREEN}操作完成！${PLAIN}"
    read -p "按回车键返回..."
}

# 安装/更新 Dashboard
install_dashboard() {
    echo -e "${GREEN}>>> 开始安装/更新 Dashboard (Master)...${PLAIN}"
    
    # 停止旧的
    docker rm -f nezha-dashboard 2>/dev/null
    
    # 确认端口
    if [ -z "$NZ_DASHBOARD_PORT" ]; then
        read -p "请输入面板访问端口 (默认 8008): " NZ_DASHBOARD_PORT
        NZ_DASHBOARD_PORT=${NZ_DASHBOARD_PORT:-8008}
    fi
    
    save_config
    
    # 拉取并运行
    docker pull $DEFAULT_IMAGE_REPO
    docker run -d \
        --name nezha-dashboard \
        --restart always \
        -p ${NZ_DASHBOARD_PORT}:8008 \
        -p ${NZ_GRPC_PORT}:5555 \
        -v ${CONF_DIR}/dashboard_data:/dashboard/data \
        $DEFAULT_IMAGE_REPO
        
    echo -e "${GREEN}Dashboard 安装完成！访问端口: ${NZ_DASHBOARD_PORT}${PLAIN}"
    read -p "按回车键返回..."
}

# 安装/更新 Agent
install_agent() {
    echo -e "${GREEN}>>> 开始安装/更新 Agent (Client)...${PLAIN}"
    
    # 检查配置
    if [ -z "$NZ_SERVER" ] || [ -z "$NZ_TOKEN" ]; then
        echo -e "${YELLOW}未检测到配置，请先进行配置：${PLAIN}"
        read -p "请输入面板服务器 IP/域名: " NZ_SERVER
        read -p "请输入面板通信端口 (GRPC，默认 5555): " input_grpc
        NZ_GRPC_PORT=${input_grpc:-5555}
        read -p "请输入 Agent 密钥 (Token): " NZ_TOKEN
        save_config
    fi
    
    # 停止旧的
    docker rm -f nezha-agent 2>/dev/null
    
    # 拉取并运行
    docker pull $DEFAULT_AGENT_IMAGE
    docker run -d \
        --name nezha-agent \
        --restart always \
        --network host \
        -e Server="${NZ_SERVER}:${NZ_GRPC_PORT}" \
        -e Secret="${NZ_TOKEN}" \
        -e TLS="false" \
        $DEFAULT_AGENT_IMAGE
        
    echo -e "${GREEN}Agent 安装完成！${PLAIN}"
    read -p "按回车键返回..."
}

# 修改配置
modify_config() {
    local key=$1
    local name=$2
    
    echo -e "${YELLOW}当前 $name: ${!key} ${PLAIN}"
    read -p "请输入新的 $name: " new_val
    if [ -n "$new_val" ]; then
        export $key="$new_val"
        save_config
        echo -e "${GREEN}配置已保存。是否立即重启相关服务以应用更改？(y/n)${PLAIN}"
        read -p "> " confirm
        if [[ "$confirm" == "y" ]]; then
            # 简单粗暴全部重启，确保配置生效
            echo -e "${YELLOW}正在重启容器...${PLAIN}"
            if [[ "$key" == "NZ_DASHBOARD_PORT" ]]; then
                 install_dashboard
            elif [[ "$key" == "NZ_SERVER" || "$key" == "NZ_TOKEN" ]]; then
                 install_agent
            fi
        fi
    fi
}

# 删除容器
delete_containers() {
    local target=$(select_target_component)
    case $target in
        1) docker rm -f nezha-dashboard;;
        2) docker rm -f nezha-agent;;
        3) docker rm -f nezha-dashboard nezha-agent;;
    esac
    echo -e "${GREEN}删除完成。${PLAIN}"
    read -p "按回车键返回..."
}

# 主处理逻辑
handle_choice() {
    case $1 in
        1) install_dashboard ;;
        2) install_agent ;;
        3) 
            echo -e "${YELLOW}正在拉取最新脚本...${PLAIN}"
            wget -O $0 https://raw.githubusercontent.com/your-repo/script.sh && chmod +x $0 && ./$0
            exit 0
            ;;
        4) manage_service "start" ;;
        5) manage_service "stop" ;;
        6) manage_service "restart" ;;
        7) manage_service "logs" ;;
        8) modify_config "NZ_DASHBOARD_PORT" "面板端口" ;;
        9) modify_config "NZ_TOKEN" "连接密钥 (Token)" ;;
        10) modify_config "NZ_SERVER" "服务端 IP" ;;
        11) delete_containers ;;
        12) echo -e "${YELLOW}功能开发中...${PLAIN}"; sleep 1 ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效输入${PLAIN}"; sleep 1 ;;
    esac
}

# --- 脚本入口 ---
check_root
check_dependencies
load_config

while true; do
    show_menu
done
