#!/bin/bash
# MultiX V5.8 - 最终旗舰版 (智能感知识别 + 拨测集成 + 密钥工厂)

INSTALL_PATH="/opt/multix_mvp"
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

# --- 身份识别 ---
IS_MASTER=false
IS_AGENT=false
[ -f "$INSTALL_PATH/master/app.py" ] && IS_MASTER=true
[ -f "$INSTALL_PATH/agent/agent.py" ] && IS_AGENT=true

# --- 快捷命令安装 ---
install_shortcut() {
    cat > /usr/local/bin/multix <<EOF
#!/bin/bash
if [ -f "$INSTALL_PATH/multix.sh" ]; then
    bash $INSTALL_PATH/multix.sh
else
    echo -e "${R}[!] 未找到主脚本 $INSTALL_PATH/multix.sh${NC}"
fi
EOF
    chmod +x /usr/local/bin/multix
}

# --- 核心逻辑：智能拨测 ---
smart_test() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 智能拨测系统 V5.8      "
    echo -e "${G}==================================${NC}"

    if [ "$IS_MASTER" = true ]; then
        echo -e "${Y}[主控自检模式]${NC}"
        echo -n "  Web 页面 (7575): "
        nc -zt 127.0.0.1 7575 &>/dev/null && echo -e "${G}ONLINE${NC}" || echo -e "${R}OFFLINE${NC}"
        echo -n "  WS 接口 (8888): "
        nc -zt 127.0.0.1 8888 &>/dev/null && echo -e "${G}ONLINE${NC}" || echo -e "${R}OFFLINE${NC}"
        echo -n "  Docker 加密引擎: "
        docker ps | grep -q "multix-engine" && echo -e "${G}READY${NC}" || echo -e "${R}STOPPED${NC}"
    elif [ "$IS_AGENT" = true ]; then
        echo -e "${Y}[被控链路拨测模式]${NC}"
        A_WS=$(grep "MASTER_WS =" "$INSTALL_PATH/agent/agent.py" | cut -d'"' -f2)
        A_IP=$(echo $A_WS | cut -d'/' -f3 | cut -d':' -f1)
        echo -n "  主控链路拨测 ($A_IP): "
        nc -ztw 3 $A_IP 8888 &>/dev/null && echo -e "${G}通畅${NC}" || echo -e "${R}阻塞 (请检查主控防火墙)${NC}"
        echo -e "${Y}  实时握手日志:${NC}"
        docker logs --tail 10 multix-agent
    else
        echo -e "${R}[!] 尚未安装任何端，请先进行安装。${NC}"
    fi
    echo -e "${G}==================================${NC}"
    read -p "按回车返回菜单..."
}

# --- 核心逻辑：主控安装 ---
install_master() {
    echo -e "${Y}[*] 正在拉取 Docker 加密引擎 (3x-ui)...${NC}"
    docker pull ghcr.io/mhsanaei/3x-ui:latest &>/dev/null
    docker rm -f multix-engine 2>/dev/null
    docker run -d --name multix-engine -p 2053:2053 --restart always ghcr.io/mhsanaei/3x-ui:latest &>/dev/null

    read -p "设置 Web 端口 [7575]: " M_PORT
    M_PORT=${M_PORT:-7575}
    M_TOKEN=$(openssl rand -hex 8)
    read -p "设置通信 Token [$M_TOKEN]: " FINAL_TOKEN
    FINAL_TOKEN=${FINAL_TOKEN:-$M_TOKEN}

    mkdir -p ${INSTALL_PATH}/master
    cat > ${INSTALL_PATH}/master/app.py <<EOF
import json, asyncio, time, psutil, os, base64, subprocess
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread

app = Flask(__name__)
app.secret_key = "$FINAL_TOKEN"
AGENTS = {} 
LOOP = None
AUTH_TOKEN = "$FINAL_TOKEN"

def get_keys():
    try:
        out = subprocess.check_output("docker exec multix-engine xray x25519", shell=True).decode()
        lines = [l for l in out.split('\\n') if l.strip()]
        return lines[0].split(': ')[1].strip(), lines[1].split(': ')[1].strip()
    except: return "Error", "Error"

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8"><title>MultiX V5.8</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-black text-gray-300">
    <div class="flex h-screen">
        <div class="w-64 bg-zinc-950 border-r border-white/10 p-6">
            <h1 class="text-xl font-bold text-white italic">🛰️ MultiX V5.8</h1>
            <div class="mt-8 text-xs text-zinc-500 font-mono">Token: {{ auth_token }}</div>
            <button onclick="location.reload()" class="w-full mt-10 p-3 bg-blue-600 rounded-xl font-bold hover:bg-blue-500">刷新节点</button>
        </div>
        <div class="flex-1 p-10 overflow-y-auto">
            <h2 class="text-2xl font-bold mb-8 text-white">在线小鸡 ({{ agents_count }})</h2>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                {% for ip, info in agents.items() %}
                <div class="bg-zinc-900 border border-white/5 p-6 rounded-3xl hover:border-blue-500/50 transition">
                    <div class="flex justify-between mb-4"><b>{{ ip }}</b><span class="w-3 h-3 bg-green-500 rounded-full animate-pulse shadow-[0_0_8px_rgba(34,197,94,0.6)]"></span></div>
                    <button onclick="openEdit('{{ ip }}')" class="w-full py-2 bg-zinc-800 hover:bg-blue-600 rounded-lg text-sm transition font-bold">配置管理</button>
                </div>
                {% endfor %}
            </div>
        </div>
    </div>
    <div id="modal" class="fixed inset-0 bg-black/90 hidden items-center justify-center z-50">
        <div class="bg-zinc-900 w-[450px] p-8 rounded-[32px] border border-white/10 shadow-2xl">
            <h3 class="text-white mb-6 font-bold text-lg">配置推送: <span id="tip" class="text-blue-500"></span></h3>
            <div class="space-y-4">
                <input id="uuid" placeholder="节点 UUID" class="w-full bg-black border border-white/5 p-3 rounded-xl text-sm focus:border-blue-500 outline-none">
                <div class="flex gap-2"><input id="priv" placeholder="Reality 私钥" class="flex-1 bg-black border border-white/5 p-3 rounded-xl text-sm focus:border-blue-500 outline-none"><button onclick="gk()" class="bg-green-600/20 text-green-500 px-4 rounded-xl text-xs font-bold border border-green-500/20">生成密钥</button></div>
                <input id="pub" readonly placeholder="Reality 公钥 (随私钥同步生成)" class="w-full bg-zinc-800/30 p-3 rounded-xl text-[10px] text-zinc-500 border-dashed border border-zinc-700 outline-none">
                <div class="flex gap-4 pt-4"><button onclick="closeM()" class="flex-1 py-3 bg-zinc-800 rounded-xl">取消</button><button onclick="ss()" class="flex-1 py-3 bg-blue-600 text-white font-bold rounded-xl shadow-lg">🚀 同步下发</button></div>
            </div>
        </div>
    </div>
    <script>
        let cur = "";
        function openEdit(ip) { cur = ip; document.getElementById('tip').innerText = ip; document.getElementById('modal').style.display = 'flex'; }
        function closeM() { document.getElementById('modal').style.display = 'none'; }
        async function gk() { const r = await fetch('/gen_keys'); const d = await r.json(); document.getElementById('priv').value = d.priv; document.getElementById('pub').value = d.pub; }
        async function ss() {
            const data = { ip: cur, uuid: document.getElementById('uuid').value, priv: document.getElementById('priv').value };
            const r = await fetch('/send', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(data) });
            const res = await r.json(); alert(res.msg); closeM();
        }
    </script>
</body>
</html>
"""

@app.route('/gen_keys')
def g_keys():
    priv, pub = get_keys()
    return jsonify({"priv": priv, "pub": pub})

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form['u'] == "admin" and request.form['p'] == "admin":
            session['logged'] = True
            return redirect('/')
    return '<body style="background:#000;color:#fff;padding:100px"><h3>MultiX V5.8 Auth</h3><form method="post"><input name="u" placeholder="Admin"><input name="p" type="password" placeholder="Pass"><button>Go</button></form></body>'

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(HTML_TEMPLATE, agents_count=len(AGENTS), agents=AGENTS, auth_token=AUTH_TOKEN)

@app.route('/send', methods=['POST'])
def send():
    req = request.json
    node_data = {"remark": "V58_Reality", "port": 443, "protocol": "vless", "settings": json.dumps({"clients": [{"id": req['uuid'], "flow": "xtls-rprx-vision"}]}), "stream_settings": json.dumps({"network": "tcp", "security": "reality", "realitySettings": {"privateKey": req['priv'], "dest": "www.microsoft.com:443", "serverNames": ["www.microsoft.com"]}}), "sniffing": json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic"]})}
    payload = json.dumps({"action": "sync_node", "data": node_data, "token": AUTH_TOKEN})
    if req['ip'] in AGENTS:
        asyncio.run_coroutine_threadsafe(AGENTS[req['ip']]['ws'].send(payload), LOOP)
        return jsonify({"msg": "✅ 已下发至小鸡"})
    return jsonify({"msg": "❌ 小鸡离线"})

async def ws_server(websocket):
    ip = websocket.remote_address[0]
    try:
        auth = await asyncio.wait_for(websocket.recv(), timeout=10)
        if json.loads(auth).get('token') != AUTH_TOKEN: return
        AGENTS[ip] = {"ws": websocket, "stats": {"cpu":0, "mem":0}}
        async for msg in websocket: pass
    finally:
        if ip in AGENTS: del AGENTS[ip]

def run_loop():
    global LOOP
    LOOP = asyncio.new_event_loop(); asyncio.set_event_loop(LOOP)
    LOOP.run_until_complete(websockets.serve(ws_server, "0.0.0.0", 8888))
    LOOP.run_forever()

if __name__ == '__main__':
    Thread(target=run_loop, daemon=True).start()
    app.run(host='0.0.0.0', port=$M_PORT)
EOF
    pkill -9 -f app.py
    nohup python3 ${INSTALL_PATH}/master/app.py > /dev/null 2>&1 &
    install_shortcut
    IS_MASTER=true
    echo -e "${G}✅ 主控端部署成功！Token: $FINAL_TOKEN${NC}"
    read -p "按回车返回..."
}

# --- 核心逻辑：被控安装 ---
install_agent() {
    clear
    echo -e "${G}--- 被控端引导安装 (V5.8) ---${NC}"
    read -p "主控端公网 IP: " M_IP
    read -p "通信 Token: " A_TOKEN
    read -p "被控面板端口 [2053]: " P_WEB
    P_WEB=${P_WEB:-2053}

    apt update && apt install -y sqlite3 docker.io psmisc lsof curl
    mkdir -p ${INSTALL_PATH}/agent/db_data
    docker rm -f 3x-ui multix-agent 2>/dev/null
    
    docker run -d --name 3x-ui --restart always --network host \
      -e XUI_PORT=${P_WEB} \
      -v ${INSTALL_PATH}/agent/db_data:/etc/x-ui ghcr.io/mhsanaei/3x-ui:latest

    cat > ${INSTALL_PATH}/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, docker, time
MASTER_WS = "ws://${M_IP}:8888"
TOKEN = "$A_TOKEN"
DB_PATH = "/app/db_share/x-ui.db"

async def handle_task(data):
    try:
        client = docker.from_env(); xui = client.containers.get("3x-ui")
        xui.stop(); time.sleep(2)
        conn = sqlite3.connect(DB_PATH); cursor = conn.cursor()
        cursor.execute("INSERT OR REPLACE INTO inbounds (remark, port, protocol, settings, stream_settings, sniffing, enable, tag, up, down, total, expiry_time) VALUES (?, ?, ?, ?, ?, ?, 1, ?, 0, 0, 0, 0)", 
                       (data['remark'], data['port'], data['protocol'], data['settings'], data['stream_settings'], data['sniffing'], f"inbound-{data['port']}"))
        conn.commit(); conn.close(); xui.start()
    except Exception as e: print(f"Error: {e}")

async def run_agent():
    while True:
        try:
            async with websockets.connect(MASTER_WS) as ws:
                await ws.send(json.dumps({"token": TOKEN}))
                while True:
                    stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent)}
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats}))
                    msg = await asyncio.wait_for(ws.recv(), timeout=25)
                    task = json.loads(msg)
                    if task.get('token') == TOKEN: await handle_task(task['data'])
        except: await asyncio.sleep(5)
if __name__ == '__main__': asyncio.run(run_agent())
EOF

    cd ${INSTALL_PATH}/agent
    cat > Dockerfile <<EOF
FROM python:3.11-slim
RUN pip install --no-cache-dir websockets psutil docker
WORKDIR /app
CMD ["python", "-u", "agent.py"]
EOF
    docker build -t multix-agent-image .
    docker run -d --name multix-agent --restart always --network host \
      -v /var/run/docker.sock:/var/run/docker.sock -v ${INSTALL_PATH}/agent:/app \
      -v ${INSTALL_PATH}/agent/db_data:/app/db_share multix-agent-image
    
    install_shortcut
    IS_AGENT=true
    echo -e "${G}✅ 被控端已完成凭据设置并上线！${NC}"
    read -p "回车返回..."
}

# --- 菜单循环 ---
show_menu() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 管理系统 V5.8        "
    echo -e "   [ 主控角色: $IS_MASTER | 被控角色: $IS_AGENT ] "
    echo -e "${G}==================================${NC}"
    echo "1. 🚀 安装/重装 主控端 (Master)"
    echo "2. 📡 安装/重装 被控端 (Agent)"
    echo "----------------------------------"
    echo "3. 🔍 档案查询 (查看 Token/地址)"
    echo "4. 📊 智能拨测 (链路/凭据自检)"
    echo "5. ⚙️  凭据修改 (修改 Token/IP)"
    echo "----------------------------------"
    echo "7. 🔧 智能修复 (清理端口/进程)"
    echo "9. 🗑️  完全卸载"
    echo "0. 🚪 退出"
    echo -e "${G}==================================${NC}"
}

mkdir -p $INSTALL_PATH
cp "$0" "$INSTALL_PATH/multix.sh" 2>/dev/null
install_shortcut

while true; do
    show_menu
    read -p "选择操作: " choice
    case $choice in
        1) install_master ;;
        2) install_agent ;;
        3) clear; echo -e "${Y}=== 配置档案 ===${NC}"
           [ "$IS_MASTER" = true ] && echo -e "主控 Token: ${G}$(grep "AUTH_TOKEN =" "$INSTALL_PATH/master/app.py" | cut -d'"' -f2)${NC}"
           [ "$IS_AGENT" = true ] && echo -e "Agent 指向: ${G}$(grep "MASTER_WS =" "$INSTALL_PATH/agent/agent.py" | cut -d'"' -f2)${NC}"
           read -p "返回..." ;;
        4) smart_test ;;
        5) read -p "新IP: " nip; read -p "新Token: " ntk; [ ! -z "$nip" ] && sed -i "s/MASTER_WS = .*/MASTER_WS = \"ws:\/\/$nip:8888\"/" $INSTALL_PATH/agent/agent.py; [ ! -z "$ntk" ] && sed -i "s/TOKEN = .*/TOKEN = \"$ntk\"/" $INSTALL_PATH/agent/agent.py; docker restart multix-agent; echo "已同步"; sleep 1 ;;
        7) pkill -9 -f app.py; [ "$IS_MASTER" = true ] && nohup python3 $INSTALL_PATH/master/app.py > /dev/null 2>&1 &; docker restart multix-agent multix-engine 2>/dev/null; echo "修复完成"; sleep 1 ;;
        9) docker rm -f 3x-ui multix-agent multix-engine 2>/dev/null; rm -rf $INSTALL_PATH; exit 0 ;;
        0) exit 0 ;;
    esac
done
