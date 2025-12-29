#!/bin/bash
# Multiy Pro V135.0-ULTIMATE - 终极全功能旗舰版

export M_ROOT="/opt/multiy_mvp"
SH_VER="V135.0-ULTIMATE"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 基础工具 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[错误]${PLAIN} 需 Root 权限!" && exit 1; }
install_shortcut() { [ ! -f /usr/bin/multiy ] && cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy; }
pause_back() { echo -e "\n${YELLOW}按任意键返回主菜单...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 环境深度清理 ] ---
env_cleaner() {
    echo -e "${YELLOW}>>> 正在执行环境物理级大扫除...${PLAIN}"
    systemctl stop multiy-master multiy-agent 2>/dev/null
    pkill -9 python3 2>/dev/null
    # 彻底卸载冲突库
    python3 -m pip uninstall -y python-socketio eventlet python-engineio websockets flask 2>/dev/null
    # 安装旗舰版所需三件套
    python3 -m pip install flask websockets psutil --break-system-packages --user >/dev/null 2>&1
}

# --- [ 1. 凭据与配置详情看板 ] ---
credential_center() {
    clear
    [ ! -f "$M_ROOT/.env" ] && echo -e "${RED}尚未安装主控！${PLAIN}" && pause_back && return
    source "$M_ROOT/.env"
    V4=$(curl -s4m 3 api.ipify.org || echo "未分配")
    V6=$(curl -s6m 3 api64.ipify.org || echo "未分配")
    
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    echo -e "          🛰️  MULTIY PRO 旗舰凭据看板"
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    echo -e "${GREEN}[ 1. 面板访问信息 ]${PLAIN}"
    echo -e " 🔹 IPv4 入口: ${SKYBLUE}http://$V4:$M_PORT${PLAIN}"
    echo -e " 🔹 IPv6 入口: ${SKYBLUE}http://[$V6]:$M_PORT${PLAIN}"
    echo -e " 🔹 管理账号: ${YELLOW}$M_USER${PLAIN}"
    echo -e " 🔹 管理密码: ${YELLOW}$M_PASS${PLAIN}"
    
    echo -e "\n${GREEN}[ 2. Agent 接入配置 ]${PLAIN}"
    echo -e " 🔹 接入地址: ${SKYBLUE}$M_HOST${PLAIN}"
    echo -e " 🔹 接入端口: ${SKYBLUE}9339${PLAIN}"
    echo -e " 🔹 通信 Token: ${YELLOW}$M_TOKEN${PLAIN}"
    
    echo -e "\n${GREEN}[ 3. 系统底层监听 ]${PLAIN}"
    check_v4v6() { ss -tuln | grep -q ":$1 " && echo -e "${GREEN}● OK${PLAIN}" || echo -e "${RED}○ OFF${PLAIN}"; }
    echo -e " 🔹 Web Server ($M_PORT): $(check_v4v6 $M_PORT)"
    echo -e " 🔹 WebSocket (9339): $(check_v4v6 9339)"
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    pause_back
}

# --- [ 2. 主控安装 (找回全部功能) ] ---
install_master() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 旗舰主控 (全异步合一架构)${PLAIN}"
    env_cleaner
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
    echo -e "${GREEN}✅ 部署完成。${PLAIN}"; sleep 2; credential_center
}

_generate_master_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import asyncio, websockets, json, os, time, subprocess
from flask import Flask, render_template_string, session, redirect, request, jsonify
from werkzeug.serving import make_server

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
TOKEN = env.get('M_TOKEN', 'admin')
app.secret_key = TOKEN

async def ws_handler(ws):
    addr = ws.remote_address[0]
    sid = str(id(ws))
    try:
        async for msg in ws:
            data = json.loads(msg)
            if data.get('type') == 'auth' and data.get('token') == TOKEN:
                AGENTS[sid] = {
                    "alias": data.get('hostname', 'Node'), "stats": {"cpu":0,"mem":0},
                    "ip": addr, "connected_at": time.strftime("%H:%M:%S"), "last_seen": time.time()
                }
            elif data.get('type') == 'heartbeat' and sid in AGENTS:
                AGENTS[sid]['stats'] = data
                AGENTS[sid].update({"last_seen": time.time()})
    except: pass
    finally:
        if sid in AGENTS: del AGENTS[sid]

@app.route('/api/state')
def api_state():
    now = time.time()
    for sid in list(AGENTS.keys()):
        if now - AGENTS[sid]['last_seen'] > 30: del AGENTS[sid]
    return jsonify({"agents": AGENTS})

@app.route('/api/info')
def api_info():
    e = load_env()
    ip4 = subprocess.getoutput("curl -s4m 1 api.ipify.org || echo 'N/A'")
    ip6 = subprocess.getoutput("curl -s6m 1 api64.ipify.org || echo 'N/A'")
    return jsonify({"token": e.get('M_TOKEN'), "ip4": ip4, "ip6": ip6, "m_port": e.get('M_PORT')})

# --- [ UI 找回：玻璃拟态旗舰仪表盘 ] ---
INDEX_HTML = """
<!DOCTYPE html><html><head><meta charset="UTF-8">
<script src="https://cdn.tailwindcss.com"></script>
<script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
<style>
    body { background: radial-gradient(circle at top right, #0f172a, #020617); color: #fff; min-height: 100vh; }
    .glass { background: rgba(255,255,255,0.02); backdrop-filter: blur(20px); border: 1px solid rgba(255,255,255,0.08); border-radius: 2rem; }
    .status-dot { width: 10px; height: 10px; border-radius: 50%; background: #22c55e; box-shadow: 0 0 15px #22c55e; animation: pulse 2s infinite; }
    @keyframes pulse { 0%, 100% { opacity: 1; transform: scale(1); } 50% { opacity: 0.5; transform: scale(0.8); } }
</style></head>
<body class="p-8 md:p-12" x-data="panel()" x-init="init()">
    <div class="max-w-7xl mx-auto">
        <header class="flex justify-between items-center mb-16">
            <div>
                <h1 class="text-6xl font-black italic tracking-tighter text-blue-600">MULTIY <span class="text-white text-4xl">PRO</span></h1>
                <p class="text-slate-500 font-bold mt-2 uppercase text-xs tracking-widest">Global Node Monitor System</p>
            </div>
            <div class="glass px-8 py-3 flex items-center gap-4">
                <span class="text-xs font-black text-blue-400">WS PORT: 9339</span>
                <div class="h-4 w-px bg-white/10"></div>
                <div class="status-dot"></div>
            </div>
        </header>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            <template x-for="(node, sid) in agents" :key="sid">
                <div class="glass p-10 hover:border-blue-500/50 transition-all group">
                    <div class="flex justify-between items-start mb-8">
                        <div>
                            <h2 class="text-2xl font-black group-hover:text-blue-400 transition-colors" x-text="node.alias"></h2>
                            <code class="text-slate-500 text-[10px]" x-text="node.ip"></code>
                        </div>
                        <div class="text-right"><span class="text-[10px] font-black text-slate-600 uppercase">Connected At</span><div class="text-xs font-bold" x-text="node.connected_at"></div></div>
                    </div>
                    <div class="space-y-6">
                        <div>
                            <div class="flex justify-between text-[10px] font-black uppercase mb-2"><span class="text-slate-400">CPU Load</span><span class="text-blue-400" x-text="node.stats.cpu+'%'"></span></div>
                            <div class="h-1.5 w-full bg-white/5 rounded-full overflow-hidden"><div class="h-full bg-blue-500 transition-all duration-700" :style="'width:'+node.stats.cpu+'%'"></div></div>
                        </div>
                        <div>
                            <div class="flex justify-between text-[10px] font-black uppercase mb-2"><span class="text-slate-400">Memory Usage</span><span class="text-purple-400" x-text="node.stats.mem+'%'"></span></div>
                            <div class="h-1.5 w-full bg-white/5 rounded-full overflow-hidden"><div class="h-full bg-purple-500 transition-all duration-700" :style="'width:'+node.stats.mem+'%'"></div></div>
                        </div>
                    </div>
                </div>
            </template>
        </div>
    </div>
    <script>
        function panel(){ return { agents:{}, init(){ setInterval(async ()=>{const r=await fetch('/api/state');this.agents=(await r.json()).agents}, 2000) } }}
    </script>
</body></html>
"""

HTML_LOGIN = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><script src="https://cdn.tailwindcss.com"></script></head>
<body style="background:#020617;display:flex;justify-content:center;align-items:center;height:100vh;color:#fff;font-family:sans-serif">
<form method="post" style="background:rgba(255,255,255,0.02);padding:60px;border-radius:40px;border:1px solid rgba(255,255,255,0.1);width:360px;text-align:center">
    <h2 style="color:#3b82f6;font-size:2.5rem;font-weight:900;margin-bottom:40px;text-transform:uppercase">Multiy <span style="color:#fff">Pro</span></h2>
    <input name="u" placeholder="Admin Account" style="width:100%;padding:18px;margin:10px 0;background:#000;border:1px solid #333;color:#fff;border-radius:15px;outline:none">
    <input name="p" type="password" placeholder="Terminal Password" style="width:100%;padding:18px;margin:10px 0;background:#000;border:1px solid #333;color:#fff;border-radius:15px;outline:none">
    <button style="width:100%;padding:18px;background:#3b82f6;color:#fff;border:none;border-radius:15px;margin-top:25px;font-weight:900;cursor:pointer;text-transform:uppercase">Access Terminal</button>
</form></body></html>
"""

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST' and request.form.get('u') == env.get('M_USER') and request.form.get('p') == env.get('M_PASS'):
        session['logged'] = True; return redirect('/')
    return render_template_string(HTML_LOGIN)

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(INDEX_HTML)

async def main():
    # 异步合一监听
    ws_server = await websockets.serve(ws_handler, "::", 9339)
    srv = make_server('::', int(env.get('M_PORT', 7575)), app)
    print(f">>> 旗舰主控已就绪 | Web: {env.get('M_PORT')} | WS: 9339")
    await asyncio.gather(asyncio.to_thread(srv.serve_forever), asyncio.Future())

if __name__ == "__main__":
    asyncio.run(main())
EOF
}

# --- [ 3. 被控端安装 (找回自愈功能) ] ---
install_agent() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 旗舰被控 (原生 WS 隧道)${PLAIN}"
    mkdir -p "$M_ROOT/agent"
    read -p "1. 主控域名或IP: " M_INPUT
    read -p "2. 通信令牌 (Token): " M_TOKEN
    
    python3 -m pip install websockets psutil --break-system-packages --user >/dev/null 2>&1

    # 自愈映射：IPv6 数字地址转虚拟域名
    if [[ "$M_INPUT" == *:* ]]; then
        echo -e "${YELLOW}[物理自愈] 正在为 IPv6 执行 hosts 劫持映射...${PLAIN}"
        sed -i "/multiy.local.master/d" /etc/hosts
        echo "$M_INPUT multiy.local.master" >> /etc/hosts
        FINAL_URL="ws://multiy.local.master:9339"
    else
        FINAL_URL="ws://$M_INPUT:9339"
    fi

    cat > "$M_ROOT/agent/agent.py" << 'EOF'
import asyncio, websockets, json, psutil, socket, time
MASTER = "REPLACE_URL"; TOKEN = "REPLACE_TOKEN"
async def run_agent():
    while True:
        try:
            async with websockets.connect(MASTER, ping_interval=20, ping_timeout=20) as ws:
                await ws.send(json.dumps({"type":"auth","token":TOKEN,"hostname":socket.gethostname()}))
                while True:
                    await ws.send(json.dumps({"type":"heartbeat","cpu":int(psutil.cpu_percent()),"mem":int(psutil.virtual_memory().percent)}))
                    await asyncio.sleep(8)
        except: await asyncio.sleep(5)
if __name__ == "__main__": asyncio.run(run_agent())
EOF
    sed -i "s|REPLACE_URL|$FINAL_URL|; s/REPLACE_TOKEN/$M_TOKEN/" "$M_ROOT/agent/agent.py"
    _deploy_service "multiy-agent" "$M_ROOT/agent/agent.py"
    echo -e "${GREEN}✅ 被控端已上线。${PLAIN}"; pause_back
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

# --- [ 4. 链路诊断中心 ] ---
smart_diagnostic() {
    clear; echo -e "${SKYBLUE}🔍 旗舰诊断中心 (原生协议探测)${PLAIN}"
    if [ -f "$M_ROOT/agent/agent.py" ]; then
        A_URL=$(grep "MASTER =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
        echo -e " 🔹 探测 URL: ${SKYBLUE}$A_URL${PLAIN}"
        python3 -c "import websockets, asyncio; asyncio.run(websockets.connect('$A_URL', timeout=5))" >/dev/null 2>&1
        [ $? -eq 0 ] || [ $? -eq 1 ] && echo -e " 👉 状态: ${GREEN}物理链路 OK${PLAIN}" || echo -e " 👉 状态: ${RED}链路 FAIL${PLAIN}"
    else
        echo -e "${RED}[错误]${PLAIN} 未发现 Agent 记录。"
    fi
    pause_back
}

main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro ${SH_VER}${PLAIN}"
    echo " 1. 安装/物理自愈主控 (旗舰合一版)"
    echo " 2. 安装/更新被控 (原生双栈隧道)"
    echo " 3. 实时凭据与监听看板"
    echo " 4. 链路智能诊断中心"
    echo " 5. 深度清理中心 (物理抹除)"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in 
        1) install_master ;; 
        2) install_agent ;; 
        3) credential_center ;;
        4) smart_diagnostic ;;
        5) 
            systemctl stop multiy-master multiy-agent 2>/dev/null
            rm -rf "$M_ROOT"; rm -f /etc/systemd/system/multiy-*; echo "抹除成功"; exit ;; 
        0) exit ;; 
    esac
}

check_root; install_shortcut; main_menu
