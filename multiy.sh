#!/bin/bash
# Multiy Pro V135.0-ULTIMATE - 终极全功能旗舰版 (旗舰 UI + 异步合一)

export M_ROOT="/opt/multiy_mvp"
SH_VER="V135.0-ULTIMATE"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 基础工具 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[错误]${PLAIN} 需 Root 权限!" && exit 1; }
install_shortcut() { [ ! -f /usr/bin/multiy ] && cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy; }
pause_back() { echo -e "\n${YELLOW}按任意键返回主菜单...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 环境清理与检测 ] ---
env_cleaner() {
    echo -e "${YELLOW}>>> 正在深度清理冗余组件并重建 Python 异步环境...${PLAIN}"
    systemctl stop multiy-master multiy-agent 2>/dev/null
    pkill -9 python3 2>/dev/null
    python3 -m pip uninstall -y python-socketio eventlet python-engineio websockets flask 2>/dev/null
    python3 -m pip install flask websockets psutil --break-system-packages --user >/dev/null 2>&1
}

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
    echo -e " 🔹 IPv6: http://[$V6]:$M_PORT"
    echo -e " 🔹 管理员: ${YELLOW}$M_USER${PLAIN} / 密码: ${YELLOW}$M_PASS${PLAIN}"
    echo -e "\n${GREEN}[ 2. 被控接入 (WS 协议) ]${PLAIN}"
    echo -e " 🔹 主控地址: ${SKYBLUE}$M_HOST${PLAIN}"
    echo -e " 🔹 接入端口: ${SKYBLUE}9339${PLAIN}"
    echo -e " 🔹 校验令牌: ${YELLOW}$M_TOKEN${PLAIN}"
    echo -e "\n${GREEN}[ 3. 物理监听状态 ]${PLAIN}"
    check_v4v6() { ss -tuln | grep -q ":$1 " && echo -e "${GREEN}● OK${PLAIN}" || echo -e "${RED}○ OFF${PLAIN}"; }
    echo -e " 🔹 面板端口 ($M_PORT): $(check_v4v6 $M_PORT)"
    echo -e " 🔹 通信端口 (9339): $(check_v4v6 9339)"
    echo -e "${SKYBLUE}==================================================${PLAIN}"
    pause_back
}

# --- [ 2. 主控安装 ] ---
install_master() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 旗舰主控 (V135.0)${PLAIN}"
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
def api_state(): return jsonify({"agents": AGENTS})

INDEX_HTML = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Multiy Pro Dashboard</title>
<script src="https://cdn.tailwindcss.com"></script>
<script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;600;800&display=swap" rel="stylesheet">
<style>
    body { background: #020617; color: #fff; font-family: 'Plus Jakarta Sans', sans-serif; }
    .glass { background: rgba(255,255,255,0.01); backdrop-filter: blur(20px); border: 1px solid rgba(255,255,255,0.08); border-radius: 2rem; }
</style></head>
<body class="p-8 md:p-12" x-data="{ agents: {}, init() { setInterval(async () => { const r = await fetch('/api/state'); const d = await r.json(); this.agents = d.agents; }, 2000) } }">
    <div class="max-w-7xl mx-auto">
        <header class="flex justify-between items-center mb-16">
            <h1 class="text-5xl font-extrabold italic tracking-tighter text-blue-600">MULTIY <span class="text-white text-3xl">PRO</span></h1>
            <div class="glass px-6 py-2 text-[10px] font-black uppercase tracking-widest text-blue-500">WebSocket Tunnel Active</div>
        </header>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            <template x-for="(n, sid) in agents" :key="sid">
                <div class="glass p-10 hover:border-blue-500/50 transition-all">
                    <div class="flex justify-between mb-8">
                        <div><h3 class="text-2xl font-bold" x-text="n.alias"></h3><code class="text-blue-400 text-[10px]" x-text="n.ip"></code></div>
                        <span class="w-3 h-3 bg-green-500 rounded-full animate-pulse shadow-[0_0_15px_#22c55e]"></span>
                    </div>
                    <div class="space-y-6">
                        <div>
                            <div class="flex justify-between text-[10px] font-bold mb-2"><span>CPU</span><span x-text="n.stats.cpu+'%'"></span></div>
                            <div class="h-1.5 w-full bg-white/5 rounded-full overflow-hidden"><div class="h-full bg-blue-500 transition-all duration-700" :style="'width:'+n.stats.cpu+'%'"></div></div>
                        </div>
                        <div>
                            <div class="flex justify-between text-[10px] font-bold mb-2"><span>MEMORY</span><span x-text="n.stats.mem+'%'"></span></div>
                            <div class="h-1.5 w-full bg-white/5 rounded-full overflow-hidden"><div class="h-full bg-purple-500 transition-all duration-700" :style="'width:'+n.stats.mem+'%'"></div></div>
                        </div>
                    </div>
                </div>
            </template>
        </div>
    </div>
</body></html>
"""

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(INDEX_HTML)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST' and request.form.get('u') == env.get('M_USER') and request.form.get('p') == env.get('M_PASS'):
        session['logged'] = True; return redirect('/')
    return render_template_string('''<body style="background:#020617;color:#fff;display:flex;justify-content:center;align-items:center;height:100vh;font-family:sans-serif"><form method="post" style="background:rgba(255,255,255,0.02);padding:60px;border-radius:40px;border:1px solid rgba(255,255,255,0.1);width:340px;text-align:center"><h2 style="color:#3b82f6;font-size:2.5rem;font-weight:900;margin-bottom:40px;letter-spacing:-2px">MULTIY PRO</h2><input name="u" placeholder="Admin" style="width:100%;padding:18px;margin:10px 0;background:#000;border:1px solid #333;color:#fff;border-radius:15px;outline:none"><input name="p" type="password" placeholder="Pass" style="width:100%;padding:18px;margin:10px 0;background:#000;border:1px solid #333;color:#fff;border-radius:15px;outline:none"><button style="width:100%;padding:18px;background:#3b82f6;color:#fff;border:none;border-radius:15px;margin-top:25px;font-weight:900;cursor:pointer;text-transform:uppercase">Enter Terminal</button></form></body>''')

async def main():
    ws_server = await websockets.serve(ws_handler, "::", 9339)
    srv = make_server('::', int(env.get('M_PORT', 7575)), app)
    print(f">>> Multiy Master Running...")
    await asyncio.gather(asyncio.to_thread(srv.serve_forever), asyncio.Future())

if __name__ == "__main__":
    asyncio.run(main())
EOF
}

# --- [ 3. 被控安装 ] ---
install_agent() {
    clear; echo -e "${SKYBLUE}>>> 部署 Multiy 旗舰被控 (自动双栈适配)${PLAIN}"
    mkdir -p "$M_ROOT/agent"
    read -p "1. 主控地址 (域名/IP): " M_INPUT
    read -p "2. 通信令牌 (Token): " M_TOKEN
    
    python3 -m pip install websockets psutil --break-system-packages --user >/dev/null 2>&1

    if [[ "$M_INPUT" == *:* ]]; then
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
            async with websockets.connect(MASTER, ping_interval=20) as ws:
                await ws.send(json.dumps({"type":"auth","token":TOKEN,"hostname":socket.gethostname()}))
                while True:
                    await ws.send(json.dumps({"type":"heartbeat","cpu":int(psutil.cpu_percent()),"mem":int(psutil.virtual_memory().percent)}))
                    await asyncio.sleep(8)
        except: await asyncio.sleep(5)
if __name__ == "__main__": asyncio.run(run_agent())
EOF
    sed -i "s|REPLACE_URL|$FINAL_URL|; s/REPLACE_TOKEN/$M_TOKEN/" "$M_ROOT/agent/agent.py"
    _deploy_service "multiy-agent" "$M_ROOT/agent/agent.py"
    echo -e "${GREEN}✅ 被控端已启动。${PLAIN}"; pause_back
}

_deploy_service() {
    local NAME=$1; local EXEC=$2
    cat > "/etc/systemd/system/${NAME}.service" << EOF
[Unit]
Description=${NAME} Service
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

# --- [ 菜单中心 ] ---
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro ${SH_VER}${PLAIN}"
    echo " 1. 安装/物理修复主控 (旗舰合一架构)"
    echo " 2. 安装/更新被控 (原生双栈隧道)"
    echo " 3. 实时凭据看板 (配置详情)"
    echo " 4. 链路诊断中心 (物理连接测试)"
    echo " 5. 服务状态监控 (systemd 查看)"
    echo " 6. 深度清理中心 (物理抹除)"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in 
        1) install_master ;; 
        2) install_agent ;; 
        3) credential_center ;;
        4) [ -f "$M_ROOT/agent/agent.py" ] && python3 -c "import websockets, asyncio; asyncio.run(websockets.connect('$(grep "MASTER =" $M_ROOT/agent/agent.py | cut -d'"' -f2)', timeout=5))" && echo "连接正常" || echo "异常"; pause_back ;;
        5) systemctl status multiy-master multiy-agent; pause_back ;;
        6) systemctl stop multiy-master multiy-agent; rm -rf "$M_ROOT"; rm -f /etc/systemd/system/multiy-*; echo "已清理"; exit ;; 
        0) exit ;; 
    esac
}

check_root; install_shortcut; main_menu
