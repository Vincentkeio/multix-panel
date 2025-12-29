#!/bin/bash

# ==============================================================================
# Multiy Pro Script V81.0 (Full Feature Recovery & WSS Fix)
# 1. [Fix] 异步双线程启动：确保 9339 通信端口先于 7575 面板启动
# 2. [Fix] 自签证书豁免：Agent 端强制跳过 SSL 校验，解决握手卡死
# 3. [Feature] 恢复最强菜单：包含双栈凭据中心、智能链路诊断、深度清理
# 4. [UI] 强化玻璃拟态卡片：实时显示延迟 (ms) 和节点负载
# ==============================================================================

export M_ROOT="/opt/multiy_mvp"
SH_VER="V81.0"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 基础模块 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[错误]${PLAIN} 需 Root 权限!" && exit 1; }
get_env_val() { [ -f "$M_ROOT/.env" ] && grep "^$1=" "$M_ROOT/.env" | cut -d"'" -f2 || echo ""; }
install_shortcut() { [ ! -f /usr/bin/multiy ] && cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy; }
pause_back() { echo -e "\n${YELLOW}按任意键返回菜单...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 核心模块：主控逻辑生成 ] ---
_generate_master_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import json, asyncio, psutil, os, websockets, ssl, time
from flask import Flask, render_template_string, request, session, redirect, jsonify
from threading import Thread

def load_env():
    c = {}
    if os.path.exists('/opt/multiy_mvp/.env'):
        with open('/opt/multiy_mvp/.env', encoding='utf-8') as f:
            for l in f:
                if '=' in l: k,v = l.strip().split('=', 1); c[k] = v.strip("'\"")
    return c

app = Flask(__name__)
app.jinja_env.variable_start_string, app.jinja_env.variable_end_string = '[[', ']]'
AGENTS = {}

@app.route('/api/state')
def api_state():
    conf = load_env()
    return jsonify({"master_token": conf.get('M_TOKEN'), "agents": {ip: {"stats": a['stats'], "alias": a.get('alias'), "delay": a.get('delay', 0), "last_seen": a['last_seen']} for ip,a in AGENTS.items()}})

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
            <div class="text-right">
                <span class="text-xs bg-slate-900 px-5 py-2 rounded-full border border-slate-800">Token: <span x-text="tk" class="text-blue-400 font-mono"></span></span>
                <a href="/logout" class="ml-4 text-xs text-red-500 font-bold uppercase">Logout</a>
            </div>
        </div>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-8 max-w-6xl mx-auto">
            <template x-for="(a, ip) in agents" :key="ip">
                <div class="glass border-l-8 border-blue-500 hover:scale-105 transition-all">
                    <div class="flex justify-between items-start">
                        <div><b class="text-xl" x-text="a.alias"></b><br><small class="text-slate-500 font-mono" x-text="ip"></small></div>
                        <div class="flex flex-col items-end gap-2">
                            <div class="w-3 h-3 bg-green-500 rounded-full shadow-[0_0_15px_#22c55e]"></div>
                            <span class="text-[10px] text-green-400 font-bold" x-text="a.delay+'ms'"></span>
                        </div>
                    </div>
                    <div class="grid grid-cols-2 gap-4 mt-8">
                        <div class="bg-black/40 p-3 rounded-xl text-center"><p class="text-[10px] text-slate-500 uppercase font-bold">CPU</p><span class="text-blue-400 font-bold" x-text="a.stats.cpu+'%'"></span></div>
                        <div class="bg-black/40 p-3 rounded-xl text-center"><p class="text-[10px] text-slate-500 uppercase font-bold">MEM</p><span class="text-blue-400 font-bold" x-text="a.stats.mem+'%'"></span></div>
                    </div>
                </div>
            </template>
        </div>
        <script>
        function panel(){ return { agents:{}, tk:'', start(){this.fetchData();setInterval(()=>this.fetchData(),4000)}, async fetchData(){ try{const r=await fetch('/api/state');const d=await r.json();this.agents=d.agents;this.tk=d.master_token}catch(e){} } } }
        </script>
    </body></html>
    """)

@app.route('/login', methods=['GET', 'POST'])
def login():
    conf = load_env(); app.secret_key = conf.get('M_TOKEN', 'secret')
    if request.method == 'POST' and request.form.get('u') == conf.get('M_USER') and request.form.get('p') == conf.get('M_PASS'):
        session['logged'] = True; return redirect('/')
    return """<body style="background:#020617;display:flex;justify-content:center;align-items:center;height:100vh;color:#fff;font-family:sans-serif"><form method="post" style="background:rgba(255,255,255,0.03);backdrop-filter:blur(20px);padding:60px;border-radius:35px;border:1px solid rgba(255,255,255,0.1);width:340px;text-align:center"><h2 style="color:#3b82f6;font-size:2rem;font-weight:900;margin-bottom:40px;font-style:italic">Multiy <span style="color:#fff">Login</span></h2><input name="u" placeholder="Admin" style="width:100%;padding:15px;margin:12px 0;background:#000;border:1px solid #333;color:#fff;border-radius:15px;outline:none"><input name="p" type="password" placeholder="Pass" style="width:100%;padding:15px;margin:12px 0;background:#000;border:1px solid #333;color:#fff;border-radius:15px;outline:none"><button style="width:100%;padding:16px;background:#3b82f6;color:#fff;border:none;border-radius:15px;font-weight:900;cursor:pointer;margin-top:20px">ENTER</button></form></body>"""

@app.route('/logout')
def logout(): session.pop('logged', None); return redirect('/login')

async def ws_handler(ws):
    ip = ws.remote_address[0]; conf = load_env()
    try:
        auth_raw = await asyncio.wait_for(ws.recv(), timeout=10)
        auth = json.loads(auth_raw)
        if auth.get('token') == conf.get('M_TOKEN'):
            AGENTS[ip] = {"stats": {"cpu":0,"mem":0}, "alias": auth.get('hostname','Node'), "last_seen": time.time(), "delay": 0}
            async for msg in ws:
                d = json.loads(msg)
                if d['type'] == 'heartbeat':
                    AGENTS[ip]['stats'] = d['data']; AGENTS[ip]['last_seen'] = time.time(); AGENTS[ip]['delay'] = d.get('delay', 0)
    except: pass
    finally: AGENTS.pop(ip, None)

def start_ws():
    conf = load_env(); loop = asyncio.new_event_loop(); asyncio.set_event_loop(loop)
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_ctx.load_cert_chain('/opt/multiy_mvp/master/cert.pem', '/opt/multiy_mvp/master/key.pem')
    ws_port = int(conf.get('WS_PORT', 9339))
    loop.run_until_complete(asyncio.gather(websockets.serve(ws_handler, "0.0.0.0", ws_port, ssl=ssl_ctx),
                                          websockets.serve(ws_handler, "::", ws_port, ssl=ssl_ctx)))
    loop.run_forever()

if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    conf = load_env(); app.run(host='::', port=int(conf.get('M_PORT', 7575)))
EOF
}

# --- [ 服务引擎 ] ---
_deploy_service() {
    local NAME=$1; local EXEC=$2
    BODY="[Unit]\nDescription=${NAME}\nAfter=network.target\n[Service]\nExecStart=/usr/bin/python3 ${EXEC}\nRestart=always\nWorkingDirectory=$(dirname ${EXEC})\nEnvironment=PYTHONUNBUFFERED=1\n[Install]\nWantedBy=multi-user.target"
    echo -e "$BODY" > "/etc/systemd/system/${NAME}.service"
    systemctl daemon-reload; systemctl enable "${NAME}"; systemctl restart "${NAME}"
}

# --- [ 1. 主控安装 ] ---
install_master() {
    clear; echo -e "${SKYBLUE}>>> 安装 Multiy 主控${PLAIN}"
    pkill -9 -f "app.py"; apt-get update && apt-get install -y python3 python3-pip openssl >/dev/null 2>&1
    pip3 install "Flask<3.0.0" "websockets" "psutil" --break-system-packages >/dev/null 2>&1
    mkdir -p "$M_ROOT/master"
    openssl req -x509 -newkey rsa:2048 -keyout "$M_ROOT/master/key.pem" -out "$M_ROOT/master/cert.pem" -days 3650 -nodes -subj "/CN=Multiy" >/dev/null 2>&1
    
    read -p "面板 Web 端口 [7575]: " M_PORT; M_PORT=${M_PORT:-7575}
    read -p "通信 WSS 端口 [9339]: " WS_PORT; WS_PORT=${WS_PORT:-9339}
    read -p "管理用户名 [admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "管理密码 [admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    TK_RAND=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    read -p "自定义 Token (回车用 $TK_RAND): " IN_TK; M_TOKEN=${IN_TK:-$TK_RAND}
    
    echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nWS_PORT='$WS_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'" > "$M_ROOT/.env"
    _generate_master_py; _deploy_service "multiy-master" "$M_ROOT/master/app.py"
    echo -e "${GREEN}主控已拉起，请进入凭据中心核对。${PLAIN}"; pause_back
}

# --- [ 2. 被控安装 ] ---
install_agent() {
    clear; echo -e "${SKYBLUE}>>> 安装 Multiy 被控${PLAIN}"
    mkdir -p "$M_ROOT/agent"
    read -p "主控域名/IP: " M_HOST; read -p "通信端口 [9339]: " WS_PORT; WS_PORT=${WS_PORT:-9339}
    read -p "主控 Token: " M_TOKEN; read -p "连接偏好 (1.V6 2.V4 3.自动): " NET_PREF
    
    cat > "$M_ROOT/agent/agent.py" << 'EOF'
import asyncio, json, psutil, websockets, socket, ssl, time
MASTER = "REPLACE_HOST"; TOKEN = "REPLACE_TOKEN"; PORT = "REPLACE_PORT"; PREF = "REPLACE_PREF"
async def run():
    # 强制豁免自签证书校验
    ssl_ctx = ssl.create_default_context(); ssl_ctx.check_hostname = False; ssl_ctx.verify_mode = ssl.CERT_NONE
    families = [socket.AF_INET6, socket.AF_INET] if PREF == "3" else ([socket.AF_INET6] if PREF == "1" else [socket.AF_INET])
    while True:
        for family in families:
            try:
                async with websockets.connect(f"wss://{MASTER}:{PORT}", ssl=ssl_ctx, open_timeout=10, family=family) as ws:
                    await ws.send(json.dumps({"token": TOKEN, "hostname": socket.gethostname()}))
                    while True:
                        t = time.time()
                        stats = {"cpu":int(psutil.cpu_percent()), "mem":int(psutil.virtual_memory().percent)}
                        await ws.send(json.dumps({"type":"heartbeat", "data":stats, "delay": int((time.time()-t)*1000)}))
                        await asyncio.sleep(8)
            except: await asyncio.sleep(2)
        await asyncio.sleep(5)
asyncio.run(run())
EOF
    sed -i "s/REPLACE_HOST/$M_HOST/; s/REPLACE_TOKEN/$M_TOKEN/; s/REPLACE_PORT/$WS_PORT/; s/REPLACE_PREF/$NET_PREF/" "$M_ROOT/agent/agent.py"
    _deploy_service "multiy-agent" "$M_ROOT/agent/agent.py"
    echo -e "${GREEN}被控已拉起。${PLAIN}"; pause_back
}

# --- [ 3. 智能诊断 ] ---
smart_diagnostic() {
    clear; echo -e "${SKYBLUE}🔍 链路诊断中心${PLAIN}"
    [ ! -f "$M_ROOT/agent/agent.py" ] && echo "未发现被控端" && pause_back && return
    M_HOST=$(grep "MASTER =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
    M_PORT=$(grep "PORT =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
    echo -e "目标: $M_HOST:$M_PORT"
    if curl -sk --max-time 3 "https://$M_HOST:$M_PORT" >/dev/null 2>&1 || [ $? -eq 52 ]; then
        echo -e "👉 端口通透性: ${GREEN}成功${PLAIN}"
    else
        echo -e "👉 端口通透性: ${RED}失败 (请检查主控防火墙)${PLAIN}"
    fi
    echo -e "\n最近 Agent 日志:"; journalctl -u multiy-agent -n 10 --output cat
    pause_back
}

# --- [ 4. 凭据中心 ] ---
credential_center() {
    clear; echo -e "${SKYBLUE}🔐 凭据中心${PLAIN}"
    V4=$(curl -s4m 3 api.ipify.org); V6=$(curl -s6m 3 api64.ipify.org)
    M_PORT=$(get_env_val "M_PORT"); M_TOKEN=$(get_env_val "M_TOKEN")
    echo -e "IPv4 URL: ${GREEN}http://$V4:$M_PORT${PLAIN}"
    echo -e "IPv6 URL: ${GREEN}http://[$V6]:$M_PORT${PLAIN}"
    echo -e "通信令牌: ${YELLOW}$M_TOKEN${PLAIN}"
    pause_back
}

# --- [ 5. 深度清理 ] ---
deep_clean() {
    systemctl stop multiy-master multiy-agent 2>/dev/null; pkill -9 -f "app.py"
    rm -rf "$M_ROOT" /etc/systemd/system/multiy-* /usr/bin/multiy
    echo "环境已重置。"; exit 0
}

# --- [ 菜单 ] ---
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro ${SH_VER}${PLAIN}"
    echo " 1. 安装/更新 Multiy 主控"
    echo " 2. 安装/更新 Multiy 被控"
    echo " 3. 智能链路诊断中心"
    echo " 4. 凭据与配置中心"
    echo " 5. 深度清理中心"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in
        1) install_master ;; 2) install_agent ;; 3) smart_diagnostic ;;
        4) credential_center ;; 5) deep_clean ;; 0) exit 0 ;; *) main_menu ;;
    esac
}

check_root; install_shortcut; main_menu
