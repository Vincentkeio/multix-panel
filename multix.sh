#!/bin/bash
# MultiX V5.5 - 旗舰增强版 (Tailwind UI + Reality 密钥工厂 + 状态自愈 + SQL嗅探)

INSTALL_PATH="/opt/multix_mvp"
MASTER_DOMAIN="multix.spacelite.top"
CONFIG_FILE="${INSTALL_PATH}/.env"

# 颜色定义
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

# 创建必要目录
mkdir -p ${INSTALL_PATH}/master
mkdir -p ${INSTALL_PATH}/agent/db_data

# --- 快捷命令安装逻辑 ---
install_shortcut() {
    cat > /usr/local/bin/multix <<EOF
#!/bin/bash
if [ -f "${INSTALL_PATH}/multix.sh" ]; then
    bash ${INSTALL_PATH}/multix.sh
else
    echo -e "${R}[!] 未找到主脚本 multix.sh${NC}"
fi
EOF
    chmod +x /usr/local/bin/multix
}

# --- 菜单界面 ---
show_menu() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 管理系统 V5.5        "
    echo -e "   Tailwind UI | Reality Factory  "
    echo -e "   一切以主控为准 | 暴力同步模式   "
    echo -e "${G}==================================${NC}"
    echo -e "${Y}[ 部署安装 ]${NC}"
    echo "1. 🚀 安装/重装 主控端 (Master)"
    echo "2. 📡 安装/重装 被控端 (Agent)"
    echo -e "----------------------------------"
    echo -e "${Y}[ 运维管理 ]${NC}"
    echo "3. 🔍 查看配置凭据 (Token/端口)"
    echo "4. 📊 查看服务运行状态"
    echo "5. ⚡ 服务管理 (启动/停止/重启)"
    echo -e "----------------------------------"
    echo "7. 🔧 智能一键修复 (解决端口占用)"
    echo "9. 🗑️  完全卸载 (慎用)"
    echo "0. 🚪 退出"
    echo -e "${G}==================================${NC}"
    read -p "请选择操作 [0-9]: " choice
}

# --- 功能：安装主控端 ---
install_master() {
    echo -e "${G}[+] 启动 V5.5 主控安装向导...${NC}"
    read -p "设置管理 Web 端口 [默认 7575]: " M_PORT
    M_PORT=${M_PORT:-7575}
    read -p "设置管理员账号 [默认 admin]: " M_USER
    M_USER=${M_USER:-admin}
    read -p "设置管理员密码 [默认 admin]: " M_PASS
    M_PASS=${M_PASS:-admin}
    DEF_TOKEN=$(openssl rand -hex 8)
    read -p "设置通信 Token [默认 $DEF_TOKEN]: " M_TOKEN
    M_TOKEN=${M_TOKEN:-$DEF_TOKEN}

    cat > $CONFIG_FILE <<EOF
TYPE=MASTER
M_PORT=$M_PORT
M_USER=$M_USER
M_PASS=$M_PASS
M_TOKEN=$M_TOKEN
EOF

    apt update && apt install -y python3 python3-pip psmisc curl lsof sqlite3
    pip3 install flask websockets psutil cryptography --break-system-packages --quiet 2>/dev/null || pip3 install flask websockets psutil cryptography --quiet

    cat > ${INSTALL_PATH}/master/app.py <<EOF
import json, asyncio, time, psutil, secrets, os, base64
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread
from cryptography.hazmat.primitives.asymmetric import x25519
from cryptography.hazmat.primitives import serialization

app = Flask(__name__)
app.secret_key = "$M_TOKEN"
AGENTS = {} 
LOOP = None
AUTH_TOKEN = "$M_TOKEN"

def generate_x25519():
    priv_key = x25519.X25519PrivateKey.generate()
    pub_key = priv_key.public_key()
    priv_bytes = priv_key.private_bytes(encoding=serialization.Encoding.Raw,format=serialization.PrivateFormat.Raw,encryption_algorithm=serialization.NoEncryption())
    pub_bytes = pub_key.public_bytes(encoding=serialization.Encoding.Raw,format=serialization.PublicFormat.Raw)
    return base64.b64encode(priv_bytes).decode(), base64.b64encode(pub_bytes).decode()

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>MultiX V5.5 Center</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <style> body { font-family: 'Inter', sans-serif; background: #050505; } </style>
</head>
<body class="text-slate-300">
    <div class="flex h-screen">
        <aside class="w-64 bg-zinc-950 border-r border-white/5 p-6 flex flex-col">
            <h1 class="text-xl font-bold text-white flex items-center gap-2 italic">🛰️ MultiX <span class="text-xs bg-blue-600 px-1 rounded not-italic">V5.5</span></h1>
            <nav class="mt-10 space-y-2 flex-1">
                <button onclick="location.reload()" class="w-full text-left p-3 rounded-xl bg-white/5 hover:bg-white/10 transition text-sm">📊 仪表盘总览</button>
            </nav>
            <div class="pt-4 border-t border-white/5"><a href="/logout" class="text-zinc-500 hover:text-red-400 text-sm">🚪 退出系统</a></div>
        </aside>
        <main class="flex-1 p-8 overflow-y-auto">
            <div class="flex justify-between items-center mb-10">
                <h2 class="text-2xl font-bold text-white">集群节点 <span class="text-blue-500">({{ agents_count }})</span></h2>
                <div class="text-xs font-mono bg-zinc-900 border border-white/5 px-4 py-2 rounded-full">Token: <span class="text-yellow-500">{{ auth_token }}</span></div>
            </div>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                {% for ip, info in agents.items() %}
                <div class="bg-zinc-900/50 border border-white/5 rounded-2xl p-6 hover:border-blue-500/50 transition shadow-2xl">
                    <div class="flex justify-between mb-4">
                        <span class="font-bold text-zinc-100">{{ ip }}</span>
                        <span class="flex h-2 w-2 rounded-full bg-green-500 animate-pulse"></span>
                    </div>
                    <div class="flex gap-4 mb-6">
                        <div class="flex-1 bg-black/40 rounded-lg p-2 text-center text-xs text-zinc-500">CPU<br><span class="text-zinc-300">{{ info.stats.cpu }}%</span></div>
                        <div class="flex-1 bg-black/40 rounded-lg p-2 text-center text-xs text-zinc-500">MEM<br><span class="text-zinc-300">{{ info.stats.mem }}%</span></div>
                    </div>
                    <button onclick="openEditor('{{ ip }}')" class="w-full py-2.5 bg-blue-600 hover:bg-blue-500 text-white rounded-xl text-sm font-bold transition">⚙️ 节点管理</button>
                </div>
                {% endfor %}
            </div>
        </main>
    </div>
    <div id="editorModal" class="fixed inset-0 bg-black/90 backdrop-blur-sm hidden items-center justify-center z-50">
        <div class="bg-zinc-900 border border-white/10 w-[500px] rounded-3xl p-8 shadow-2xl">
            <h3 class="text-xl font-bold text-white mb-6">配置推送: <span id="target_ip_display" class="text-blue-400"></span></h3>
            <div class="space-y-4">
                <div><label class="text-[10px] uppercase font-bold text-zinc-500 mb-1 block">UUID</label>
                    <div class="flex gap-2"><input type="text" id="node_uuid" class="flex-1 bg-black border border-white/5 rounded-xl p-3 text-sm focus:border-blue-500 outline-none"><button onclick="genUUID()" class="px-3 bg-zinc-800 rounded-xl hover:bg-zinc-700">🎲</button></div>
                </div>
                <div><label class="text-[10px] uppercase font-bold text-zinc-500 mb-1 block">Reality 私钥</label>
                    <div class="flex gap-2"><input type="text" id="node_priv" class="flex-1 bg-black border border-white/5 rounded-xl p-3 text-sm focus:border-blue-500 outline-none"><button onclick="genKeys()" class="px-3 bg-green-900/20 text-green-500 border border-green-500/20 rounded-xl hover:bg-green-600/30">生成</button></div>
                </div>
                <div><label class="text-[10px] uppercase font-bold text-green-600 mb-1 block italic">Reality 公钥</label>
                    <input type="text" id="node_pub" readonly class="w-full bg-zinc-800/50 border border-dashed border-zinc-700 rounded-xl p-3 text-[10px] text-zinc-500" placeholder="随私钥自动生成">
                </div>
                <div class="flex gap-4 pt-4">
                    <button onclick="closeEditor()" class="flex-1 py-3 bg-zinc-800 rounded-2xl font-bold hover:bg-zinc-700">取消</button>
                    <button onclick="saveSync()" class="flex-1 py-3 bg-blue-600 text-white rounded-2xl font-bold hover:bg-blue-500 shadow-lg shadow-blue-600/20 transition">🚀 强行同步写入</button>
                </div>
            </div>
        </div>
    </div>
    <script>
        let curIP = "";
        const $ = (id) => document.getElementById(id);
        function openEditor(ip) { curIP = ip; $('target_ip_display').innerText = ip; $('editorModal').style.display = 'flex'; }
        function closeEditor() { $('editorModal').style.display = 'none'; }
        function genUUID() { $('node_uuid').value = crypto.randomUUID(); }
        async function genKeys() {
            const r = await fetch('/gen_keys');
            const d = await r.json();
            $('node_priv').value = d.priv;
            $('node_pub').value = d.pub;
        }
        async function saveSync() {
            const data = { ip: curIP, uuid: $('node_uuid').value, priv: $('node_priv').value, port: 443, remark: "V5_REALITY" };
            if(!data.uuid || !data.priv) return alert("请先生成UUID和密钥！");
            const r = await fetch('/send', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(data) });
            const res = await r.json(); alert(res.msg); closeEditor();
        }
    </script>
</body>
</html>
"""

@app.route('/gen_keys')
def g_keys():
    priv, pub = generate_x25519()
    return jsonify({"priv": priv, "pub": pub})

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form['u'] == "$M_USER" and request.form['p'] == "$M_PASS":
            session['logged'] = True
            return redirect('/')
    return '<body style="background:#000;color:#fff;display:flex;justify-content:center;padding-top:100px"><div><h3>MultiX V5.5 Auth</h3><form method="post">User: <input name="u"><br>Pass: <input name="p" type="password"><br><button>Login</button></form></div></body>'

@app.route('/logout')
def logout(): session.clear(); return redirect('/login')

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(HTML_TEMPLATE, agents_count=len(AGENTS), agents=AGENTS, auth_token=AUTH_TOKEN)

@app.route('/send', methods=['POST'])
def send():
    if not session.get('logged'): return jsonify({"msg": "Unauthorized"}), 403
    req = request.json
    node_data = {
        "remark": f"MX-{req['remark']}", "port": int(req['port']), "protocol": "vless",
        "settings": json.dumps({"clients": [{"id": req['uuid'], "flow": "xtls-rprx-vision"}], "decryption": "none"}),
        "stream_settings": json.dumps({"network": "tcp", "security": "reality", "realitySettings": {"show": False, "dest": "www.microsoft.com:443", "serverNames": ["www.microsoft.com"], "privateKey": req['priv'], "shortIds": ["abcdef123456"]}}),
        "sniffing": json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic"]})
    }
    payload = json.dumps({"action": "sync_node", "data": node_data, "token": AUTH_TOKEN})
    if req['ip'] in AGENTS:
        asyncio.run_coroutine_threadsafe(AGENTS[req['ip']]['ws'].send(payload), LOOP)
        return jsonify({"msg": "✅ 指令已送达，被控正在暴力同步..."})
    return jsonify({"msg": "❌ 小鸡离线"}), 404

async def ws_server(websocket):
    ip = websocket.remote_address[0]
    try:
        auth_msg = await asyncio.wait_for(websocket.recv(), timeout=10)
        data = json.loads(auth_msg)
        if data.get('token') != AUTH_TOKEN: return
        AGENTS[ip] = {"ws": websocket, "stats": {"cpu":0, "mem":0}, "fields": data.get('fields', [])}
        async for msg in websocket:
            d = json.loads(msg)
            if d.get('type') == 'heartbeat': AGENTS[ip]['stats'] = d['data']
    finally:
        if ip in AGENTS: del AGENTS[ip]

def start_ws_loop():
    global LOOP
    LOOP = asyncio.new_event_loop()
    asyncio.set_event_loop(LOOP)
    start_server = websockets.serve(ws_server, "0.0.0.0", 8888)
    LOOP.run_until_complete(start_server)
    LOOP.run_forever()

if __name__ == '__main__':
    Thread(target=start_ws_loop, daemon=True).start()
    app.run(host='0.0.0.0', port=$M_PORT)
EOF

    pkill -9 -f app.py 2>/dev/null
    nohup python3 ${INSTALL_PATH}/master/app.py > ${INSTALL_PATH}/master/master.log 2>&1 &
    install_shortcut
    echo -e "${G}🎉 主控部署成功！快捷命令: multix${NC}"
    read -p "按回车继续..."
}

# --- 功能：安装被控端 ---
install_agent() {
    echo -e "${G}--- 被控端安装 (V5.5 嗅探同步版) ---${NC}"
    read -p "请输入主控端 IP 地址: " M_IP
    read -p "请输入主控端通信 Token: " A_TOKEN
    
    apt update && apt install -y sqlite3 docker.io psmisc lsof curl
    mkdir -p ${INSTALL_PATH}/agent/db_data

    cat > ${INSTALL_PATH}/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, subprocess, time
MASTER_WS = "ws://${M_IP}:8888"
TOKEN = "${A_TOKEN}"
DB_PATH = "/app/db_share/x-ui.db"

def get_db_fields():
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("PRAGMA table_info(inbounds)")
        fields = [row[1] for row in cursor.fetchall()]
        conn.close()
        return fields
    except: return []

async def handle_task(task):
    try:
        if task.get('action') == 'sync_node':
            subprocess.run(f"cp {DB_PATH} {DB_PATH}.bak", shell=True)
            subprocess.run("docker stop 3x-ui", shell=True)
            time.sleep(1)
            fields = get_db_fields()
            data = task['data']
            valid_data = {k: v for k, v in data.items() if k in fields}
            conn = sqlite3.connect(DB_PATH)
            keys = ", ".join(valid_data.keys())
            placeholders = ", ".join(["?"] * len(valid_data))
            sql = f"INSERT OR REPLACE INTO inbounds ({keys}) VALUES ({placeholders})"
            conn.execute(sql, list(valid_data.values()))
            conn.commit()
            conn.close()
            subprocess.run("docker start 3x-ui", shell=True)
    except Exception as e: print(f"Error: {e}")

async def run_agent():
    while True:
        try:
            async with websockets.connect(MASTER_WS) as ws:
                await ws.send(json.dumps({"token": TOKEN, "fields": get_db_fields()}))
                while True:
                    stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent)}
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats}))
                    msg = await asyncio.wait_for(ws.recv(), timeout=25)
                    await handle_task(json.loads(msg))
        except: await asyncio.sleep(5)
if __name__ == '__main__': asyncio.run(run_agent())
EOF

    docker pull ghcr.io/mhsanaei/3x-ui:latest
    docker run -d --name 3x-ui --restart always --network host -v ${INSTALL_PATH}/agent/db_data:/etc/x-ui ghcr.io/mhsanaei/3x-ui:latest

    cd ${INSTALL_PATH}/agent
    cat > Dockerfile <<EOF
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
    
    install_shortcut
    echo -e "${G}✅ 被控端部署完成！${NC}"
    read -p "按回车继续..."
}

# --- 执行入口流程 ---
install_shortcut
cp "$0" "$INSTALL_PATH/multix.sh" 2>/dev/null

while true; do
    show_menu
    case $choice in
        1) install_master ;;
        2) install_agent ;;
        3) clear; [ -f $CONFIG_FILE ] && cat $CONFIG_FILE || echo "未发现配置"; read -p "回车继续..." ;;
        5) clear; echo "1. 重启主控 2. 重启被控 0. 返回"; read -p "选择: " s_opt; 
           if [ "$s_opt" == "1" ]; then pkill -9 -f app.py && nohup python3 ${INSTALL_PATH}/master/app.py > /dev/null 2>&1 & echo "已重启"; fi
           if [ "$s_opt" == "2" ]; then docker restart multix-agent 3x-ui && echo "已重启"; fi
           ;;
        9) docker rm -f 3x-ui multix-agent; rm -rf $INSTALL_PATH; exit 0 ;;
        0) exit 0 ;;
    esac
done
