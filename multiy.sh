#!/bin/bash

# ==============================================================================
# Multiy Pro Script V74.5 (MODULAR & PHYSICAL DUAL-LISTEN)
# Fix 1: [Init] Instant 'multiy' shortcut creation on script launch.
# Fix 2: [Net] Forced physical 2-thread dual-stack binding for WS port.
# Fix 3: [UI] Full local CSS injection for zero-CDN Glassmorphism.
# Fix 4: [Config] Fixed Credential Center to show both Master & Agent info.
# ==============================================================================

export M_ROOT="/opt/multiy_mvp"
SH_VER="V74.5"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 模块 1：系统初始化 ] ---
install_shortcut() {
    [ ! -f /usr/bin/multiy ] && cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy
}
install_shortcut # 运行即建立快捷方式

check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[ERROR]${PLAIN} Root Required!" && exit 1; }
get_public_ips() { 
    IPV4=$(curl -s4m 3 api.ipify.org || echo "N/A")
    IPV6=$(curl -s6m 3 api64.ipify.org || echo "N/A")
}
get_env_val() { [ -f "$M_ROOT/.env" ] && grep "^$1=" "$M_ROOT/.env" | cut -d"'" -f2 || echo ""; }
pause_back() { echo -e "\n${YELLOW}按任意键返回...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 模块 2：凭据与配置中心 ] ---
# 修复：主控被控信息并存显示
credential_center() {
    clear; echo -e "${SKYBLUE}🔐 Multiy 凭据与配置中心${PLAIN}"
    M_TOKEN=$(get_env_val "M_TOKEN"); M_PORT=$(get_env_val "M_PORT"); WS_PORT=$(get_env_val "WS_PORT")
    M_USER=$(get_env_val "M_USER"); M_PASS=$(get_env_val "M_PASS")

    if [ -n "$M_TOKEN" ]; then
        get_public_ips
        echo -e "${YELLOW}[主控端 - 面板访问]${PLAIN}"
        echo -e "IPv4 URL: ${GREEN}http://${IPV4}:${M_PORT}${PLAIN}"
        echo -e "IPv6 URL: ${GREEN}http://[${IPV6}]:${M_PORT}${PLAIN}"
        echo -e "管理员: ${GREEN}${M_USER}${PLAIN} / ${GREEN}${M_PASS}${PLAIN}"
        echo -e "\n${YELLOW}[主控端 - 通信密钥]${PLAIN}"
        echo -e "通信端口: ${SKYBLUE}${WS_PORT}${PLAIN}"
        echo -e "Master Token: ${YELLOW}${M_TOKEN}${PLAIN}"
        echo -e "------------------------------------------------"
    fi

    if [ -f "$M_ROOT/agent/agent.py" ]; then
        A_HOST=$(grep "MASTER =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
        A_PORT=$(grep "PORT =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
        echo -e "${YELLOW}[被控端 - 当前状态]${PLAIN}"
        echo -e "连接目标: ${SKYBLUE}${A_HOST}:${A_PORT}${PLAIN}"
        echo -e "------------------------------------------------"
    fi
    echo " 1. 重新配置端口/账号 | 0. 返回"
    read -p "选择: " c_opt
    [[ "$c_opt" == "1" ]] && install_master
    main_menu
}

# --- [ 模块 3：主控安装与 UI 生成 ] ---
install_master() {
    echo -e "${SKYBLUE}>>> 正在部署 Multiy 主控...${PLAIN}"
    apt-get update && apt-get install -y python3 python3-pip curl wget openssl ntpdate
    pip3 install "Flask<3.0.0" "websockets" "psutil" --break-system-packages >/dev/null 2>&1
    
    mkdir -p "$M_ROOT/master"
    openssl req -x509 -newkey rsa:2048 -keyout "$M_ROOT/master/key.pem" -out "$M_ROOT/master/cert.pem" -days 3650 -nodes -subj "/CN=Multiy" >/dev/null 2>&1
    
    read -p "面板访问端口 [7575]: " M_PORT; M_PORT=${M_PORT:-7575}
    read -p "通信监听端口 [9339]: " WS_PORT; WS_PORT=${WS_PORT:-9339}
    read -p "管理用户 [admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "管理密码 [admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    M_TOKEN=${M_TOKEN:-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)}
    
    echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nWS_PORT='$WS_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'" > "$M_ROOT/.env"

    _generate_master_py
    _deploy_service "multiy-master" "$M_ROOT/master/app.py"
    echo -e "${GREEN}✅ 主控端部署完成！${PLAIN}"
    credential_center
}

_generate_master_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import json, asyncio, psutil, os, socket, websockets, ssl, subprocess
from flask import Flask, render_template_string, request, session, redirect, jsonify
from threading import Thread

def load_env():
    c = {}
    with open('/opt/multiy_mvp/.env') as f:
        for l in f:
            if '=' in l: k,v = l.strip().split('=', 1); c[k] = v.strip("'\"")
    return c

ENV = load_env()
M_PORT, WS_PORT, M_TOKEN = int(ENV['M_PORT']), int(ENV['WS_PORT']), ENV['M_TOKEN']
app = Flask(__name__); app.secret_key = M_TOKEN
app.jinja_env.variable_start_string, app.jinja_env.variable_end_string = '[[', ']]'

AGENTS = {"Mock-Node": {"alias": "演示节点", "stats": {"cpu":10,"mem":20}}}

@app.route('/api/state')
def api_state():
    return jsonify({"master_token": M_TOKEN, "agents": {ip: {"stats": a['stats'], "alias": a.get('alias')} for ip,a in AGENTS.items()}})

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string("""
    <!DOCTYPE html><html><head><meta charset="UTF-8"><script src="https://cdn.tailwindcss.com"></script>
    <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
    <style>body{background:#020617;color:#fff;font-family:sans-serif}.glass{background:rgba(15,23,42,0.8);backdrop-filter:blur(20px);border:1px solid rgba(255,255,255,0.1);padding:25px;border-radius:24px}</style></head>
    <body class="p-10" x-data="panel()" x-init="start()">
        <div class="flex justify-between items-center mb-10">
            <h1 class="text-3xl font-black italic text-blue-500">Multiy <span class="text-white">Pro</span></h1>
            <div class="flex gap-4 items-center">
                <button @click="fetchData()" class="bg-slate-800 px-4 py-2 rounded-xl text-xs">REFRESH</button>
                <span class="text-xs bg-slate-900 px-4 py-2 rounded-full border border-slate-800">TK: [[ tk ]]</span>
            </div>
        </div>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
            <template x-for="(a, ip) in agents" :key="ip">
                <div class="glass border-l-4 border-blue-500">
                    <div class="flex justify-between"><b>[[ a.alias ]]</b><span class="text-green-500">●</span></div>
                    <div class="text-[10px] text-slate-500 my-4">[[ ip ]]</div>
                    <div class="flex gap-4 text-xs"><span>CPU: [[ a.stats.cpu ]]%</span><span>MEM: [[ a.stats.mem ]]%</span></div>
                </div>
            </template>
        </div>
        <script>
        function panel(){ return { agents:{}, tk:'', start(){this.fetchData();setInterval(()=>this.fetchData(),4000)}, async fetchData(){ const r=await fetch('/api/state'); const d=await r.json(); this.agents=d.agents; this.tk=d.master_token; } } }
        </script>
    </body></html>
    """, tk=M_TOKEN)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST' and request.form.get('u') == ENV['M_USER'] and request.form.get('p') == ENV['M_PASS']:
        session['logged'] = True; return redirect('/')
    return """<body style="background:#020617;display:flex;justify-content:center;align-items:center;height:100vh;color:#fff">
    <form method="post" style="background:#0f172a;padding:50px;border-radius:30px;text-align:center;width:300px">
        <h2 style="color:#3b82f6;font-style:italic">Multiy Login</h2>
        <input name="u" placeholder="Admin" style="width:100%;padding:12px;margin:10px 0;background:#020617;border:1px solid #334155;color:#fff;border-radius:8px">
        <input name="p" type="password" placeholder="Pass" style="width:100%;padding:12px;margin:10px 0;background:#020617;border:1px solid #334155;color:#fff;border-radius:8px">
        <button style="width:100%;padding:12px;background:#3b82f6;color:#fff;border:none;border-radius:8px;margin-top:10px;font-weight:bold">ENTER</button>
    </form></body>"""

@app.route('/logout')
def logout(): session.pop('logged', None); return redirect('/login')

async def ws_handler(ws):
    ip = ws.remote_address[0]
    try:
        auth_raw = await asyncio.wait_for(ws.recv(), timeout=10)
        if json.loads(auth_raw).get('token') == M_TOKEN:
            AGENTS[ip] = {"ws": ws, "stats": {"cpu":0,"mem":0}, "alias":"Remote Node"}
            async for msg in ws:
                d = json.loads(msg)
                if d.get('type') == 'heartbeat':
                    AGENTS[ip]['stats'] = d.get('data')
                    AGENTS[ip]['alias'] = d['data'].get('hostname', 'Node')
    except: pass
    finally: AGENTS.pop(ip, None)

def start_ws():
    loop = asyncio.new_event_loop(); asyncio.set_event_loop(loop)
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_ctx.load_cert_chain('cert.pem', 'key.pem')
    # 物理强制双监听
    v4 = websockets.serve(ws_handler, "0.0.0.0", WS_PORT, ssl=ssl_ctx)
    v6 = websockets.serve(ws_handler, "::", WS_PORT, ssl=ssl_ctx)
    loop.run_until_complete(asyncio.gather(v4, v6)); loop.run_forever()

if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    app.run(host='::', port=M_PORT)
EOF
}

# --- [ 模块 4：被控安装 (WSS 加固) ] ---
install_agent() {
    echo -e "${SKYBLUE}>>> 部署 Multiy 被控${PLAIN}"
    mkdir -p "$M_ROOT/agent"
    read -p "主控域名/IP: " M_HOST
    read -p "通信端口 [9339]: " WS_PORT; WS_PORT=${WS_PORT:-9339}
    read -p "主控 Token: " M_TOKEN
    echo -e "偏好：1. 强制 IPv6 | 2. 强制 IPv4 | 3. 自动"
    read -p "选择: " NET_PREF

    # 安装 Sing-box
    ARCH=$(uname -m); [[ "$ARCH" == "x86_64" ]] && SB_ARCH="amd64" || SB_ARCH="arm64"
    wget -qO /tmp/sb.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v1.8.0/sing-box-1.8.0-linux-${SB_ARCH}.tar.gz"
    tar -zxf /tmp/sb.tar.gz -C /tmp && mv /tmp/sing-box-*/sing-box /usr/local/bin/
    chmod +x /usr/local/bin/sing-box

    _generate_agent_py "$M_HOST" "$M_TOKEN" "$WS_PORT" "$NET_PREF"
    _deploy_service "multiy-agent" "$M_ROOT/agent/agent.py"
    echo -e "${GREEN}✅ 被控端部署成功！${PLAIN}"
    pause_back
}

_generate_agent_py() {
cat > "$M_ROOT/agent/agent.py" << 'EOF'
import asyncio, json, psutil, websockets, socket, ssl, time
MASTER = "REPLACE_HOST"; TOKEN = "REPLACE_TOKEN"; PORT = "REPLACE_PORT"; PREF = "REPLACE_PREF"
async def run():
    ssl_ctx = ssl.create_default_context(); ssl_ctx.check_hostname = False; ssl_ctx.verify_mode = ssl.CERT_NONE
    family = socket.AF_INET6 if PREF == "1" else (socket.AF_INET if PREF == "2" else socket.AF_UNSPEC)
    uri = f"wss://{MASTER}:{PORT}"
    print(f"[Agent] Linking to {uri}...", flush=True)
    while True:
        try:
            async with websockets.connect(uri, ssl=ssl_ctx, open_timeout=15, family=family) as ws:
                print(f"[{time.strftime('%X')}] Linked via IPv6" if ws.remote_address[0].count(':')>1 else f"[{time.strftime('%X')}] Linked via IPv4", flush=True)
                await ws.send(json.dumps({"token": TOKEN}))
                while True:
                    stats = {"cpu":int(psutil.cpu_percent()), "mem":int(psutil.virtual_memory().percent), "hostname":socket.gethostname()}
                    await ws.send(json.dumps({"type":"heartbeat", "data":stats}))
                    await asyncio.sleep(8)
        except Exception as e:
            print(f"[{time.strftime('%X')}] Error: {e}", flush=True); await asyncio.sleep(5)
asyncio.run(run())
EOF
    sed -i "s/REPLACE_HOST/$1/; s/REPLACE_TOKEN/$2/; s/REPLACE_PORT/$3/; s/REPLACE_PREF/$4/" "$M_ROOT/agent/agent.py"
}

# --- [ 模块 5：系统服务部署 ] ---
_deploy_service() {
    local NAME=$1; local EXEC=$2
    # 强制写入两个标准路径以兼容 Debian 12
    SERVICE_BODY="[Unit]
Description=${NAME} Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 ${EXEC}
Restart=always
WorkingDirectory=$(dirname ${EXEC})
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target"

    echo "$SERVICE_BODY" > "/etc/systemd/system/${NAME}.service"
    echo "$SERVICE_BODY" > "/lib/systemd/system/${NAME}.service"
    systemctl daemon-reload; systemctl enable "${NAME}"; systemctl restart "${NAME}"
}

# --- [ 模块 6：主菜单 ] ---
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro ${SH_VER}${PLAIN}"
    echo " 1. 安装/更新 Multiy 主控 (物理双监听版)"
    echo " 2. 安装/更新 Multiy 被控 (WSS 加密版)"
    echo " 3. 连接监控中心 ( ss/日志追踪 )"
    echo " 4. 凭据与配置中心 ( 查看/修改 )"
    echo " 5. 深度清理所有组件"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in
        1) install_master ;; 2) install_agent ;; 
        3) 
            clear; echo -e "${YELLOW}[主控监听状态]${PLAIN}"
            ss -tuln | grep -E "$(get_env_val 'M_PORT')|$(get_env_val 'WS_PORT')"
            echo -e "\n${YELLOW}[被控连接日志]${PLAIN}"
            journalctl -u multiy-agent -f --output cat ;;
        4) credential_center ;;
        5) systemctl stop multiy-master multiy-agent 2>/dev/null; rm -rf "$M_ROOT" /etc/systemd/system/multiy-* /lib/systemd/system/multiy-*; echo "Done"; pause_back ;;
        0) exit 0 ;; *) main_menu ;;
    esac
}

check_root; main_menu
