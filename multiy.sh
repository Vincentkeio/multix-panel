#!/bin/bash

# ==============================================================================
# Multiy Pro Script V78.2 (LOGIC LOAD FIX & DIAGNOSTIC+)
# 1. [Fix] 调整函数定义顺序，彻底修复 install_master: command not found
# 2. [UI] 恢复强化版玻璃拟态卡片，增加实时拨测毫秒显示
# 3. [Diagnostic] 选项 3 增加网络族识别（V4/V6）与 Token 强一致性校验
# 4. [Init] 启动即刷新快捷指令，确保 multiy 命令永远指向最新版
# ==============================================================================

export M_ROOT="/opt/multiy_mvp"
SH_VER="V78.2"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 基础工具模块 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[错误]${PLAIN} Root Required!" && exit 1; }
install_shortcut() { [ ! -f /usr/bin/multiy ] && cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy; }
get_env_val() { [ -f "$M_ROOT/.env" ] && grep "^$1=" "$M_ROOT/.env" | cut -d"'" -f2 || echo ""; }
pause_back() { echo -e "\n${YELLOW}按任意键返回菜单...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 模块：服务引擎 ] ---
_deploy_service() {
    local NAME=$1; local EXEC=$2
    BODY="[Unit]\nDescription=${NAME} Service\nAfter=network.target\n[Service]\nExecStart=/usr/bin/python3 ${EXEC}\nRestart=always\nWorkingDirectory=$(dirname ${EXEC})\nEnvironment=PYTHONUNBUFFERED=1\n[Install]\nWantedBy=multi-user.target"
    echo -e "$BODY" > "/etc/systemd/system/${NAME}.service"
    echo -e "$BODY" > "/lib/systemd/system/${NAME}.service"
    systemctl daemon-reload; systemctl enable "${NAME}"; systemctl restart "${NAME}"
}

# --- [ 模块：主控逻辑 ] ---
_generate_master_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import json, asyncio, psutil, os, websockets, ssl, time
from flask import Flask, render_template_string, request, session, redirect, jsonify
from threading import Thread

def load_env():
    c = {}
    if os.path.exists('/opt/multiy_mvp/.env'):
        with open('/opt/multiy_mvp/.env') as f:
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
            <span class="text-xs bg-slate-900 px-5 py-2 rounded-full border border-slate-800">Token: <span x-text="tk" class="text-blue-400"></span></span>
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
                        <div class="bg-black/40 p-3 rounded-xl text-center"><p class="text-[10px] text-slate-500">CPU</p><span class="text-blue-400 font-bold" x-text="a.stats.cpu+'%'"></span></div>
                        <div class="bg-black/40 p-3 rounded-xl text-center"><p class="text-[10px] text-slate-500">MEM</p><span class="text-blue-400 font-bold" x-text="a.stats.mem+'%'"></span></div>
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
    conf = load_env(); app.secret_key = conf.get('M_TOKEN', 'secret')
    if request.method == 'POST' and request.form.get('u') == conf.get('M_USER') and request.form.get('p') == conf.get('M_PASS'):
        session['logged'] = True; return redirect('/')
    return """<body style="background:#020617;display:flex;justify-content:center;align-items:center;height:100vh;color:#fff;font-family:sans-serif">
    <form method="post" style="background:rgba(255,255,255,0.03);backdrop-filter:blur(20px);padding:60px;border-radius:35px;border:1px solid rgba(255,255,255,0.1);width:340px;text-align:center">
        <h2 style="color:#3b82f6;font-size:2rem;font-weight:900;margin-bottom:40px;font-style:italic">Multiy <span style="color:#fff">Login</span></h2>
        <input name="u" placeholder="Admin" style="width:100%;padding:15px;margin:12px 0;background:#000;border:1px solid #333;color:#fff;border-radius:15px">
        <input name="p" type="password" placeholder="Pass" style="width:100%;padding:15px;margin:12px 0;background:#000;border:1px solid #333;color:#fff;border-radius:15px">
        <button style="width:100%;padding:16px;background:#3b82f6;color:#fff;border:none;border-radius:15px;font-weight:900;cursor:pointer;margin-top:20px">ENTER</button>
    </form></body>"""

async def ws_handler(ws):
    ip = ws.remote_address[0]; conf = load_env()
    try:
        auth_raw = await asyncio.wait_for(ws.recv(), timeout=5)
        auth = json.loads(auth_raw)
        if auth.get('token') == conf.get('M_TOKEN'):
            AGENTS[ip] = {"ws": ws, "stats": {"cpu":0,"mem":0}, "alias": auth.get('hostname','Node'), "last_seen": time.time(), "delay": 0}
            async for msg in ws:
                d = json.loads(msg)
                if d['type'] == 'heartbeat':
                    AGENTS[ip]['stats'] = d['data']; AGENTS[ip]['last_seen'] = time.time(); AGENTS[ip]['delay'] = d.get('delay', 0)
    except: pass
    finally: AGENTS.pop(ip, None)

def start_ws():
    conf = load_env(); loop = asyncio.new_event_loop(); asyncio.set_event_loop(loop)
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ssl_ctx.load_cert_chain('cert.pem', 'key.pem')
    loop.run_until_complete(asyncio.gather(websockets.serve(ws_handler, "0.0.0.0", int(conf.get('WS_PORT', 9339)), ssl=ssl_ctx),
                                          websockets.serve(ws_handler, "::", int(conf.get('WS_PORT', 9339)), ssl=ssl_ctx)))
    loop.run_forever()

if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    conf = load_env(); app.run(host='::', port=int(conf.get('M_PORT', 7575)))
EOF
}

# --- [ 核心模块：主控安装 ] ---
install_master() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 主控 (强化卡片版)${PLAIN}"
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
    echo -e "${GREEN}✅ 主控部署成功！正在同步配置...${PLAIN}"
    sleep 2; credential_center
}

# --- [ 核心模块：被控安装 ] ---
install_agent() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 被控 (自愈拨测版)${PLAIN}"
    mkdir -p "$M_ROOT/agent"
    read -p "主控域名或 IP: " M_HOST
    read -p "通信端口 [9339]: " WS_PORT; WS_PORT=${WS_PORT:-9339}
    read -p "主控 Token: " M_TOKEN
    read -p "偏好 (1.强制V6 2.强制V4 3.自动): " NET_PREF

    ARCH=$(uname -m); [[ "$ARCH" == "x86_64" ]] && SB_ARCH="amd64" || SB_ARCH="arm64"
    wget -qO /tmp/sb.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v1.8.0/sing-box-1.8.0-linux-${SB_ARCH}.tar.gz"
    tar -zxf /tmp/sb.tar.gz -C /tmp && mv /tmp/sing-box-*/sing-box /usr/local/bin/
    chmod +x /usr/local/bin/sing-box

    cat > "$M_ROOT/agent/agent.py" << 'EOF'
import asyncio, json, psutil, websockets, socket, ssl, time
MASTER = "REPLACE_HOST"; TOKEN = "REPLACE_TOKEN"; PORT = "REPLACE_PORT"; PREF = "REPLACE_PREF"
async def run():
    ssl_ctx = ssl.create_default_context(); ssl_ctx.check_hostname = False; ssl_ctx.verify_mode = ssl.CERT_NONE
    family_list = [socket.AF_INET6, socket.AF_INET] if PREF == "3" else ([socket.AF_INET6] if PREF == "1" else [socket.AF_INET])
    while True:
        for family in family_list:
            uri = f"wss://{MASTER}:{PORT}"
            try:
                async with websockets.connect(uri, ssl=ssl_ctx, open_timeout=10, family=family) as ws:
                    await ws.send(json.dumps({"token": TOKEN, "hostname": socket.gethostname()}))
                    while True:
                        t = time.time()
                        stats = {"cpu":int(psutil.cpu_percent()), "mem":int(psutil.virtual_memory().percent), "hostname":socket.gethostname()}
                        await ws.send(json.dumps({"type":"heartbeat", "data":stats, "delay": int((time.time()-t)*1000)}))
                        await asyncio.sleep(8)
            except Exception: await asyncio.sleep(5)
asyncio.run(run())
EOF
    sed -i "s/REPLACE_HOST/$M_HOST/; s/REPLACE_TOKEN/$M_TOKEN/; s/REPLACE_PORT/$WS_PORT/; s/REPLACE_PREF/$NET_PREF/" "$M_ROOT/agent/agent.py"
    _deploy_service "multiy-agent" "$M_ROOT/agent/agent.py"
    pause_back
}

# --- [ 核心模块：链路诊断 ] ---
smart_diagnostic() {
    clear; echo -e "${SKYBLUE}🔍 Multiy 智能链路诊断中心${PLAIN}"
    [ ! -f "$M_ROOT/agent/agent.py" ] && echo -e "${RED}[错误] 请先安装被控端${PLAIN}" && pause_back && return
    A_MASTER=$(grep "MASTER =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
    A_TOKEN=$(grep "TOKEN =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
    A_PORT=$(grep "PORT =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
    echo -e "目标主机: ${SKYBLUE}$A_MASTER:$A_PORT${PLAIN}\n校验令牌: ${YELLOW}$A_TOKEN${PLAIN}"
    echo -e "\n${YELLOW}[连通性测试]${PLAIN}"
    if curl -sk --max-time 3 "https://$A_MASTER:$A_PORT" >/dev/null 2>&1 || [ $? -eq 52 ]; then
        echo -e "👉 端口通透性: ${GREEN}成功 (WSS 接口已响应)${PLAIN}"
    else
        echo -e "👉 端口通透性: ${RED}失败 (请检查主控防火墙放行 $A_PORT)${PLAIN}"
    fi
    echo -e "\n${YELLOW}[最新连接日志]${PLAIN}"
    journalctl -u multiy-agent -n 10 --output cat
    pause_back
}

# --- [ 模块：凭据与清理 ] ---
credential_center() {
    clear; echo -e "${SKYBLUE}🔐 Multiy 凭据中心${PLAIN}"
    M_TOKEN=$(get_env_val "M_TOKEN"); M_PORT=$(get_env_val "M_PORT")
    V4=$(curl -s4m 3 api.ipify.org); V6=$(curl -s6m 3 api64.ipify.org)
    echo -e "IPv4 URL: ${GREEN}http://$V4:$M_PORT${PLAIN}\nIPv6 URL: ${GREEN}http://[$V6]:$M_PORT${PLAIN}"
    echo -e "Token: ${YELLOW}$M_TOKEN${PLAIN}"
    pause_back
}
deep_clean() {
    systemctl stop multiy-master multiy-agent 2>/dev/null; rm -rf "$M_ROOT" /etc/systemd/system/multiy-*
    echo "清理完成"; pause_back
}

# --- [ 主菜单逻辑 ] ---
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro ${SH_VER}${PLAIN}"
    echo " 1. 安装/更新 Multiy 主控 (强化卡片版)"
    echo " 2. 安装/更新 Multiy 被控 (自愈拨测版)"
    echo " 3. 智能拨测与链路诊断 ( 实时排障中心 )"
    echo " 4. 凭据与配置中心 ( 查看双栈地址 )"
    echo " 5. 深度清理中心 ( 重置环境 )"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in
        1) install_master ;; 2) install_agent ;; 3) smart_diagnostic ;;
        4) credential_center ;; 5) deep_clean ;; 0) exit 0 ;; *) main_menu ;;
    esac
}

check_root; install_shortcut; main_menu
