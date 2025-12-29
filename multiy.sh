#!/bin/bash

# ==============================================================================
# Multiy Pro Script V75.6 (MODULAR FINAL)
# [Module 1] Init: 脚本运行即建立 multiy 命令
# [Module 2] Master: 自定义 Token 交互，强制清理旧进程
# [Module 3] Config: 凭据中心(Option 5)，支持即时修改
# [Module 4] Agent: IPv6 连通性预检逻辑
# ==============================================================================

export M_ROOT="/opt/multiy_mvp"
SH_VER="V75.6"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 模块：初始化 ] ---
install_shortcut() {
    [ ! -f /usr/bin/multiy ] && cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy
}
install_shortcut # 快捷启动

check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[错误]${PLAIN} 需 Root 权限!" && exit 1; }
get_public_ips() { 
    IPV4=$(curl -s4m 3 api.ipify.org || echo "N/A")
    IPV6=$(curl -s6m 3 api64.ipify.org || echo "N/A")
}
get_env_val() { [ -f "$M_ROOT/.env" ] && grep "^$1=" "$M_ROOT/.env" | cut -d"'" -f2 || echo ""; }
pause_back() { echo -e "\n${YELLOW}按任意键返回...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 模块：凭据与配置中心 ] ---
credential_center() {
    clear; echo -e "${SKYBLUE}🔐 Multiy 凭据与配置中心 (V75.6)${PLAIN}"
    M_TOKEN=$(get_env_val "M_TOKEN"); M_PORT=$(get_env_val "M_PORT")
    WS_PORT=$(get_env_val "WS_PORT"); M_USER=$(get_env_val "M_USER")
    M_PASS=$(get_env_val "M_PASS")

    if [ -n "$M_TOKEN" ]; then
        get_public_ips
        echo -e "------------------------------------------------"
        echo -e "${YELLOW}[主控端 - 访问凭据]${PLAIN}"
        echo -e "IPv4 登录地址: ${GREEN}http://${IPV4}:${M_PORT}${PLAIN}"
        echo -e "IPv6 登录地址: ${GREEN}http://[${IPV6}]:${M_PORT}${PLAIN}"
        echo -e "管理员账号: ${GREEN}${M_USER}${PLAIN} / ${GREEN}${M_PASS}${PLAIN}"
        echo -e "\n${YELLOW}[通信安全配置]${PLAIN}"
        echo -e "WebSocket 通信端口: ${SKYBLUE}${WS_PORT}${PLAIN}"
        echo -e "通信令牌 (Token): ${YELLOW}${M_TOKEN}${PLAIN}"
        echo -e "------------------------------------------------"
    fi

    if [ -f "$M_ROOT/agent/agent.py" ]; then
        A_HOST=$(grep "MASTER =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
        echo -e "${YELLOW}[被控端 - 当前状态]${PLAIN}"
        echo -e "连接目标: ${SKYBLUE}${A_HOST}${PLAIN}"
        echo -e "------------------------------------------------"
    fi
    echo " 1. 重新安装并修改配置 | 2. 卸载清理组件 | 0. 返回"
    read -p "选择: " c_opt
    case $c_opt in
        1) install_master ;;
        2) systemctl stop multiy-master multiy-agent 2>/dev/null; rm -rf "$M_ROOT" /etc/systemd/system/multiy-*; echo "已清理"; exit 0 ;;
        *) main_menu ;;
    esac
}

# --- [ 模块：主控部署 ] ---
install_master() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 主控${PLAIN}"
    apt-get update && apt-get install -y python3 python3-pip curl wget openssl ntpdate >/dev/null 2>&1
    pip3 install "Flask<3.0.0" "websockets" "psutil" --break-system-packages >/dev/null 2>&1
    
    mkdir -p "$M_ROOT/master"
    openssl req -x509 -newkey rsa:2048 -keyout "$M_ROOT/master/key.pem" -out "$M_ROOT/master/cert.pem" -days 3650 -nodes -subj "/CN=Multiy" >/dev/null 2>&1

    read -p "面板端口 [7575]: " M_PORT; M_PORT=${M_PORT:-7575}
    read -p "通信端口 [9339]: " WS_PORT; WS_PORT=${WS_PORT:-9339}
    read -p "管理用户 [admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "管理密码 [admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    
    DEFAULT_TK=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    echo -e "系统建议 Token: ${YELLOW}${DEFAULT_TK}${PLAIN}"
    read -p "输入自定义 Token (直接回车用建议值): " IN_TOKEN
    M_TOKEN=${IN_TOKEN:-$DEFAULT_TK}
    
    echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nWS_PORT='$WS_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'" > "$M_ROOT/.env"

    _write_master_app_py
    _deploy_service "multiy-master" "$M_ROOT/master/app.py"
    echo -e "${GREEN}✅ 主控部署成功！Token 已物理同步。${PLAIN}"
    pause_back
}

_write_master_app_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import json, asyncio, psutil, os, websockets, ssl
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
    conf = load_env() # 实时同步 Token
    return jsonify({"master_token": conf.get('M_TOKEN'), "agents": {ip: {"stats": a['stats'], "alias": a.get('alias')} for ip,a in AGENTS.items()}})

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string("""
    <!DOCTYPE html><html><head><meta charset="UTF-8"><script src="https://cdn.tailwindcss.com"></script>
    <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
    <style>body{background:#020617;color:#fff}.glass{background:rgba(15,23,42,0.8);backdrop-filter:blur(20px);border:1px solid rgba(255,255,255,0.1);padding:25px;border-radius:24px}</style>
    </head><body class="p-10" x-data="panel()" x-init="start()">
        <div class="flex justify-between items-center mb-10">
            <h1 class="text-3xl font-black italic text-blue-500">Multiy <span style="color:#fff">Pro</span></h1>
            <span class="text-xs bg-slate-900 px-4 py-2 rounded-full border border-slate-800">实时 Token: <span x-text="tk"></span></span>
        </div>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
            <template x-for="(a, ip) in agents" :key="ip">
                <div class="glass border-l-4 border-blue-500">
                    <div class="flex justify-between"><b>[[ a.alias ]]</b><span class="text-green-500">●</span></div>
                    <div class="text-xs text-slate-500 my-4 font-mono">[[ ip ]]</div>
                    <div class="flex gap-4 text-xs font-mono"><span>CPU: [[ a.stats.cpu ]]%</span><span>MEM: [[ a.stats.mem ]]%</span></div>
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
    conf = load_env(); app.secret_key = conf.get('M_TOKEN')
    if request.method == 'POST' and request.form.get('u') == conf.get('M_USER') and request.form.get('p') == conf.get('M_PASS'):
        session['logged'] = True; return redirect('/')
    return "<body><form method='post' style='margin-top:100px;text-align:center'><input name='u' placeholder='User'><br><input name='p' type='password' placeholder='Pass'><br><button>LOGIN</button></form></body>"

async def ws_handler(ws):
    ip = ws.remote_address[0]; conf = load_env()
    try:
        auth_raw = await asyncio.wait_for(ws.recv(), timeout=10)
        if json.loads(auth_raw).get('token') == conf.get('M_TOKEN'):
            AGENTS[ip] = {"ws": ws, "stats": {"cpu":0,"mem":0}}
            async for msg in ws:
                d = json.loads(msg); AGENTS[ip]['stats'] = d.get('data'); AGENTS[ip]['alias'] = d['data'].get('hostname')
    except: pass
    finally: AGENTS.pop(ip, None)

def start_ws():
    conf = load_env(); loop = asyncio.new_event_loop(); asyncio.set_event_loop(loop)
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ssl_ctx.load_cert_chain('cert.pem', 'key.pem')
    # 双协议栈绑定
    v4 = websockets.serve(ws_handler, "0.0.0.0", int(conf.get('WS_PORT')), ssl=ssl_ctx)
    v6 = websockets.serve(ws_handler, "::", int(conf.get('WS_PORT')), ssl=ssl_ctx)
    loop.run_until_complete(asyncio.gather(v4, v6)); loop.run_forever()

if __name__ == '__main__':
    conf = load_env(); Thread(target=start_ws, daemon=True).start()
    app.run(host='::', port=int(conf.get('M_PORT')))
EOF
}

# --- [ 模块：被控部署 ] ---
install_agent() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 被控${PLAIN}"
    mkdir -p "$M_ROOT/agent"
    read -p "主控域名/IP: " M_HOST
    read -p "通信端口 [9339]: " WS_PORT; WS_PORT=${WS_PORT:-9339}
    read -p "主控 Token: " M_TOKEN
    read -p "偏好(1.强制V6 2.强制V4 3.自动): " NET_PREF

    # 下载 Sing-box
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
    # 同时写入两个路径确保兼容
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

# --- [ 模块：主菜单 ] ---
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro ${SH_VER}${PLAIN}"
    echo " 1. 安装/更新 Multiy 主控"
    echo " 2. 安装/更新 Multiy 被控"
    echo " 3. 连接监控中心 (查看 ss/日志)"
    echo " 4. 实时日志查看 (主控)"
    echo " 5. 凭据与配置中心 ( Option 5 )"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in
        1) install_master ;; 2) install_agent ;; 
        3) ss -tuln | grep -E "$(get_env_val 'M_PORT')|$(get_env_val 'WS_PORT')"; pause_back ;;
        4) journalctl -u multiy-master -f ;;
        5) credential_center ;;
        0) exit 0 ;; *) main_menu ;;
    esac
}

check_root; main_menu
