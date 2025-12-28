#!/bin/bash

# ==========================================
# MultiX Panel - 分布式节点管理系统 (被控端)
# GitHub 托管版 (v2.1 提示语修正)
# ==========================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

# 配置文件路径
CONFIG_FILE="/etc/multix/node_config.json"
KEY_FILE="/etc/multix/node_key.txt"

# !!! 关键设置 !!!
GITHUB_RAW_URL="https://raw.githubusercontent.com/Vincentkeio/multix-panel/main/multix.sh"

# 检查 root
[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 用户运行此脚本！${PLAIN}" && exit 1

# ==========================================
# 0. 快捷指令安装
# ==========================================
install_shortcut() {
    if [ ! -f "/usr/bin/multix" ]; then
        echo -e "${YELLOW}正在安装 multix 快捷指令...${PLAIN}"
        curl -s -o /usr/bin/multix "$GITHUB_RAW_URL"
        chmod +x /usr/bin/multix
        
        if [ -f "/usr/bin/multix" ]; then
            echo -e "${GREEN}快捷指令 'multix' 安装成功！${PLAIN}"
        else
            echo -e "${RED}快捷指令安装失败，请检查 GITHUB_RAW_URL 设置。${PLAIN}"
        fi
    fi
}

# ==========================================
# 1. 基础环境与状态检测
# ==========================================
check_status() {
    if systemctl is-active x-ui &>/dev/null; then
        XUI_STATUS="${GREEN}运行中${PLAIN}"
    elif [ -f "/usr/local/x-ui/x-ui" ]; then
        XUI_STATUS="${YELLOW}已安装但未运行${PLAIN}"
    else
        XUI_STATUS="${RED}未安装${PLAIN}"
    fi

    if [ -f "$KEY_FILE" ]; then
        KEY_STATUS="${GREEN}已配置${PLAIN}"
    else
        KEY_STATUS="${RED}未配置${PLAIN}"
    fi
}

install_dependencies() {
    local CMD=""
    if [ -f /etc/debian_version ]; then
        CMD="apt-get update -y && apt-get install -y curl jq sqlite3 openssl net-tools"
    elif [ -f /etc/redhat-release ]; then
        CMD="yum update -y && yum install -y curl jq sqlite3 openssl net-tools"
    fi
    eval "$CMD" >/dev/null 2>&1
    mkdir -p /etc/multix
}

# ==========================================
# 2. 核心部署逻辑
# ==========================================
deploy_node() {
    install_dependencies

    # --- 网络选择 (提示语修正版) ---
    echo -e "${YELLOW}正在探测本机公网 IP...${PLAIN}"
    IPV4=$(curl -4 -s --connect-timeout 3 ifconfig.co)
    IPV6=$(curl -6 -s --connect-timeout 3 ifconfig.co)
    FINAL_IP=""

    if [[ -n "$IPV4" && -n "$IPV6" ]]; then
        echo -e "${GREEN}检测到双栈网络 (Dual Stack)${PLAIN}"
        echo -e "${YELLOW}请选择 Master 连接此节点时使用的通道 (将写入Key):${PLAIN}"
        echo -e " 1. 使用 IPv4 通道 (${BLUE}${IPV4}${PLAIN}) - 兼容性好"
        echo -e " 2. 使用 IPv6 通道 (${BLUE}${IPV6}${PLAIN}) - 穿透性好(推荐NAT机)"
        read -p "请选择 [1/2] (默认1): " CHOICE
        [[ "$CHOICE" == "2" ]] && FINAL_IP="$IPV6" || FINAL_IP="$IPV4"
    elif [[ -n "$IPV4" ]]; then
        echo -e "${GREEN}自动选择 IPv4 作为隧道入口。${PLAIN}"
        FINAL_IP="$IPV4"
    elif [[ -n "$IPV6" ]]; then
        echo -e "${GREEN}自动选择 IPv6 作为隧道入口。${PLAIN}"
        FINAL_IP="$IPV6"
    else
        echo -e "${RED}无法获取公网IP，请检查网络。${PLAIN}" && return
    fi

    # --- 3X-UI 安装/配置 ---
    echo -e "${YELLOW}正在配置 3X-UI...${PLAIN}"
    if ! command -v x-ui &> /dev/null; then
        bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) -y >/dev/null 2>&1
    fi
    
    PANEL_USER="admin_$(openssl rand -hex 3)"
    PANEL_PASS="pass_$(openssl rand -hex 6)"
    PANEL_PORT=$(shuf -i 10000-60000 -n 1)
    
    /usr/local/x-ui/x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS" -port "$PANEL_PORT" >/dev/null 2>&1
    /usr/local/x-ui/x-ui restart >/dev/null 2>&1

    # --- 隧道与密钥 ---
    echo -e "${YELLOW}正在配置加密隧道...${PLAIN}"
    TUNNEL_USER="node_tunnel"
    id "$TUNNEL_USER" &>/dev/null || useradd -m -s /sbin/nologin $TUNNEL_USER
    
    USER_HOME="/home/$TUNNEL_USER"
    mkdir -p "$USER_HOME/.ssh" && chmod 700 "$USER_HOME/.ssh"
    rm -f "$USER_HOME/.ssh/id_rsa" "$USER_HOME/.ssh/id_rsa.pub"
    ssh-keygen -t rsa -b 2048 -f "$USER_HOME/.ssh/id_rsa" -N "" -q
    cat "$USER_HOME/.ssh/id_rsa.pub" > "$USER_HOME/.ssh/authorized_keys"
    chmod 600 "$USER_HOME/.ssh/authorized_keys"
    chown -R $TUNNEL_USER:$TUNNEL_USER "$USER_HOME/.ssh"
    
    PRIVATE_KEY=$(cat "$USER_HOME/.ssh/id_rsa")
    SSH_PORT=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}' | head -n 1)
    [[ -z "$SSH_PORT" ]] && SSH_PORT=22

    # --- 生成并保存 Key ---
    JSON_DATA=$(jq -n \
                  --arg ip "$FINAL_IP" \
                  --arg ssh_port "$SSH_PORT" \
                  --arg ssh_user "$TUNNEL_USER" \
                  --arg ssh_key "$PRIVATE_KEY" \
                  --arg target_port "$PANEL_PORT" \
                  --arg panel_user "$PANEL_USER" \
                  --arg panel_pass "$PANEL_PASS" \
                  '{ip: $ip, ssh_port: $ssh_port, ssh_user: $ssh_user, ssh_key: $ssh_key, target_port: $target_port, panel_user: $panel_user, panel_pass: $panel_pass}')

    NODE_KEY=$(echo -n "$JSON_DATA" | base64 -w 0)
    
    echo "$NODE_KEY" > "$KEY_FILE"
    echo -e "${GREEN}部署完成！Key 已保存。${PLAIN}"
    
    show_key
}

# ==========================================
# 3. 显示 Key
# ==========================================
show_key() {
    if [ ! -f "$KEY_FILE" ]; then
        echo -e "${RED}错误: 尚未部署，请先执行部署操作。${PLAIN}"
        return
    fi
    KEY=$(cat "$KEY_FILE")
    echo -e ""
    echo -e "${GREEN}====== 您的节点 Key (复制下方内容) ======${PLAIN}"
    echo -e "${YELLOW}${KEY}${PLAIN}"
    echo -e "${GREEN}=========================================${PLAIN}"
}

# ==========================================
# 4. 主菜单
# ==========================================
show_menu() {
    clear
    install_shortcut
    check_status
    echo -e "MultiX Panel 节点管理脚本 ${BLUE}v2.1 (GitHub版)${PLAIN}"
    echo -e "--------------------------------"
    echo -e "3X-UI状态: ${XUI_STATUS}"
    echo -e "节点配置:  ${KEY_STATUS}"
    echo -e "--------------------------------"
    echo -e " 1. 🚀 一键部署 / 重置配置"
    echo -e " 2. 🔑 查看当前 Key"
    echo -e " 3. 🗑️ 卸载脚本与清理用户"
    echo -e " 0. 退出"
    echo -e "--------------------------------"
    read -p "请选择操作 [0-3]: " num

    case "$num" in
        1) deploy_node ;;
        2) show_key ;;
        3) 
            userdel -r node_tunnel 2>/dev/null
            rm -rf /etc/multix /usr/bin/multix
            echo -e "${GREEN}清理完成。${PLAIN}"
            ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入错误${PLAIN}" ;;
    esac
}

show_menu
