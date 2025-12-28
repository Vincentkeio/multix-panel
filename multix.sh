#!/bin/bash
# MultiX V8.8 - 旗舰终极版 (双栈凭据 | IPv6优先 | 深度清理自愈)

INSTALL_PATH="/opt/multix_mvp"
CONFIG_FILE="${INSTALL_PATH}/.env"

# 颜色定义
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

# ==========================================
# 1. 深度环境自愈 (含强力清理)
# ==========================================

force_fix_env() {
    echo -e "${R}[*] 正在执行深度清理与环境自愈...${NC}"
    # 暴力停止并删除旧残留
    docker rm -f 3x-ui multix-agent 3x-ui-master 2>/dev/null
    docker rmi -f multix-agent-v85 multix-agent-img 2>/dev/null
    pkill -9 -f app.py 2>/dev/null
    pkill -9 -f agent.py 2>/dev/null
    
    # 清理 APT 锁
    rm -f /var/lib/dpkg/lock* /var/lib/apt/lists/lock 2>/dev/null
    
    # 重新同步系统依赖
    apt-get update -y >/dev/null 2>&1
    apt-get install -y python3 python3-pip python3-full psmisc curl lsof sqlite3 netcat-openbsd docker.io --no-install-recommends >/dev/null 2>&1
    systemctl start docker >/dev/null 2>&1
    
    # 强制重新注入 Python 核心 (解决 Internal Error 关键)
    python3 -m pip install flask websockets psutil cryptography --break-system-packages --quiet --force-reinstall >/dev/null 2>&1 || true
    echo -e "${G}✅ 深度环境自愈完成。${NC}"
}

get_all_ips() {
    IPV4=$(curl -4 -s --connect-timeout 5 https://api.ipify.org || echo "N/A")
    IPV6=$(curl -6 -s --connect-timeout 5 https://api64.ipify.org || echo "N/A")
}

# ==========================================
# 2. 增强型凭据管理 (双栈 + 链接)
# ==========================================

manage_credentials() {
    clear
    get_all_ips
    [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
    
    # 构建面板地址
    PANEL_URL_V4="http://$IPV4:$M_PORT"
    PANEL_URL_V6="http://[$IPV6]:$M_PORT"

    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 凭据管理中心 (V8.8)   "
    echo -e "${G}==================================${NC}"
    echo -e "${Y}[ 本机网络信息 ]${NC}"
    echo -e "IPv4 地址: ${G}${IPV4}${NC}"
    echo -e "IPv6 地址: ${G}${IPV6}${NC} (被控连接优先)"
    echo -e "----------------------------------"
    echo -e "${Y}[ 登录信息 ]${NC}"
    echo -e "面板地址(v4): ${G}${PANEL_URL_V4}${NC}"
    echo -e "面板地址(v6): ${G}${PANEL_URL_V6}${NC}"
    echo -e "用户名: ${G}${M_USER:-未设置}${NC}"
    echo -e "密码:   ${G}${M_PASS:-未设置}${NC}"
    echo -e "Token:  ${G}${M_TOKEN:-未设置}${NC}"
    echo -e "----------------------------------"
    echo -e "1. 修改配置 | 0. 返回主菜单"
    read -p "选择操作: " opt
    case $opt in
        1) install_master ;;
        0) show_menu ;;
    esac
}

# ==========================================
# 3. 主控端安装 (Master)
# ==========================================

install_master() {
    echo -e "${G}[+] 启动主控安装向导...${NC}"
    get_all_ips
    read -p "Web 端口 [7575]: " M_PORT
    M_PORT=${M_PORT:-7575}
    read -p "管理账号: " M_USER
    read -p "管理密码: " M_PASS
    M_TOKEN=$(openssl rand -hex 8)

    cat > "$CONFIG_FILE" <<EOF
TYPE="MASTER"
M_PORT="$M_PORT"
M_USER="$M_USER"
M_PASS="$M_PASS"
M_TOKEN="$M_TOKEN"
EOF

    # 启动 3X-UI 引擎
    docker rm -f 3x-ui-master 2>/dev/null
    docker run -d --name 3x-ui-master --restart always --network host -v ${INSTALL_PATH}/master/db_data:/etc/x-ui ghcr.io/mhsanaei/3x-ui:latest

    # 强力生成 app.py
    cat > "${INSTALL_PATH}/master/app.py" <<EOF
import json, asyncio, time, psutil, os, subprocess
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread

# 配置注入
M_PORT = $M_PORT
M_USER = "$M_USER"
M_PASS = "$M_PASS"
M_TOKEN = "$M_TOKEN"

app = Flask(__name__)
app.secret_key = M_TOKEN
AGENTS = {}
LOOP = None

@app.route('/api/state')
def get_state():
    return jsonify({"agents": {ip: {"stats": info["stats"]} for ip, info in AGENTS.items()}})

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form['u'] == M_USER and request.form['p'] == M_PASS:
            session['logged'] = True; return redirect('/')
    return '<h3>MultiX Auth</h3><form method="post">U: <input name="u"><br>P: <input name="p" type="password"><br><button>Login</button></form>'

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return """<h1>MultiX Panel Online</h1><div id='app'></div><script src='https://unpkg.com/vue@3/dist/vue.global.js'></script>"""

async def ws_handler(ws):
    ip = ws.remote_address[0]
    try:
        auth = await asyncio.wait_for(ws.recv(), timeout=10)
        if json.loads(auth).get('token') == M_TOKEN:
            AGENTS[ip] = {"ws": ws, "stats": {"cpu":0, "mem":0}}
            async for msg in ws:
                d = json.loads(msg)
                if d.get('type') == 'heartbeat': AGENTS[ip]['stats'] = d['data']
    finally:
        if ip in AGENTS: del AGENTS[ip]

def start_ws():
    global LOOP
    LOOP = asyncio.new_event_loop()
    asyncio.set_event_loop(LOOP)
    srv = websockets.serve(ws_handler, "0.0.0.0", 8888)
    LOOP.run_until_complete(srv); LOOP.run_forever()

if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    app.run(host='0.0.0.0', port=M_PORT)
EOF

    pkill -9 -f app.py 2>/dev/null
    nohup python3 ${INSTALL_PATH}/master/app.py > /dev/null 2>&1 &
    echo -e "${G}🎉 主控安装完成！请查阅凭据中心获取登录地址。${NC}"
    read -p "回车返回..." ; show_menu
}

# ==========================================
# 4. 被控端安装 (IPv6 优先)
# ==========================================

install_agent() {
    echo -e "${G}[+] 启动被控安装 (IPv6 优先模式)...${NC}"
    read -p "主控 IPv6 或 IP: " M_HOST
    read -p "主控 Token: " A_TOKEN
    
    cat > ${INSTALL_PATH}/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, time, socket

MASTER = "${M_HOST}"
TOKEN = "${A_TOKEN}"

async def run():
    # IPv6 优先逻辑：尝试解析双栈
    uri = f"ws://{MASTER}:8888"
    print(f"[*] 尝试连接主控: {uri}")
    while True:
        try:
            # 自动识别 IPv6 或 IPv4
            async with websockets.connect(uri, family=socket.AF_UNSPEC) as ws:
                await ws.send(json.dumps({"token": TOKEN, "type": "auth"}))
                while True:
                    stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent)}
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats}))
                    await asyncio.sleep(5)
        except Exception as e:
            print(f"[!] 连接失败: {e}, 5秒后重试...")
            await asyncio.sleep(5)

if __name__ == '__main__': asyncio.run(run())
EOF

    docker pull ghcr.io/mhsanaei/3x-ui:latest
    docker run -d --name 3x-ui --restart always --network host -v ${INSTALL_PATH}/agent/db_data:/etc/x-ui ghcr.io/mhsanaei/3x-ui:latest
    
    cd ${INSTALL_PATH}/agent
    cat > Dockerfile <<'EOF'
FROM python:3.11-slim
RUN pip install --no-cache-dir websockets psutil
WORKDIR /app
CMD ["python", "agent.py"]
EOF
    docker build -t multix-agent-v88 . >/dev/null 2>&1
    docker run -d --name multix-agent --restart always --network host -v ${INSTALL_PATH}/agent:/app multix-agent-v88
    echo -e "${G}✅ 被控端已启动，正在尝试通过 IPv6 建立握手。${NC}"
    read -p "回车返回..." ; show_menu
}

# ==========================================
# 5. 入口
# ==========================================

show_menu() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 管理系统 V8.8        "
    echo -e "   双栈自愈 | IPv6优先 | 旗舰版    "
    echo -e "${G}==================================${NC}"
    echo -e "1. 🚀 安装/重装 主控端"
    echo -e "2. 📡 安装/重装 被控端 (IPv6优先)"
    echo -e "3. 🔑 凭据中心 (双栈地址/密码/Token)"
    echo -e "7. 🧹 深度清理与修复 (解决一切报错)"
    echo -e "9. 🗑️  完全卸载"
    echo -e "0. 退出"
    read -p "操作: " opt
    case $opt in
        1) force_fix_env; install_master ;;
        2) force_fix_env; install_agent ;;
        3) manage_credentials ;;
        7) force_fix_env; read -p "清理完成..." ; show_menu ;;
        9) docker rm -f 3x-ui multix-agent 3x-ui-master; rm -rf $INSTALL_PATH; exit 0 ;;
        *) exit 0 ;;
    esac
}

mkdir -p "$INSTALL_PATH"
show_menu
