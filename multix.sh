#!/bin/bash
# MultiX V7.8 - 旗舰终极版 (彻底修复通信、SQL嗅探、转义保护)

INSTALL_PATH="/opt/multix_mvp"
CONFIG_FILE="${INSTALL_PATH}/.env"

# 颜色定义
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

# ==========================================
# 模块 A：置顶函数 (环境与嗅探)
# ==========================================

get_ips() {
    echo -e "${Y}[*] 正在嗅探双栈IP...${NC}"
    IPV4=$(curl -4 -s --connect-timeout 5 https://api.ipify.org || echo "N/A")
    IPV6=$(curl -6 -s --connect-timeout 5 https://api64.ipify.org || echo "N/A")
}

force_fix_env() {
    echo -e "${Y}[*] 正在执行系统环境深度自愈 (解决依赖与Docker冲突)...${NC}"
    apt-get purge -y containerd.io docker-ce docker-ce-cli runc 2>/dev/null
    rm -f /var/lib/dpkg/lock* /var/lib/apt/lists/lock
    dpkg --configure -a
    apt-get install -f -y
    apt-get update -y
    apt-get install -y python3 python3-pip python3-full psmisc curl lsof sqlite3 netcat-openbsd build-essential docker.io --no-install-recommends
    systemctl start docker && systemctl enable docker
    python3 -m pip install --upgrade pip --break-system-packages --quiet 2>/dev/null
    python3 -m pip install flask websockets psutil cryptography docker --break-system-packages --quiet 2>/dev/null
}

# ==========================================
# 模块 B：主控安装 (Master)
# ==========================================

install_master() {
    echo -e "${G}[+] 启动 V7.8 主控安装向导...${NC}"
    read -p "设置 Web 端口 [7575]: " M_PORT
    M_PORT=${M_PORT:-7575}
    read -p "管理账号 [admin]: " M_USER
    M_USER=${M_USER:-admin}
    read -p "管理密码 [admin]: " M_PASS
    M_PASS=${M_PASS:-admin}
    DEF_TOKEN=$(openssl rand -hex 8)
    read -p "通讯 Token [默认 $DEF_TOKEN]: " M_TOKEN
    M_TOKEN=${M_TOKEN:-$DEF_TOKEN}

    get_ips
    mkdir -p "${INSTALL_PATH}/master/db_data"
    
    # 核心：启动主控 3X-UI 引擎容器 (用于 SQL 嗅探和密钥生成)
    docker rm -f 3x-ui-master 2>/dev/null
    docker run -d --name 3x-ui-master --restart always --network host -v ${INSTALL_PATH}/master/db_data:/etc/x-ui ghcr.io/mhsanaei/3x-ui:latest

    cat > "$CONFIG_FILE" <<EOF
TYPE="MASTER"
M_PORT="$M_PORT"
M_USER="$M_USER"
M_PASS="$M_PASS"
M_TOKEN="$M_TOKEN"
IPV4="$IPV4"
IPV6="$IPV6"
EOF

    # 完整生成主控核心 (使用单引号 EOF 确保 JS 不会报错)
    cat > "${INSTALL_PATH}/master/app.py" <<'EOF'
import json, asyncio, time, psutil, secrets, os, base64, sqlite3, subprocess
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread

# 加载配置
CONFIG = {}
if os.path.exists("../.env"):
    with open("../.env") as f:
        for l in f:
            if '=' in l:
                k, v = l.replace('"', '').split('=', 1)
                CONFIG[k.strip()] = v.strip()

app = Flask(__name__)
app.secret_key = CONFIG.get('M_TOKEN', 'secret')
AGENTS = {} 
LOOP = None
AUTH_TOKEN = CONFIG.get('M_TOKEN', 'token')

# HTML 仪表盘模板 (Vue 3 + Tailwind)
HTML_TEMPLATE = """
<!DOCTYPE html>
<html class="dark">
<head>
    <meta charset="UTF-8"><title>MultiX Master Center</title>
    <script src="https://unpkg.com/vue@3/dist/vue.global.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style> body { font-family: 'Inter', sans-serif; background: #050505; color: #e2e8f0; } </style>
</head>
<body>
    <div id="app" class="flex h-screen">
        <aside class="w-64 bg-zinc-950 border-r border-white/5 p-6 flex flex-col shadow-2xl">
            <h1 class="text-xl font-bold text-white italic mb-10 flex items-center gap-2">🛰️ MultiX <span class="text-xs bg-blue-600 px-1 rounded not-italic">V7.8</span></h1>
            <nav class="space-y-2 flex-1">
                <button @click="location.reload()" class="w-full text-left p-3 rounded-xl bg-white/5 text-white text-sm">📊 仪表盘总览</button>
            </nav>
            <div class="pt-6 border-t border-white/5"><a href="/logout" class="text-zinc-500 hover:text-red-400 text-xs">🚪 退出系统</a></div>
        </aside>

        <main class="flex-1 overflow-y-auto p-10">
            <header class="flex justify-between items-center mb-12">
                <div><h2 class="text-3xl font-bold text-white">集群节点控制</h2><p class="text-zinc-500 text-sm mt-1">上帝视角管理所有被控小鸡</p></div>
                <div class="text-xs font-mono bg-zinc-900 border border-white/5 px-4 py-2 rounded-full text-yellow-500">Master Token: {{ authToken }}</div>
            </header>

            <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
                <div v-for="(info, ip) in agents" :key="ip" class="bg-zinc-900/50 border border-white/5 rounded-3xl p-6 hover:border-blue-500/30 transition shadow-xl">
                    <div class="flex justify-between mb-6">
                        <span class="font-bold text-white">{{ ip }}</span>
                        <span class="h-2 w-2 rounded-full bg-green-500 animate-pulse"></span>
                    </div>
                    <div class="grid grid-cols-2 gap-3 mb-6">
                        <div class="bg-black/40 rounded-xl p-3 text-center border border-white/5">
                            <div class="text-[10px] text-zinc-500 uppercase">CPU负载</div>
                            <div class="text-sm font-bold text-zinc-200">{{ info.stats.cpu }}%</div>
                        </div>
                        <div class="bg-black/40 rounded-xl p-3 text-center border border-white/5">
                            <div class="text-[10px] text-zinc-500 uppercase">内存</div>
                            <div class="text-sm font-bold text-zinc-200">{{ info.stats.mem }}%</div>
                        </div>
                    </div>
                    <div class="flex gap-2">
                        <button @click="openEditor(ip)" class="flex-1 py-2.5 bg-zinc-800 hover:bg-zinc-700 text-xs font-bold rounded-xl transition">配置管理</button>
                        <button class="px-4 py-2.5 bg-blue-600 hover:bg-blue-500 text-white rounded-xl transition">🚀</button>
                    </div>
                </div>
            </div>
        </main>

        <div v-if="editor.show" class="fixed inset-0 z-50 flex justify-end">
            <div class="absolute inset-0 bg-black/80" @click="editor.show = false"></div>
            <div class="relative w-[450px] bg-zinc-950 border-l border-white/10 p-8 shadow-2xl">
                <h3 class="text-xl font-bold text-white mb-8">同步节点: <span class="text-blue-500">{{ editor.ip }}</span></h3>
                <div class="space-y-6">
                    <div>
                        <label class="text-[10px] uppercase font-bold text-zinc-500 mb-1 block">UUID</label>
                        <input v-model="editor.data.uuid" class="w-full bg-black border border-white/10 rounded-xl p-3 text-sm focus:border-blue-500 outline-none">
                    </div>
                    <div>
                        <label class="text-[10px] uppercase font-bold text-zinc-500 mb-1 block">Reality Private Key</label>
                        <div class="flex gap-2">
                            <input v-model="editor.data.priv" class="flex-1 bg-black border border-white/10 rounded-xl p-3 text-xs font-mono outline-none">
                            <button @click="genKeys" class="px-4 bg-zinc-800 hover:bg-zinc-700 rounded-xl">🎲</button>
                        </div>
                    </div>
                    <div class="pt-10 flex gap-4">
                        <button @click="editor.show = false" class="flex-1 py-4 bg-zinc-900 rounded-2xl font-bold">取消</button>
                        <button @click="submitConfig" class="flex-1 py-4 bg-blue-600 rounded-2xl font-bold">🚀 立即下发</button>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        const { createApp, ref, onMounted } = Vue;
        createApp({
            setup() {
                const agents = ref({});
                const authToken = ref('');
                const editor = ref({show: false, ip: '', data: {uuid: '', priv: ''}});

                const update = async () => {
                    const r = await fetch('/api/state');
                    const d = await r.json();
                    agents.value = d.agents;
                    authToken.value = d.token;
                };

                const genKeys = async () => {
                    const r = await fetch('/api/gen_keys');
                    const d = await r.json();
                    editor.value.data.priv = d.priv;
                };

                const openEditor = (ip) => {
                    editor.value.ip = ip;
                    editor.value.show = true;
                };

                const submitConfig = async () => {
                    const r = await fetch('/api/send', {
                        method: 'POST',
                        headers: {'Content-Type': 'application/json'},
                        body: JSON.stringify({ip: editor.value.ip, ...editor.value.data})
                    });
                    const res = await r.json();
                    alert(res.msg);
                    editor.value.show = false;
                };

                onMounted(() => { update(); setInterval(update, 3000); });
                return { agents, authToken, editor, openEditor, genKeys, submitConfig };
            }
        }).mount('#app');
    </script>
</body>
</html>
"""

@app.route('/api/state')
def get_state():
    return jsonify({
        "agents": {ip: {"stats": info["stats"]} for ip, info in AGENTS.items()},
        "token": AUTH_TOKEN
    })

@app.route('/api/gen_keys')
def api_gen_keys():
    # 调用主控容器内的 xray 生成
    res = subprocess.check_output("docker exec 3x-ui-master /usr/local/bin/xray x25519", shell=True).decode()
    priv = res.split('\n')[0].split(': ')[1]
    return jsonify({"priv": priv})

@app.route('/api/send', methods=['POST'])
def api_send():
    req = request.json
    node_data = {
        "remark": f"MX-V7", "port": 443, "protocol": "vless",
        "settings": json.dumps({"clients": [{"id": req['uuid'], "flow": "xtls-rprx-vision"}], "decryption": "none"}),
        "stream_settings": json.dumps({"network": "tcp", "security": "reality", "realitySettings": {"show": False, "dest": "www.microsoft.com:443", "serverNames": ["www.microsoft.com"], "privateKey": req['priv'], "shortIds": ["abcdef123456"]}}),
        "sniffing": json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic"]})
    }
    payload = json.dumps({"action": "sync_node", "data": node_data, "token": AUTH_TOKEN})
    if req['ip'] in AGENTS:
        asyncio.run_coroutine_threadsafe(AGENTS[req['ip']]['ws'].send(payload), LOOP)
        return jsonify({"msg": "✅ 配置已发送至被控端队列"})
    return jsonify({"msg": "❌ 被控节点离线"}), 404

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(HTML_TEMPLATE)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form['u'] == CONFIG.get('M_USER') and request.form['p'] == CONFIG.get('M_PASS'):
            session['logged'] = True
            return redirect('/')
    return '<h3>Auth</h3><form method="post">User: <input name="u"><br>Pass: <input name="p" type="password"><br><button>Login</button></form>'

@app.route('/logout')
def logout(): session.clear(); return redirect('/login')

async def ws_server(websocket):
    ip = websocket.remote_address[0]
    try:
        # 严格握手逻辑
        auth_msg = await asyncio.wait_for(websocket.recv(), timeout=15)
        data = json.loads(auth_msg)
        if data.get('token') != AUTH_TOKEN:
            print(f"Auth Failed for {ip}")
            return
        
        AGENTS[ip] = {"ws": websocket, "stats": {"cpu":0, "mem":0}}
        print(f"Agent Connected: {ip}")
        
        async for msg in websocket:
            d = json.loads(msg)
            if d.get('type') == 'heartbeat':
                AGENTS[ip]['stats'] = d['data']
    except Exception as e:
        print(f"WS Error: {e}")
    finally:
        if ip in AGENTS: del AGENTS[ip]

def start_ws_loop():
    global LOOP
    LOOP = asyncio.new_event_loop()
    asyncio.set_event_loop(LOOP)
    start_server = websockets.serve(ws_server, "0.0.0.0", 8888)
    LOOP.run_until_complete(start_server); LOOP.run_forever()

if __name__ == '__main__':
    Thread(target=start_ws_loop, daemon=True).start()
    app.run(host='0.0.0.0', port=int(CONFIG.get('M_PORT', 7575)))
EOF

    pkill -9 -f app.py 2>/dev/null
    nohup python3 ${INSTALL_PATH}/master/app.py > ${INSTALL_PATH}/master/master.log 2>&1 &
    
    echo -e "${G}🎉 MultiX V7.8 主控部署完成！${NC}"
    echo -e "访问链接: http://$IPV4:$M_PORT"
    read -p "按回车继续..."
}

# ==========================================
# 模块 C：被控安装 (Agent) - 彻底修复通信
# ==========================================

install_agent() {
    echo -e "${G}--- 被控端安装 (通信补强版) ---${NC}"
    read -p "请输入主控 域名/IP: " M_HOST
    read -p "请输入主控 Token: " A_TOKEN
    
    get_ips
    mkdir -p ${INSTALL_PATH}/agent/db_data

    # 生成被控 Python 脚本 (修复了 WebSocket 发送格式)
    cat > ${INSTALL_PATH}/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, subprocess, time, socket

MASTER_HOST = "${M_HOST}"
TOKEN = "${A_TOKEN}"
DB_PATH = "/app/db_share/x-ui.db"

def get_db_fields():
    try:
        conn = sqlite3.connect(DB_PATH); cursor = conn.cursor()
        cursor.execute("PRAGMA table_info(inbounds)")
        fields = [row[1] for row in cursor.fetchall()]; conn.close()
        return fields
    except: return []

async def handle_task(task):
    try:
        if task.get('action') == 'sync_node':
            subprocess.run("docker stop 3x-ui", shell=True)
            fields = get_db_fields()
            data = task['data']
            valid_data = {k: v for k, v in data.items() if k in fields}
            conn = sqlite3.connect(DB_PATH)
            keys = ", ".join(valid_data.keys()); placeholders = ", ".join(["?"] * len(valid_data))
            conn.execute(f"INSERT OR REPLACE INTO inbounds ({keys}) VALUES ({placeholders})", list(valid_data.values()))
            conn.commit(); conn.close()
            subprocess.run("docker start 3x-ui", shell=True)
    except Exception as e: print(f"Error: {e}")

async def run_agent():
    # 强制尝试通过域名或IP建立连接 (双栈自适应)
    uri = f"ws://{MASTER_HOST}:8888"
    while True:
        try:
            print(f"Connecting to {uri}...")
            async with websockets.connect(uri, family=socket.AF_UNSPEC, timeout=10) as ws:
                # 握手包：必须包含 token
                await ws.send(json.dumps({"token": TOKEN, "type": "auth"}))
                print("Auth sent.")
                while True:
                    stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent)}
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats}))
                    msg = await asyncio.wait_for(ws.recv(), timeout=25)
                    await handle_task(json.loads(msg))
        except Exception as e:
            print(f"Connection failed: {e}, retrying in 5s...")
            await asyncio.sleep(5)

if __name__ == '__main__': asyncio.run(run_agent())
EOF

    # 强制拉取镜像
    docker pull ghcr.io/mhsanaei/3x-ui:latest
    docker rm -f 3x-ui 2>/dev/null
    docker run -d --name 3x-ui --restart always --network host -v ${INSTALL_PATH}/agent/db_data:/etc/x-ui ghcr.io/mhsanaei/3x-ui:latest

    cd ${INSTALL_PATH}/agent
    cat > Dockerfile <<'EOF'
FROM python:3.11-slim
RUN pip install --no-cache-dir websockets psutil
WORKDIR /app
CMD ["python", "-u", "agent.py"]
EOF
    docker build -t multix-agent-image .
    docker rm -f multix-agent 2>/dev/null
    docker run -d --name multix-agent --restart always --network host \
      -v /var/run/docker.sock:/var/run/docker.sock -v ${INSTALL_PATH}/agent:/app \
      -v ${INSTALL_PATH}/agent/db_data:/app/db_share multix-agent-image

    echo -e "${G}✅ 被控端部署完成！已启动通信守护。${NC}"
}

# ==========================================
# 模块 D：入口
# ==========================================

show_menu() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 管理系统 V7.8        "
    echo -e "   通信死锁修复 | 全功能增强版     "
    echo -e "${G}==================================${NC}"
    echo "1. 🚀 安装/重装 主控端 (Master)"
    echo "2. 📡 安装/重装 被控端 (Agent)"
    echo "----------------------------------"
    echo "3. 🔍 查看配置凭据"
    echo "7. 🧹 深度环境修复 (APT冲突必选)"
    echo "9. 🗑️  完全卸载"
    echo "0. 退出"
    echo -e "${G}==================================${NC}"
    read -p "请选择 [0-9]: " choice
    case $choice in
        1) force_fix_env && install_master ;;
        2) force_fix_env && install_agent ;;
        3) [ -f "$CONFIG_FILE" ] && cat "$CONFIG_FILE" || echo "无配置"; read -p "继续..." ;;
        7) force_fix_env ;;
        9) docker rm -f 3x-ui multix-agent 3x-ui-master; rm -rf $INSTALL_PATH; exit 0 ;;
        0) exit 0 ;;
        *) show_menu ;;
    esac
}

mkdir -p "$INSTALL_PATH"
show_menu
