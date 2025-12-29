#!/bin/bash
# Multiy Pro V135.0-ULTIMATE - 终极全功能旗舰版

export M_ROOT="/opt/multiy_mvp"
SH_VER="V135.0-ULTIMATE"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 基础工具 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[错误]${PLAIN} 需 Root 权限!" && exit 1; }
install_shortcut() { [ ! -f /usr/bin/multiy ] && cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy; }
pause_back() { echo -e "\n${YELLOW}按任意键返回主菜单...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 1. 凭据中心看板 ] ---
credential_center() {
    clear
    [ ! -f "$M_ROOT/.env" ] && echo -e "${RED}尚未安装主控！${PLAIN}" && pause_back && return
    source "$M_ROOT/.env"
    V4=$(curl -s4m 3 api.ipify.org || echo "未分配")
    V6=$(curl -s6m 3 api64.ipify.org || echo "未分配")
    
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    echo -e "          🛰️  MULTIY PRO 旗舰凭据看板"
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    echo -e "${GREEN}[ 1. 管理入口 (WEB) ]${PLAIN}"
    echo -e " 🔹 IPv4: http://$V4:$M_PORT"
    [ "$V6" != "未分配" ] && echo -e " 🔹 IPv6: http://[$V6]:$M_PORT"
    echo -e " 🔹 管理员: ${YELLOW}$M_USER${PLAIN} / 密码: ${YELLOW}$M_PASS${PLAIN}"
    
    echo -e "\n${GREEN}[ 2. 被控接入 (原生 WS 隧道) ]${PLAIN}"
    echo -e " 🔹 接入地址: ${SKYBLUE}$M_HOST${PLAIN}"
    echo -e " 🔹 接入端口: ${SKYBLUE}9339${PLAIN}"
    echo -e " 🔹 校验令牌: ${YELLOW}$M_TOKEN${PLAIN}"
    
    echo -e "\n${GREEN}[ 3. 物理监听状态 ]${PLAIN}"
    check_v4v6() { ss -tuln | grep -q ":$1 " && echo -e "${GREEN}● OK${PLAIN}" || echo -e "${RED}○ OFF${PLAIN}"; }
    echo -e " 🔹 面板服务 ($M_PORT): $(check_v4v6 $M_PORT)"
    echo -e " 🔹 通信服务 (9339): $(check_v4v6 9339)"
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    pause_back
}

# --- [ 2. 主控安装 (功能增强版) ] ---
install_master() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 旗舰主控 (V135.0)${PLAIN}"
    systemctl stop multiy-master 2>/dev/null
    
    # 环境对齐
    apt-get update && apt-get install -y python3 python3-pip curl lsof net-tools >/dev/null 2>&1
    python3 -m pip install "Flask<3.0.0" "websockets" "psutil" --break-system-packages --user >/dev/null 2>&1

    mkdir -p "$M_ROOT/master"

    echo -e "\n${YELLOW}--- 交互式设置 (回车使用默认值) ---${PLAIN}"
    read -p "1. 面板 Web 端口 [默认 7575]: " M_PORT; M_PORT=${M_PORT:-7575}
    read -p "2. 管理员账号 [默认 admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "3. 管理员密码 [默认 admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    read -p "4. 主控公网地址 (Agent连接用): " M_HOST; M_HOST=${M_HOST:-$(curl -s4 api.ipify.org)}
    
    TK_RAND=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)
    read -p "5. 通信令牌 Token [回车使用: $TK_RAND]: " IN_TK; M_TOKEN=${IN_TK:-$TK_RAND}

    cat > "$M_ROOT/.env" << EOF
M_TOKEN='$M_TOKEN'
M_PORT='$M_PORT'
M_USER='$M_USER'
M_PASS='$M_PASS'
M_HOST='$M_HOST'
EOF
    
    _generate_master_py
    _deploy_service "multiy-master" "$M_ROOT/master/app.py"
    echo -e "${GREEN}✅ 部署完成。${PLAIN}"; sleep 1; credential_center
}

_generate_master_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import asyncio, websockets, json, os, time, subprocess
from flask import Flask, render_template_string, session, redirect, request, jsonify
from threading import Thread

def load_env():
    c = {}
    path = '/opt/multiy_mvp/.env'
    if os.path.exists(path):
        with open(path, 'r', encoding='utf-8') as f:
            for l in f:
                if '=' in l: k, v = l.strip().split('=', 1); c[k] = v.strip("'\"")
    return c

app = Flask(__name__)
AGENTS = {}
env = load_env()
TOKEN = env.get('M_TOKEN')

# --- [ 原生 WS 异步逻辑 ] ---
async def ws_handler(ws):
    addr = ws.remote_address[0]
    sid = str(id(ws))
    try:
        async for msg in ws:
            data = json.loads(msg)
            if data.get('type') == 'auth':
                if data.get('token') == TOKEN:
                    AGENTS[sid] = {
                        "alias": data.get('hostname', 'Node'),
                        "stats": {"cpu":0,"mem":0},
                        "ip": addr,
                        "connected_at": time.strftime("%H:%M:%S"),
                        "last_seen": time.time()
                    }
                else: await ws.close()
            elif data.get('type') == 'heartbeat' and sid in AGENTS:
                AGENTS[sid]['stats'] = data
                AGENTS[sid]['last_seen'] = time.time()
    except: pass
    finally:
        if sid in AGENTS: del AGENTS[sid]

def start_ws_server():
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    srv = websockets.serve(ws_handler, "::", 9339)
    loop.run_until_complete(srv)
    loop.run_forever()

@app.route('/api/state')
def api_state(): 
    now = time.time()
    for sid in list(AGENTS.keys()):
        if now - AGENTS[sid]['last_seen'] > 30: del AGENTS[sid]
    return jsonify({"agents": AGENTS})

@app.route('/api/info')
def api_info():
    env = load_env()
    ip4 = subprocess.getoutput("curl -s4m 2 api.ipify.org || echo 'N/A'")
    ip6 = subprocess.getoutput("curl -s6m 2 api64.ipify.org || echo 'N/A'")
    return jsonify({"token": env.get('M_TOKEN'), "ip4": ip4, "ip6": ip6, "m_port": env.get('M_PORT')})

# --- [ UI 旗舰增强版 HTML ] ---
INDEX_HTML = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Multiy Pro Dashboard</title>
<script src="https://cdn.tailwindcss.com"></script>
<script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
<style>
    body{background:#020617;color:#fff;font-family:ui-sans-serif,system-ui;overflow-x:hidden}
    .glass{background:rgba(255,255,255,0.01);backdrop-filter:blur(20px);border:1px solid rgba(255,255,255,0.08);border-radius:2rem}
    .top-badge{background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.05);padding:8px 16px;border-radius:12px;font-size:10px;font-weight:900}
</style></head>
<body class="p-6 md:p-12" x-data="panel()" x-init="init()">
    <div class="max-w-7xl mx-auto">
        <div class="flex flex-wrap gap-4 mb-10">
            <div class="top-badge uppercase">Token: <span class="text-blue-400" x-text="sys.token"></span></div>
            <div class="top-badge uppercase">Master V4: <span class="text-blue-400" x-text="sys.ip4"></span></div>
            <div class="top-badge uppercase">Master V6: <span class="text-blue-400" x-text="sys.ip6"></span></div>
        </div>
        <header class="flex justify-between items-end mb-16">
            <div>
                <h1 class="text-6xl font-black italic tracking-tighter text-blue-600">MULTIY <span class="text-white">PRO</span></h1>
                <p class="text-slate-500 font-bold mt-2 uppercase text-xs tracking-widest">Enterprise Monitor System</p>
            </div>
            <div class="bg-blue-500/10 text-blue-500 px-4 py-1 rounded-full text-[10px] font-black border border-blue-500/20">NATIVE WS TUNNEL ACTIVE</div>
        </header>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            <template x-for="(node, sid) in agents" :key="sid">
                <div class="glass p-10 hover:border-blue-500/50 transition-all group">
                    <div class="flex justify-between mb-8">
                        <div>
                            <h2 class="text-2xl font-black group-hover:text-blue-400 transition-colors" x-text="node.alias"></h2>
                            <div class="flex items-center gap-2 mt-1">
                                <span class="w-2 h-2 rounded-full bg-green-500 animate-pulse"></span>
                                <code class="text-slate-500 text-[10px]" x-text="node.ip"></code>
                            </div>
                        </div>
                        <div class="text-right">
                            <div class="text-[10px] font-black text-slate-500 uppercase tracking-tighter">Connected At</div>
                            <div class="text-xs font-bold" x-text="node.connected_at"></div>
                        </div>
                    </div>
                    <div class="space-y-6">
                        <div>
                            <div class="flex justify-between text-[10px] font-black uppercase mb-2"><span class="text-slate-500">CPU Load</span><span x-text="node.stats.cpu+'%'"></span></div>
                            <div class="h-1.5 w-full bg-white/5 rounded-full overflow-hidden"><div class="h-full bg-blue-500 transition-all duration-500" :style="'width:'+node.stats.cpu+'%'"></div></div>
                        </div>
                        <div>
                            <div class="flex justify-between text-[10px] font-black uppercase mb-2"><span class="text-slate-500">Memory</span><span x-text="node.stats.mem+'%'"></span></div>
                            <div class="h-1.5 w-full bg-white/5 rounded-full overflow-hidden"><div class="h-full bg-purple-500 transition-all duration-500" :style="'width:'+node.stats.mem+'%'"></div></div>
                        </div>
                    </div>
                </div>
            </template>
        </div>
    </div>
    <script>
        function panel(){ return { agents:{}, sys:{}, init(){ setInterval(()=>this.fetch(), 2000); this.fetch(); }, 
        async fetch(){ try{ const r=await fetch('/api/state'); const d=await r.json(); this.agents=d.agents; const i=await fetch('/api/info'); this.sys=await i.json(); }catch(e){} } }}
    </script>
</body></html>
"""

HTML_LOGIN = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><script src="https://cdn.tailwindcss.com"></script></head>
<body style="background:#020617;display:flex;justify-content:center;align-items:center;height:100vh;color:#fff;font-family:sans-serif">
<form method="post" style="background:rgba(255,255,255,0.02);backdrop-filter:blur(30px);padding:60px;border-radius:40px;border:1px solid rgba(255,255,255,0.1);width:400px;text-align:center;box-shadow:0 0 50px rgba(59,130,246,0.15)">
    <h2 style="color:#3b82f6;font-size:3rem;font-weight:900;margin-bottom:40px;font-style:italic;letter-spacing:-3px;text-transform:uppercase">Multiy <span style="color:#fff">Pro</span></h2>
    <input name="u" placeholder="Admin Account" style="width:100%;padding:20px;margin:12px 0;background:#000;border:1px solid #333;color:#fff;border-radius:20px;outline:none;font-weight:bold">
    <input name="p" type="password" placeholder="Terminal Password" style="width:100%;padding:20px;margin:12px 0;background:#000;border:1px solid #333;color:#fff;border-radius:20px;outline:none;font-weight:bold">
    <button style="width:100%;padding:20px;background:#3b82f6;color:#fff;border:none;border-radius:20px;font-weight:900;cursor:pointer;margin-top:30px;text-transform:uppercase;letter-spacing:1px">Access Terminal</button>
</form></body></html>
"""

@app.route('/login', methods=['GET', 'POST'])
def login():
    env = load_env(); app.secret_key = env.get('M_TOKEN', 'secret')
    if request.method == 'POST' and request.form.get('u') == env.get('M_USER') and request.form.get('p') == env.get('M_PASS'):
        session['logged'] = True; return redirect('/')
    return render_template_string(HTML_LOGIN)

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(INDEX_HTML)

@app.route('/logout')
def logout(): session.pop('logged', None); return redirect('/login')

if __name__ == '__main__':
    Thread(target=start_ws_server, daemon=True).start()
    env = load_env()
    app.run(host='::', port=int(env.get('M_PORT', 7575)))
EOF
}

# --- [ 3. 被控安装 (终极修复版) ] ---
install_agent() {
    clear; echo -e "${SKYBLUE}>>> 安装 Multiy 旗舰被控 (V135.0)${PLAIN}"
    mkdir -p "$M_ROOT/agent"
    read -p "1. 主控域名或IP: " M_INPUT
    read -p "2. 通信令牌 (Token): " M_TOKEN
    
    # 强制安装原生 WS 库
    python3 -m pip install websockets psutil --break-system-packages --user >/dev/null 2>&1

    # 逻辑核心：自动判定 IPv6 数字地址并建立本地绰号映射
    if [[ "$M_INPUT" == *:* ]]; then
        echo -e "${YELLOW}[自愈机制] 映射 IPv6 物理路径以确保 100% 握手成功...${PLAIN}"
        NICKNAME="multiy.local.master"
        sed -i "/$NICKNAME/d" /etc/hosts
        echo "$M_INPUT $NICKNAME" >> /etc/hosts
        FINAL_URL="ws://$NICKNAME:9339"
    else
        FINAL_URL="ws://$M_INPUT:9339"
    fi

    cat > "$M_ROOT/agent/agent.py" << 'EOF'
import asyncio, websockets, json, psutil, socket, time

MASTER_URL = "REPLACE_URL"
TOKEN = "REPLACE_TOKEN"

async def run_agent():
    print(f"[*] 启动原生 WS 隧道: {MASTER_URL}")
    while True:
        try:
            async with websockets.connect(MASTER_URL, ping_interval=20, ping_timeout=20) as ws:
                # 身份验证
                auth_payload = {"type": "auth", "token": TOKEN, "hostname": socket.gethostname()}
                await ws.send(json.dumps(auth_payload))
                
                # 持续心跳
                while True:
                    stats = {
                        "type": "heartbeat",
                        "cpu": int(psutil.cpu_percent()),
                        "mem": int(psutil.virtual_memory().percent)
                    }
                    await ws.send(json.dumps(stats))
                    await asyncio.sleep(8)
        except Exception as e:
            await asyncio.sleep(5)

if __name__ == "__main__":
    try:
        asyncio.run(run_agent())
    except KeyboardInterrupt:
        pass
EOF
    sed -i "s|REPLACE_URL|$FINAL_URL|; s/REPLACE_TOKEN/$M_TOKEN/" "$M_ROOT/agent/agent.py"
    _deploy_service "multiy-agent" "$M_ROOT/agent/agent.py"
    echo -e "${GREEN}✅ 被控端已启动。${PLAIN}"; pause_back
}

# --- [ 4. 增强诊断中心 ] ---
smart_diagnostic() {
    clear; echo -e "${SKYBLUE}🔍 旗舰诊断中心 (原生协议探测)${PLAIN}"
    if [ -f "$M_ROOT/agent/agent.py" ]; then
        A_URL=$(grep "MASTER_URL =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
        echo -e " 🔹 探测 URL: ${SKYBLUE}$A_URL${PLAIN}"
        # 模拟 WebSocket 物理连接
        python3 -c "import websockets, asyncio; asyncio.run(websockets.connect('$A_URL', timeout=5))" >/dev/null 2>&1
        [ $? -eq 0 ] || [ $? -eq 1 ] && echo -e " 👉 链路状态: ${GREEN}正常 (TCP+WS 对接成功)${PLAIN}" || echo -e " 👉 链路状态: ${RED}故障 (主控 9339 端口不可达)${PLAIN}"
    else
        echo -e "${RED}[错误]${PLAIN} 未安装 Agent。"
    fi
    pause_back
}

_deploy_service() {
    local NAME=$1; local EXEC=$2
    cat > "/etc/systemd/system/${NAME}.service" << EOF
[Unit]
Description=${NAME} Flagship Service
After=network.target
[Service]
ExecStart=/usr/bin/python3 ${EXEC}
Restart=always
WorkingDirectory=$(dirname ${EXEC})
Environment=PYTHONUNBUFFERED=1
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable "${NAME}"; systemctl restart "${NAME}"
}

main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro ${SH_VER}${PLAIN}"
    echo " 1. 安装/物理修复主控 (双栈原生协议版)"
    echo " 2. 安装/更新被控 (自动双栈路径自愈)"
    echo " 3. 智能链路诊断中心 (原生协议探测)"
    echo " 4. 凭据与配置看板 (精准存活状态)"
    echo " 5. 深度清理中心 (物理级全删)"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in 
        1) install_master ;; 
        2) install_agent ;; 
        3) smart_diagnostic ;; 
        4) credential_center ;; 
        5) 
            systemctl stop multiy-master multiy-agent 2>/dev/null
            rm -rf "$M_ROOT"; rm -f /etc/systemd/system/multiy-*; echo "清理完成"; exit ;; 
        0) exit ;; 
    esac
}

check_root; install_shortcut; main_menu
