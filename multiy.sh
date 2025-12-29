#!/bin/bash

# ==============================================================================
# Multiy Pro Script V75.8 (FULL FEATURES & DESIGN RESTORED)
# 1. [Purge] 选项 5 深度清理，物理杀掉所有 multix/multiy 残留进程
# 2. [UI] 玻璃拟态登录界面美化 + 标识符隔离（防止 500 错误）
# 3. [Config] 选项 5 凭据中心回归，支持即时修改 Token、端口和账号
# 4. [Init] 启动即建立快捷指令 multiy，环境预检防止 Internal Server Error
# ==============================================================================

export M_ROOT="/opt/multiy_mvp"
SH_VER="V75.8"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 模块 1：系统初始化 ] ---
install_shortcut() { [ ! -f /usr/bin/multiy ] && cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy; }
install_shortcut

check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[错误]${PLAIN} Root Required!" && exit 1; }
get_env_val() { [ -f "$M_ROOT/.env" ] && grep "^$1=" "$M_ROOT/.env" | cut -d"'" -f2 || echo ""; }
pause_back() { echo -e "\n${YELLOW}按任意键返回...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 模块 2：深度清理与卸载 ] ---
deep_purge() {
    echo -e "${YELLOW}正在执行深度清理，根除所有残留进程...${PLAIN}"
    systemctl stop multiy-master multiy-agent multix-master multix-agent 2>/dev/null
    pkill -9 -f "multix_mvp" >/dev/null 2>&1
    pkill -9 -f "multiy_mvp" >/dev/null 2>&1
    pkill -9 -f "app.py" >/dev/null 2>&1
    rm -rf /opt/multix_mvp "$M_ROOT"
    rm -f /etc/systemd/system/multi* /lib/systemd/system/multi*
    systemctl daemon-reload
    echo -e "${GREEN}清理完成，环境已重置。${PLAIN}"
}

# --- [ 模块 3：凭据与配置中心 ] ---
credential_center() {
    clear; echo -e "${SKYBLUE}🔐 Multiy 凭据与配置中心 (V75.8)${PLAIN}"
    M_TOKEN=$(get_env_val "M_TOKEN"); M_PORT=$(get_env_val "M_PORT")
    WS_PORT=$(get_env_val "WS_PORT"); M_USER=$(get_env_val "M_USER"); M_PASS=$(get_env_val "M_PASS")

    if [ -n "$M_TOKEN" ]; then
        echo -e "------------------------------------------------"
        echo -e "${YELLOW}[当前主控配置]${PLAIN}"
        echo -e "面板端口: ${GREEN}${M_PORT}${PLAIN} | 通信端口: ${GREEN}${WS_PORT}${PLAIN}"
        echo -e "管理账号: ${GREEN}${M_USER}${PLAIN} | 密码: ${GREEN}${M_PASS}${PLAIN}"
        echo -e "当前令牌: ${YELLOW}${M_TOKEN}${PLAIN}"
        echo -e "------------------------------------------------"
    else
        echo -e "${RED}[警告] 主控尚未安装或配置丢失${PLAIN}"
    fi
    echo " 1. 重新安装并修改配置 | 2. 执行深度清理 (重置环境) | 0. 返回"
    read -p "选择: " c_opt
    case $c_opt in
        1) install_master ;;
        2) deep_purge; pause_back ;;
        *) main_menu ;;
    esac
}

# --- [ 模块 4：主控部署 (UI 美化版) ] ---
install_master() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 主控 (美化与功能回归版)${PLAIN}"
    pkill -9 -f "multiy_mvp" >/dev/null 2>&1
    
    apt-get update && apt-get install -y python3 python3-pip curl wget openssl >/dev/null 2>&1
    pip3 install "Flask<3.0.0" "websockets" "psutil" --break-system-packages >/dev/null 2>&1
    
    mkdir -p "$M_ROOT/master"
    openssl req -x509 -newkey rsa:2048 -keyout "$M_ROOT/master/key.pem" -out "$M_ROOT/master/cert.pem" -days 3650 -nodes -subj "/CN=Multiy" >/dev/null 2>&1

    read -p "面板访问端口 [7575]: " M_PORT; M_PORT=${M_PORT:-7575}
    read -p "通信监听端口 [9339]: " WS_PORT; WS_PORT=${WS_PORT:-9339}
    read -p "管理用户名 [admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "管理密码 [admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    
    DEFAULT_TK=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    echo -e "建议令牌: ${YELLOW}${DEFAULT_TK}${PLAIN}"
    read -p "自定义 Token (回车用建议值): " IN_TOKEN
    M_TOKEN=${IN_TOKEN:-$DEFAULT_TK}
    
    echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nWS_PORT='$WS_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'" > "$M_ROOT/.env"

    _generate_master_py
    _deploy_service "multiy-master" "$M_ROOT/master/app.py"
    echo -e "${GREEN}✅ 主控部署成功！请通过快捷键 multiy 进入凭据中心查看地址。${PLAIN}"
    pause_back
}

_generate_master_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import json, asyncio, psutil, os, websockets, ssl
from flask import Flask, render_template_string, request, session, redirect, jsonify
from threading import Thread

def load_env():
    c = {}
    path = '/opt/multiy_mvp/.env'
    if os.path.exists(path):
        with open(path) as f:
            for l in f:
                if '=' in l: k,v = l.strip().split('=', 1); c[k] = v.strip("'\"")
    return c

app = Flask(__name__)
app.jinja_env.variable_start_string, app.jinja_env.variable_end_string = '[[', ']]'
AGENTS = {}

@app.route('/api/state')
def api_state():
    conf = load_env()
    return jsonify({"master_token": conf.get('M_TOKEN'), "agents": {ip: {"stats": a['stats'], "alias": a.get('alias')} for ip,a in AGENTS.items()}})

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string("""
    <!DOCTYPE html><html><head><meta charset="UTF-8"><script src="https://cdn.tailwindcss.com"></script>
    <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
    <style>body{background:#020617;color:#fff}.glass{background:rgba(15,23,42,0.85);backdrop-filter:blur(25px);border:1px solid rgba(255,255,255,0.1);padding:30px;border-radius:28px}</style>
    </head><body class="p-10" x-data="panel()" x-init="start()">
        <div class="flex justify-between items-center mb-10 max-w-6xl mx-auto">
            <h1 class="text-4xl font-black italic text-blue-500">Multiy <span class="text-white text-3xl">Pro</span></h1>
            <div class="flex gap-4 items-center">
                <span class="text-xs bg-slate-900 px-5 py-2 rounded-full border border-slate-800">Token: <span x-text="tk" class="text-blue-400"></span></span>
                <a href="/logout" class="bg-red-500/20 text-red-500 px-4 py-2 rounded-full text-xs font-bold">LOGOUT</a>
            </div>
        </div>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-8 max-w-6xl mx-auto">
            <template x-for="(a, ip) in agents" :key="ip">
                <div class="glass border-l-8 border-blue-500 hover:scale-105 transition-transform cursor-pointer">
                    <div class="flex justify-between items-start">
                        <div><b class="text-xl" x-text="a.alias"></b><br><small class="text-slate-500 font-mono" x-text="ip"></small></div>
                        <div class="w-3 h-3 bg-green-500 rounded-full shadow-[0_0_15px_#22c55e]"></div>
                    </div>
                    <div class="grid grid-cols-2 gap-4 mt-8">
                        <div class="bg-black/40 p-3 rounded-xl text-center"><p class="text-[10px] text-slate-500 font-bold">CPU</p><span class="text-blue-400 font-bold" x-text="a.stats.cpu+'%'"></span></div>
                        <div class="bg-black/40 p-3 rounded-xl text-center"><p class="text-[10px] text-slate-500 font-bold">MEM</p><span class="text-blue-400 font-bold" x-text="a.stats.mem+'%'"></span></div>
                    </div>
                </div>
            </template>
        </div>
        <script>
        function panel(){ return { agents:{}, tk:'', start(){this.fetchData();setInterval(()=>this.fetchData(),4000)}, async fetchData(){ const r=await fetch('/api/state'); const d=await r.json(); this.agents=d.agents; this.tk=d.master_token; } } }
        </script>
    </body></html>
    """)

@app.route('/login', methods=['GET', 'POST'])
def login():
    conf = load_env()
    app.secret_key = conf.get('M_TOKEN', 'secret')
    if request.method == 'POST' and request.form.get('u') == conf.get('M_USER') and request.form.get('p') == conf.get('M_PASS'):
        session['logged'] = True; return redirect('/')
    return """<body style="background:#020617;display:flex;justify-content:center;align-items:center;height:100vh;color:#fff;font-family:sans-serif">
    <form method="post" style="background:rgba(255,255,255,0.03);backdrop-filter:blur(20px);padding:60px;border-radius:35px;border:1px solid rgba(255,255,255,0.1);width:340px;text-align:center">
        <h2 style="color:#3b82f6;font-size:2rem;font-weight:900;margin-bottom:40px;font-style:italic">Multiy <span style="color:#fff">Login</span></h2>
        <input name="u" placeholder="Admin Username" autocomplete="off" style="width:100%;padding:15px;margin:12px 0;background:rgba(0,0,0,0.5);border:1px solid #333;color:#fff;border-radius:15px;box-sizing:border-box">
        <input name="p" type="password" placeholder="Password" style="width:100%;padding:15px;margin:12px 0;background:rgba(0,0,0,0.5);border:1px solid #333;color:#fff;border-radius:15px;box-sizing:border-box">
        <button style="width:100%;padding:16px;background:#3b82f6;color:#fff;border:none;border-radius:15px;font-weight:900;cursor:pointer;margin-top:20px;letter-spacing:1px">ENTER SYSTEM</button>
    </form></body>"""

@app.route('/logout')
def logout(): session.pop('logged', None); return redirect('/login')

async def ws_handler(ws):
    ip = ws.remote_address[0]; conf = load_env()
    try:
        auth_raw = await asyncio.wait_for(ws.recv(), timeout=10)
        if json.loads(auth_raw).get('token') == conf.get('M_TOKEN'):
            AGENTS[ip] = {"ws": ws, "stats": {"cpu":0,"mem":0}, "alias":"Remote Node"}
            async for msg in ws:
                d = json.loads(msg); AGENTS[ip]['stats'] = d.get('data'); AGENTS[ip]['alias'] = d['data'].get('hostname', 'Node')
    except: pass
    finally: AGENTS.pop(ip, None)

def start_ws():
    conf = load_env(); loop = asyncio.new_event_loop(); asyncio.set_event_loop(loop)
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ssl_ctx.load_cert_chain('cert.pem', 'key.pem')
    v4 = websockets.serve(ws_handler, "0.0.0.0", int(conf.get('WS_PORT', 9339)), ssl=ssl_ctx)
    v6 = websockets.serve(ws_handler, "::", int(conf.get('WS_PORT', 9339)), ssl=ssl_ctx)
    loop.run_until_complete(asyncio.gather(v4, v6)); loop.run_forever()

if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    conf = load_env(); app.run(host='::', port=int(conf.get('M_PORT', 7575)))
EOF
}

# --- [ 模块 5：被控部署 ] ---
install_agent() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 被控 (NAT 优化版)${PLAIN}"
    mkdir -p "$M_ROOT/agent"
    read -p "主控域名或 IP: " M_HOST
    read -p "通信端口 [9339]: " WS_PORT; WS_PORT=${WS_PORT:-9339}
    read -p "主控 Token: " M_TOKEN
    read -p "连接偏好 (1.强制V6 2.强制V4 3.自动): " NET_PREF

    ARCH=$(uname -m); [[ "$ARCH" == "x86_64" ]] && SB_ARCH="amd64" || SB_ARCH="arm64"
    wget -qO /tmp/sb.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v1.8.0/sing-box-1.8.0-linux-${SB_ARCH}.tar.gz"
    tar -zxf /tmp/sb.tar.gz -C /tmp && mv /tmp/sing-box-*/sing-box /usr/local/bin/
    chmod +x /usr/local/bin/sing-box

    cat > "$M_ROOT/agent/agent.py" << 'EOF'
import asyncio, json, psutil, websockets, socket, ssl, time
MASTER = "REPLACE_HOST"; TOKEN = "REPLACE_TOKEN"; PORT = "REPLACE_PORT"; PREF = "REPLACE_PREF"
async def run():
    ssl_ctx = ssl.create_default_context(); ssl_ctx.check_hostname = False; ssl_ctx.verify_mode = ssl.CERT_NONE
    family = socket.AF_INET6 if PREF == "1" else (socket.AF_INET if PREF == "2" else socket.AF_UNSPEC)
    uri = f"wss://{MASTER}:{PORT}"
    while True:
        try:
            async with websockets.connect(uri, ssl=ssl_ctx, open_timeout=15, family=family) as ws:
                await ws.send(json.dumps({"token": TOKEN}))
                while True:
                    stats = {"cpu":int(psutil.cpu_percent()), "mem":int(psutil.virtual_memory().percent), "hostname":socket.gethostname()}
                    await ws.send(json.dumps({"type":"heartbeat", "data":stats}))
                    await asyncio.sleep(10)
        except Exception: await asyncio.sleep(5)
asyncio.run(run())
EOF
    sed -i "s/REPLACE_HOST/$M_HOST/; s/REPLACE_TOKEN/$M_TOKEN/; s/REPLACE_PORT/$WS_PORT/; s/REPLACE_PREF/$NET_PREF/" "$M_ROOT/agent/agent.py"
    _deploy_service "multiy-agent" "$M_ROOT/agent/agent.py"
    pause_back
}

_deploy_service() {
    local NAME=$1; local EXEC=$2
    BODY="[Unit]
Description=${NAME} Service
After=network.target
[Service]
ExecStart=/usr/bin/python3 ${EXEC}
Restart=always
WorkingDirectory=$(dirname ${EXEC})
Environment=PYTHONUNBUFFERED=1
[Install]
WantedBy=multi-user.target"
    echo "$BODY" > "/etc/systemd/system/${NAME}.service"
    echo "$BODY" > "/lib/systemd/system/${NAME}.service"
    systemctl daemon-reload; systemctl enable "${NAME}"; systemctl restart "${NAME}"
}

# --- [ 模块 6：主菜单 ] ---
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro ${SH_VER}${PLAIN}"
    echo " 1. 安装/更新 Multiy 主控 (美化与全功能版)"
    echo " 2. 安装/更新 Multiy 被控"
    echo " 3. 连接监控中心"
    echo " 4. 实时日志查看"
    echo " 5. 凭据中心与深度清理 ( Option 5 )"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in
        1) install_master ;; 2) install_agent ;; 
        3) ss -tuln | grep -E "$(get_env_val 'M_PORT')|$(get_env_val 'WS_PORT')"; pause_back ;;
        4) journalctl -f -u multiy-master -u multiy-agent ;;
        5) credential_center ;;
        0) exit 0 ;; *) main_menu ;;
    esac
}

check_root; main_menu
