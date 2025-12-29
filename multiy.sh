#!/bin/bash

# ==============================================================================
# Multiy Pro Script V75.0 (MODULAR & TOKEN SYNC FIX)
# 1. [Init] 脚本运行即创建 multiy 命令
# 2. [Master] 支持自定义 Token，安装前强制清理残留进程
# 3. [UI] 面板 Token 实时从 .env 读取，确保与凭据中心一致
# 4. [Net] 被控端增加 IPv6 连通性预检逻辑
# ==============================================================================

export M_ROOT="/opt/multiy_mvp"
SH_VER="V75.0"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 模块：初始化 ] ---
install_shortcut() {
    [ ! -f /usr/bin/multiy ] && cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy
}
install_shortcut

check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[错误]${PLAIN} 请使用 root 用户运行！" && exit 1; }
get_public_ips() { 
    IPV4=$(curl -s4m 3 api.ipify.org || echo "N/A")
    IPV6=$(curl -s6m 3 api64.ipify.org || echo "N/A")
}
get_env_val() { [ -f "$M_ROOT/.env" ] && grep "^$1=" "$M_ROOT/.env" | cut -d"'" -f2 || echo ""; }
pause_back() { echo -e "\n${YELLOW}按任意键返回...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 模块：凭据中心 ] ---
credential_center() {
    clear; echo -e "${SKYBLUE}🔐 Multiy 凭据与配置中心 (V75.0)${PLAIN}"
    M_TOKEN=$(get_env_val "M_TOKEN"); M_PORT=$(get_env_val "M_PORT"); WS_PORT=$(get_env_val "WS_PORT")
    M_USER=$(get_env_val "M_USER"); M_PASS=$(get_env_val "M_PASS")

    if [ -n "$M_TOKEN" ]; then
        get_public_ips
        echo -e "------------------------------------------------"
        echo -e "${YELLOW}[主控端 - 访问凭据]${PLAIN}"
        echo -e "IPv4 URL: ${GREEN}http://${IPV4}:${M_PORT}${PLAIN}"
        echo -e "IPv6 URL: ${GREEN}http://[${IPV6}]:${M_PORT}${PLAIN}"
        echo -e "管理员用户: ${GREEN}${M_USER}${PLAIN}"
        echo -e "管理员密码: ${GREEN}${M_PASS}${PLAIN}"
        echo -e "\n${YELLOW}[主控端 - 通信配置]${PLAIN}"
        echo -e "通信监听端口: ${SKYBLUE}${WS_PORT}${PLAIN}"
        echo -e "通信令牌 (Token): ${YELLOW}${M_TOKEN}${PLAIN}"
        echo -e "------------------------------------------------"
    fi

    if [ -f "$M_ROOT/agent/agent.py" ]; then
        A_HOST=$(grep "MASTER =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
        A_PORT=$(grep "PORT =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
        echo -e "${YELLOW}[被控端 - 当前配置]${PLAIN}"
        echo -e "连接目标: ${SKYBLUE}${A_HOST}:${A_PORT}${PLAIN}"
        echo -e "------------------------------------------------"
    fi
    echo " 1. 重新安装/修改配置 | 0. 返回"
    read -p "选择: " c_opt
    [[ "$c_opt" == "1" ]] && install_master
    main_menu
}

# --- [ 模块：主控端 ] ---
install_master() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 主控 (物理双监听版)${PLAIN}"
    apt-get update && apt-get install -y python3 python3-pip curl wget openssl ntpdate >/dev/null 2>&1
    pip3 install "Flask<3.0.0" "websockets" "psutil" --break-system-packages >/dev/null 2>&1
    
    mkdir -p "$M_ROOT/master"
    openssl req -x509 -newkey rsa:2048 -keyout "$M_ROOT/master/key.pem" -out "$M_ROOT/master/cert.pem" -days 3650 -nodes -subj "/CN=Multiy" >/dev/null 2>&1

    read -p "面板端口 [7575]: " M_PORT; M_PORT=${M_PORT:-7575}
    read -p "通信端口 [9339]: " WS_PORT; WS_PORT=${WS_PORT:-9339}
    read -p "管理用户 [admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "管理密码 [admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    
    # Token 交互逻辑优化
    DEFAULT_TK=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    echo -e "系统建议 Token: ${YELLOW}${DEFAULT_TK}${PLAIN}"
    read -p "请输入自定义 Token (直接回车使用建议值): " IN_TOKEN
    M_TOKEN=${IN_TOKEN:-$DEFAULT_TK}
    
    # 强制写入并同步配置
    echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nWS_PORT='$WS_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'" > "$M_ROOT/.env"

    # 关键：彻底杀掉旧进程，防止 Token 缓存
    pkill -9 -f "master/app.py" >/dev/null 2>&1

    _generate_master_py
    _deploy_service "multiy-master" "$M_ROOT/master/app.py"
    echo -e "${GREEN}✅ 主控端部署成功！${PLAIN}"
    credential_center
}

_generate_master_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import json, asyncio, psutil, os, socket, websockets, ssl
from flask import Flask, render_template_string, request, session, redirect, jsonify
from threading import Thread

def load_env():
    c = {}
    try:
        with open('/opt/multiy_mvp/.env') as f:
            for l in f:
                if '=' in l: k,v = l.strip().split('=', 1); c[k] = v.strip("'\"")
    except: pass
    return c

app = Flask(__name__)
app.jinja_env.variable_start_string, app.jinja_env.variable_end_string = '[[', ']]'
AGENTS = {}

@app.route('/api/state')
def api_state():
    conf = load_env()
    return jsonify({
        "master_token": conf.get('M_TOKEN'),
        "agents": {ip: {"stats": a['stats'], "alias": a.get('alias')} for ip,a in AGENTS.items()}
    })

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    conf = load_env()
    return render_template_string("""
    <!DOCTYPE html><html><head><meta charset="UTF-8"><title>Multiy Pro</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
    <style>body{background:#020617;color:#fff}.glass{background:rgba(15,23,42,0.8);backdrop-filter:blur(20px);border:1px solid rgba(255,255,255,0.1);padding:25px;border-radius:24px}</style>
    </head><body class="p-10" x-data="panel()" x-init="start()">
        <div class="flex justify-between items-center mb-10">
            <h1 class="text-3xl font-black italic text-blue-500">Multiy <span class="text-white text-2xl">Pro</span></h1>
            <div class="flex gap-4">
                <span class="text-xs bg-slate-900 px-4 py-2 rounded-full border border-slate-800">Token: <span x-text="tk"></span></span>
                <a href="/logout" class="text-xs text-red-400 bg-red-900/20 px-4 py-2 rounded-full">退出</a>
            </div>
        </div>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
            <template x-for="(a, ip) in agents" :key="ip">
                <div class="glass border-l-4 border-blue-500">
                    <div class="flex justify-between"><b class="text-lg text-blue-100" x-text="a.alias"></b><span class="w-3 h-3 bg-green-500 rounded-full shadow-[0_0_10px_#22c55e]"></span></div>
                    <div class="text-xs text-slate-500 my-4 font-mono" x-text="ip"></div>
                    <div class="flex gap-6 text-sm">
                        <div><small class="block text-slate-500 text-[10px]">CPU</small><span x-text="a.stats.cpu+'%'"></span></div>
                        <div><small class="block text-slate-500 text-[10px]">MEM</small><span x-text="a.stats.mem+'%'"></span></div>
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
    app.secret_key = conf.get('M_TOKEN')
    if request.method == 'POST' and request.form.get('u') == conf.get('M_USER') and request.form.get('p') == conf.get('M_PASS'):
        session['logged'] = True; return redirect('/')
    return """<body style="background:#020617;display:flex;justify-content:center;align-items:center;height:100vh;color:#fff;font-family:sans-serif">
    <form method="post" style="background:#0f172a;padding:50px;border-radius:30px;width:300px;border:1px solid #1e293b">
        <h2 style="color:#3b82f6;text-align:center;font-weight:900">Multiy <span style="color:#fff">Login</span></h2>
        <input name="u" placeholder="Username" style="width:100%;padding:12px;margin:15px 0;background:#020617;border:1px solid #334155;color:#fff;border-radius:10px">
        <input name="p" type="password" placeholder="Password" style="width:100%;padding:12px;margin:15px 0;background:#020617;border:1px solid #334155;color:#fff;border-radius:10px">
        <button style="width:100%;padding:12px;background:#3b82f6;color:#fff;border:none;border-radius:10px;font-weight:bold;cursor:pointer">进入控制面板</button>
    </form></body>"""

@app.route('/logout')
def logout(): session.pop('logged', None); return redirect('/login')

async def ws_handler(ws):
    ip = ws.remote_address[0]
    conf = load_env()
    try:
        auth_raw = await asyncio.wait_for(ws.recv(), timeout=10)
        if json.loads(auth_raw).get('token') == conf.get('M_TOKEN'):
            AGENTS[ip] = {"ws": ws, "stats": {"cpu":0,"mem":0}, "alias":"连接中..."}
            async for msg in ws:
                d = json.loads(msg)
                if d.get('type') == 'heartbeat':
                    AGENTS[ip]['stats'] = d.get('data')
                    AGENTS[ip]['alias'] = d['data'].get('hostname', 'Node')
    except: pass
    finally: AGENTS.pop(ip, None)

def start_ws():
    conf = load_env()
    loop = asyncio.new_event_loop(); asyncio.set_event_loop(loop)
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_ctx.load_cert_chain('cert.pem', 'key.pem')
    # 物理物理双监听加固
    v4 = websockets.serve(ws_handler, "0.0.0.0", int(conf.get('WS_PORT', 9339)), ssl=ssl_ctx)
    v6 = websockets.serve(ws_handler, "::", int(conf.get('WS_PORT', 9339)), ssl=ssl_ctx)
    loop.run_until_complete(asyncio.gather(v4, v6)); loop.run_forever()

if __name__ == '__main__':
    conf = load_env()
    Thread(target=start_ws, daemon=True).start()
    app.run(host='::', port=int(conf.get('M_PORT', 7575)))
EOF
}

# --- [ 模块：被控端 ] ---
install_agent() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 被控 (V75.0)${PLAIN}"
    mkdir -p "$M_ROOT/agent"
    read -p "主控域名或 IP: " M_HOST
    read -p "主控通信端口 [9339]: " WS_PORT; WS_PORT=${WS_PORT:-9339}
    read -p "主控 Token: " M_TOKEN
    echo -e "偏好选择: 1. 强制 IPv6 (适合 NAT 小鸡) | 2. 强制 IPv4 | 3. 自动探测"
    read -p "请选择 [1-3]: " NET_PREF

    # 下载 Sing-box 二进制
    ARCH=$(uname -m); [[ "$ARCH" == "x86_64" ]] && SB_ARCH="amd64" || SB_ARCH="arm64"
    wget -qO /tmp/sb.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v1.8.0/sing-box-1.8.0-linux-${SB_ARCH}.tar.gz"
    tar -zxf /tmp/sb.tar.gz -C /tmp && mv /tmp/sing-box-*/sing-box /usr/local/bin/
    chmod +x /usr/local/bin/sing-box

    _generate_agent_py "$M_HOST" "$M_TOKEN" "$WS_PORT" "$NET_PREF"
    _deploy_service "multiy-agent" "$M_ROOT/agent/agent.py"
    echo -e "${GREEN}✅ 被控端部署成功！请在主控面板查看。${PLAIN}"
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
    print(f"[Agent] 连接目标: {uri}...", flush=True)
    while True:
        try:
            async with websockets.connect(uri, ssl=ssl_ctx, open_timeout=15, family=family) as ws:
                await ws.send(json.dumps({"token": TOKEN}))
                print(f"[Agent] 成功与主控建立安全通信", flush=True)
                while True:
                    stats = {"cpu":int(psutil.cpu_percent()), "mem":int(psutil.virtual_memory().percent), "hostname":socket.gethostname()}
                    await ws.send(json.dumps({"type":"heartbeat", "data":stats}))
                    await asyncio.sleep(8)
        except Exception as e:
            print(f"[Agent] 通信异常: {e}", flush=True); await asyncio.sleep(5)
asyncio.run(run())
EOF
    sed -i "s/REPLACE_HOST/$1/; s/REPLACE_TOKEN/$2/; s/REPLACE_PORT/$3/; s/REPLACE_PREF/$4/" "$M_ROOT/agent/agent.py"
}

# --- [ 模块：服务引擎 ] ---
_deploy_service() {
    local NAME=$1; local EXEC=$2
    SERVICE_CONF="[Unit]
Description=${NAME} Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 ${EXEC}
Restart=always
WorkingDirectory=$(dirname ${EXEC})
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target"

    echo "$SERVICE_CONF" > "/etc/systemd/system/${NAME}.service"
    echo "$SERVICE_CONF" > "/lib/systemd/system/${NAME}.service"
    systemctl daemon-reload; systemctl enable "${NAME}"; systemctl restart "${NAME}"
}

# --- [ 模块：主菜单 ] ---
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro ${SH_VER}${PLAIN}"
    echo " 1. 安装/更新 Multiy 主控 (自定义 Token 版)"
    echo " 2. 安装/更新 Multiy 被控 (WSS 加固版)"
    echo " 3. 连接监控中心 (查看 ss 监听 & 日志)"
    echo " 4. 凭据与配置中心 (主/被控信息查看)"
    echo " 5. 卸载并清理组件"
    echo " 0. 退出"
    read -p "请选择: " c
    case $c in
        1) install_master ;; 2) install_agent ;; 
        3) 
            clear; echo -e "${YELLOW}[主控端口监听]${PLAIN}"
            ss -tuln | grep -E "$(get_env_val 'M_PORT')|$(get_env_val 'WS_PORT')"
            echo -e "\n${YELLOW}[被控运行日志]${PLAIN}"
            journalctl -u multiy-agent -f --output cat ;;
        4) credential_center ;;
        5) 
            systemctl stop multiy-master multiy-agent 2>/dev/null
            rm -rf "$M_ROOT" /usr/bin/multiy /etc/systemd/system/multiy-*
            echo "清理完成！"; exit 0 ;;
        0) exit 0 ;; *) main_menu ;;
    esac
}

check_root; main_menu
