#!/bin/bash
# MultiX V8.0 - 工业级旗舰版 (双模兼容 + 特殊字符深度支持)

INSTALL_PATH="/opt/multix_mvp"
ENV_FILE="$INSTALL_PATH/.env"
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

mkdir -p $INSTALL_PATH

# --- 核心函数：安全读写 (兼容旧明文) ---
safe_write() {
    local key=$1
    local val=$2
    # 编码为 Base64 存储以屏蔽 ; ^ = 等字符的影响
    local b64_val=$(echo -n "$val" | base64 | tr -d '\n')
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${b64_val}|" "$ENV_FILE"
    else
        echo "${key}=${b64_val}" >> "$ENV_FILE"
    fi
}

safe_read() {
    local key=$1
    local raw=$(grep "^${key}=" "$ENV_FILE" | cut -d'=' -f2)
    [ -z "$raw" ] && return
    # 智能判断：如果 Base64 解码报错，则说明是旧明文，直接返回原值并修复为 Base64
    if echo "$raw" | base64 -d &>/dev/null; then
        echo "$raw" | base64 -d
    else
        echo "$raw"
        safe_write "$key" "$raw" # 自动后台修复为 Base64 格式
    fi
}

# --- 身份感知 ---
IS_MASTER=false
IS_AGENT=false
[ -f "$INSTALL_PATH/master/app.py" ] && IS_MASTER=true
[ -f "$INSTALL_PATH/agent/agent.py" ] && IS_AGENT=true

# --- 智能修复 ---
service_fix() {
    echo -e "${Y}[*] 执行全局同步自愈...${NC}"
    pkill -9 -f app.py
    fuser -k 7575/tcp 8888/tcp 2>/dev/null
    [ "$IS_MASTER" = true ] && nohup python3 $INSTALL_PATH/master/app.py > /dev/null 2>&1 &
    [ "$IS_AGENT" = true ] && docker restart multix-agent 2>/dev/null
    sleep 2
    echo -e "${G}✅ 修复完成。${NC}"
}

# --- 档案管理 (修复 Base64 报错) ---
manage_config() {
    clear
    echo -e "${G}=== MultiX V8.0 全凭据管理 ===${NC}"
    if [ ! -f "$ENV_FILE" ]; then echo "档案空"; return; fi
    
    local U=$(safe_read "USER")
    local P=$(safe_read "PASS")
    local T=$(safe_read "TOKEN")
    local I=$(safe_read "IP")
    
    echo -e "${Y}[当前配置信息]${NC}"
    echo "----------------------------------"
    echo -e "管理账号: ${G}${U}${NC}"
    echo -e "管理密码: ${G}${P}${NC}"
    echo -e "通信 Token: ${G}${T}${NC}"
    [ ! -z "$I" ] && echo -e "指向主控: ${G}${I}${NC}"
    echo "----------------------------------"
    
    echo "1. 修改管理员账号及密码"
    echo "2. 修改通信 Token"
    echo "3. 修改主控 IP (被控端)"
    echo "0. 返回"
    read -p "选择: " sub_c
    
    case $sub_c in
        1) read -p "新账号: " nu; read -p "新密码: " np
           [ ! -z "$nu" ] && safe_write "USER" "$nu"
           [ ! -z "$np" ] && safe_write "PASS" "$np" ;;
        2) read -p "新 Token: " nt
           [ ! -z "$nt" ] && safe_write "TOKEN" "$nt" ;;
        3) read -p "新主控 IP: " ni
           [ ! -z "$ni" ] && safe_write "IP" "$ni" ;;
    esac
    service_fix
}

# --- 主控安装 ---
install_master() {
    clear
    echo -e "${G}>>> 主控端旗舰安装${NC}"
    read -p "设置账号: " M_USER
    read -p "设置密码: " M_PASS
    M_TOKEN=$(openssl rand -hex 12)
    read -p "通信 Token [$M_TOKEN]: " M_TOKEN
    M_TOKEN=${M_TOKEN:-$M_TOKEN}

    echo "TYPE=MASTER" > $ENV_FILE
    safe_write "USER" "$M_USER"
    safe_write "PASS" "$M_PASS"
    safe_write "TOKEN" "$M_TOKEN"

    # Python 脚本动态读取 Base64 档案
    cat > $INSTALL_PATH/master/app.py <<'EOF'
import base64, json, os
from flask import Flask, request, session, redirect, render_template_string
from threading import Thread

def get_conf(key):
    try:
        with open('/opt/multix_mvp/.env', 'r') as f:
            for line in f:
                if line.startswith(key + '='):
                    val = line.strip().split('=')[1]
                    return base64.b64decode(val).decode()
    except: pass
    return ""

app = Flask(__name__)
app.secret_key = get_conf('TOKEN')

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form['u'] == get_conf('USER') and request.form['p'] == get_conf('PASS'):
            session['logged'] = True
            return redirect('/')
    return '<h3>Login</h3><form method="post">U: <input name="u"> P: <input name="p" type="password"><button>Login</button></form>'

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return f"<h1>MultiX V8.0 Master</h1><p>Active Token: {get_conf('TOKEN')}</p>"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=7575)
EOF
    service_fix
    echo -e "${G}✅ 主控安装完成。${NC}"
    read -p "回车继续..."
}

# --- 菜单逻辑 ---
while true; do
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 管理系统 V8.0        "
    echo -e "   [ 工业级稳定版 | 凭据自修复 ]     "
    echo -e "${G}==================================${NC}"
    echo "1. 🚀 安装/重装 主控端"
    echo "2. 📡 安装/重装 被控端"
    echo "----------------------------------"
    echo "3. ⚙️  档案库 (查看与一键修改凭据)"
    echo "4. 📊 深度诊断 (链路解析与实时日志)"
    echo "----------------------------------"
    echo "7. ⚡ 同步配置并重启自愈"
    echo "9. 🗑️  完全卸载"
    echo "0. 退出"
    read -p "选择: " choice
    case $choice in
        1) install_master ;;
        2) # 这里调用被控逻辑，略
           echo "安装被控端..."; sleep 1 ;;
        3) manage_config ;;
        4) # 调用诊断逻辑，略
           echo "诊断中..."; sleep 1 ;;
        7) service_fix ;;
        9) rm -rf $INSTALL_PATH; exit 0 ;;
        0) exit 0 ;;
    esac
done
