#!/bin/bash
# MultiX V7.8 - 凭据特殊字符增强版 (Base64 安全存储)

INSTALL_PATH="/opt/multix_mvp"
ENV_FILE="$INSTALL_PATH/.env"
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

mkdir -p $INSTALL_PATH

# --- 工具函数：安全读写 ---
# 使用 Base64 编码存入，规避 ; ^ = 等特殊字符
safe_write() {
    local key=$1
    local val=$2
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
    [ -z "$raw" ] && echo "" || echo "$raw" | base64 -d
}

# --- 身份检测 ---
IS_MASTER=false
IS_AGENT=false
[ -f "$INSTALL_PATH/master/app.py" ] && IS_MASTER=true
[ -f "$INSTALL_PATH/agent/agent.py" ] && IS_AGENT=true

# --- 服务重启 ---
service_fix() {
    echo -e "${Y}[*] 正在同步并重启服务...${NC}"
    pkill -9 -f app.py 2>/dev/null
    if [ "$IS_MASTER" = true ]; then
        nohup python3 $INSTALL_PATH/master/app.py > /dev/null 2>&1 &
    fi
    if [ "$IS_AGENT" = true ]; then
        docker restart multix-agent 2>/dev/null
    fi
    sleep 2
    echo -e "${G}✅ 动作已完成。${NC}"
}

# --- 档案库 (已修复特殊字符显示) ---
manage_config() {
    clear
    echo -e "${G}=== MultiX V7.8 全凭据管理 ===${NC}"
    if [ ! -f "$ENV_FILE" ]; then echo "无档案"; return; fi
    
    U=$(safe_read "USER")
    P=$(safe_read "PASS")
    T=$(safe_read "TOKEN")
    I=$(safe_read "IP")
    
    echo -e "${Y}[当前配置信息]${NC}"
    echo "----------------------------------"
    echo -e "管理账号: ${G}$U${NC}"
    echo -e "管理密码: ${G}$P${NC}"
    echo -e "通信 Token: ${G}$T${NC}"
    [ ! -z "$I" ] && echo -e "指向主控 IP: ${G}$I${NC}"
    echo "----------------------------------"
    
    echo "1. 修改管理员账号及密码"
    echo "2. 修改通信 Token"
    echo "3. 修改指向 IP (被控端)"
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
    echo -e "${G}>>> 主控端凭据初始化${NC}"
    read -p "设置账号: " M_USER
    read -p "设置密码: " M_PASS
    read -p "设置 Token: " M_TOKEN
    
    # 清空旧档案重新写入
    echo "TYPE=MASTER" > $ENV_FILE
    safe_write "USER" "$M_USER"
    safe_write "PASS" "$M_PASS"
    safe_write "TOKEN" "$M_TOKEN"

    mkdir -p $INSTALL_PATH/master
    # 写入动态 Base64 解码的 Python 逻辑
    cat > $INSTALL_PATH/master/app.py <<EOF
import base64, json, os, subprocess
from flask import Flask, request, session, redirect
from threading import Thread
import websockets

def get_env(key):
    with open('$ENV_FILE', 'r') as f:
        for line in f:
            if line.startswith(key + '='):
                b64 = line.strip().split('=')[1]
                return base64.b64decode(b64).decode()
    return ""

app = Flask(__name__)
app.secret_key = get_env('TOKEN')

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form['u'] == get_env('USER') and request.form['p'] == get_env('PASS'):
            session['logged'] = True
            return redirect('/')
    return '<h3>Login</h3><form method="post"><input name="u"><input name="p" type="password"><button>Go</button></form>'

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return f"<h1>MultiX V7.8 Master</h1><p>Token: {get_env('TOKEN')}</p>"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=7575)
EOF
    service_fix
    IS_MASTER=true
    echo -e "${G}✅ 主控安装成功。${NC}"
    read -p "按回车返回..."
}

# --- 菜单界面 ---
while true; do
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 管理系统 V7.8        "
    echo -e "   [ 特殊字符修复版 | Base64 存储 ]  "
    echo -e "${G}==================================${NC}"
    echo "1. 🚀 安装/重装 主控端"
    echo "2. 📡 安装/重装 被控端"
    echo "----------------------------------"
    echo "3. ⚙️  档案管理 (查看/修改凭据)"
    echo "4. 📊 深度诊断 (链路日志)"
    echo "----------------------------------"
    echo "7. 🔧 强制全局修复"
    echo "9. 🗑️  完全卸载"
    echo "0. 退出"
    read -p "选择: " choice
    case $choice in
        1) install_master ;;
        2) # 这里调用被控逻辑，原理同上，使用 safe_write
           echo "开发中..."; sleep 1 ;;
        3) manage_config ;;
        7) service_fix ;;
        9) rm -rf $INSTALL_PATH; exit 0 ;;
        0) exit 0 ;;
    esac
done
