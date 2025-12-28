#!/bin/bash
# MultiX V5.2 - 修正版 (修复重启语法错误 + 优化 Agent 引导安装)

INSTALL_PATH="/opt/multix_mvp"
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

# --- 快捷命令安装 ---
install_shortcut() {
    cat > /usr/local/bin/multix <<EOF
#!/bin/bash
if [ -f "$INSTALL_PATH/multix.sh" ]; then
    bash $INSTALL_PATH/multix.sh
else
    echo -e "${R}[!] 找不到主脚本 $INSTALL_PATH/multix.sh${NC}"
fi
EOF
    chmod +x /usr/local/bin/multix
}

# --- 菜单界面 ---
show_menu() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 管理系统 V5.2        "
    echo -e "   Docker引擎 | 引导安装 | 凭据管理 "
    echo -e "${G}==================================${NC}"
    echo "1. 🚀 安装/重装 主控端 (Master)"
    echo "2. 📡 安装/重装 被控端 (Agent)"
    echo "----------------------------------"
    echo "3. 🔍 查看配置档案 (Token/地址)"
    echo "4. 📊 连通性自检 (诊断握手状态)"
    echo "5. ⚙️  修改配置/凭据 (不重装直接修改)"
    echo "----------------------------------"
    echo "7. ⚡ 重启所有服务"
    echo "9. 🗑️  完全卸载"
    echo "0. 🚪 退出"
    echo -e "${G}==================================${NC}"
    read -p "选择操作 [0-9]: " choice
}

# --- 主控端安装 (集成 Docker 引擎) ---
install_master() {
    echo -e "${Y}[*] 启动主控安装，配置加密引擎...${NC}"
    docker pull ghcr.io/mhsanaei/3x-ui:latest &>/dev/null
    docker rm -f multix-engine 2>/dev/null
    docker run -d --name multix-engine -p 2053:2053 --restart always ghcr.io/mhsanaei/3x-ui:latest &>/dev/null

    read -p "设置 Web 端口 [默认 7575]: " M_PORT
    M_PORT=${M_PORT:-7575}
    DEF_TOKEN=$(openssl rand -hex 8)
    read -p "设置通信 Token [默认 $DEF_TOKEN]: " M_TOKEN
    M_TOKEN=${M_TOKEN:-$DEF_TOKEN}

    mkdir -p ${INSTALL_PATH}/master
    cat > ${INSTALL_PATH}/master/app.py <<EOF
import json, asyncio, time, psutil, os, base64, subprocess
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread

app = Flask(__name__)
app.secret_key = "$M_TOKEN"
AGENTS = {} 
LOOP = None
AUTH_TOKEN = "$M_TOKEN"

def get_keys():
    try:
        out = subprocess.check_output("docker exec multix-engine xray x25519", shell=True).decode()
        lines = [l for l in out.split('\n') if l.strip()]
        return lines[0].split(': ')[1].strip(), lines[1].split(': ')[1].strip()
    except: return "Error", "Error"

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8"><title>MultiX Center</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-black text-gray-300 font-sans">
    <div class="flex h-screen">
        <div class="w-64 bg-zinc-950 border-r border-white/10 p-6 flex flex-col">
            <h1 class="text-xl font-bold text-white italic">🛰️ MultiX V5.2</h1>
            <button onclick="location.reload()" class="w-full mt-10 p-3 bg-blue-600 rounded-xl text-white font-bold">刷新集群</button>
            <div class="mt-auto"><a href="/logout" class="text-zinc-500 text-sm">退出登录</a></div>
        </div>
        <div class="flex-1 p-10">
            <h2 class="text-2xl font-bold mb-8 text-white text-3xl font-bold">在线节点 ({{ agents_count }})</h2>
            <div class="grid grid-cols-3 gap-6">
                {% for ip, info in agents.items() %}
                <div class="bg-zinc-900 border border-white/5 p-6 rounded-2xl">
                    <div class="flex justify-between mb-4"><b>{{ ip }}</b><span class="w-2 h-2 bg-green-500 rounded-full animate-pulse"></span></div>
                    <button onclick="openEdit('{{ ip }}')" class="w-full py-2 bg-zinc-800 hover:bg-blue-600 rounded-lg transition text-sm">配置管理</button>
                </div>
                {% endfor %}
            </div>
        </div>
    </div>
    <div id="modal" class="fixed inset-0 bg-black/90 hidden items-center justify-center z-50">
        <div class="bg-zinc-900 w-[480px] p-8 rounded-3xl border border-white/10">
            <h3 class="text-white mb-6 font-bold text-lg italic">节点配置: <span id="tip" class="text-blue-500"></span></h3>
            <div class="space-y-4">
                <input id="uuid" placeholder="节点 UUID" class="w-full bg-black border border-white/5 p-3 rounded-xl text-sm">
                <div class="flex gap-2"><input id="priv" placeholder="Reality 私钥" class="flex-1 bg-black border border-white/5 p-3 rounded-xl text-sm"><button onclick="gk()" class="bg-green-600/20 text-green-500 px-4 rounded-xl text-xs font-bold border border-green-500/20">生成密钥对</button></div>
                <input id="pub" readonly placeholder="公钥 (随私钥同步生成)" class="w-full bg-zinc-800/50 p-3 rounded-xl text-xs text-zinc-500 border-dashed border border-zinc-700">
                <div class="flex gap-4 pt-4"><button onclick="closeM()" class="flex-1 py-3 bg-zinc-800 rounded-xl">取消</button><button onclick="ss()" class="flex-1 py-3 bg-blue-600 text-white font-bold rounded-xl shadow-lg shadow-blue-500/20">下发配置</button></div>
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
    return '<h3>Login</h3><form method="post"><input name="u" placeholder="User"><input name="p" type="password" placeholder="Pass"><button>Go</button></form>'

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(HTML_TEMPLATE, agents_count=len(AGENTS), agents=AGENTS, auth_token=AUTH_TOKEN)

@app.route('/send', methods=['POST'])
def send():
    req = request.json
    node_data = {"remark": "V52_Reality", "port": 443, "protocol": "vless", "settings": json.dumps({"clients": [{"id": req['uuid'], "flow": "xtls-rprx-vision"}]}), "stream_settings": json.dumps({"network": "tcp", "security": "reality", "realitySettings": {"privateKey": req['priv'], "dest": "www.microsoft.com:443", "serverNames": ["www.microsoft.com"]}}), "sniffing": json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic"]})}
    payload = json.dumps({"action": "sync_node", "data": node_data, "token": AUTH_TOKEN})
    if req['ip'] in AGENTS:
        asyncio.run_coroutine_threadsafe(AGENTS[req['ip']]['ws'].send(payload), LOOP)
        return jsonify({"msg": "✅ 指令已送达队列"})
    return jsonify({"msg": "❌ 离线"})

async def ws_server(websocket):
    ip = websocket.remote_address[0]
    try:
        auth = await asyncio.wait_for(websocket.recv(), timeout=10)
        if json.loads(auth).get('token') != AUTH_TOKEN: return
        AGENTS[ip] = {"ws": websocket, "stats": {"cpu":0, "mem":0}}
        async for msg in websocket:
            data = json.loads(msg)
            if data.get('type') == 'heartbeat': AGENTS[ip]['stats'] = data['data']
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
    echo -e "${G}✅ 主控端部署成功！面板端口: $M_PORT${NC}"
    read -p "按回车继续..."
}

# --- 被控端引导安装 (凭据设置先行) ---
install_agent() {
    clear
    echo -e "${G}--- 启动被控端引导安装 ---${NC}"
    echo -e "${Y}[步骤 1/3] 设置通信凭据${NC}"
    read -p "请输入主控端 IP 地址: " M_IP
    read -p "请输入通信 Token (须与主控一致): " A_TOKEN
    echo -e "${Y}[步骤 2/3] 设置本地面板端口${NC}"
    read -p "自定义被控面板端口 [默认 2053]: " P_WEB
    P_WEB=${P_WEB:-2053}
    echo -e "${Y}[步骤 3/3] 环境部署中...${NC}"

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
    echo -e "${G}✅ 被控端安装完成并已上线！${NC}"
    read -p "按回车返回菜单..."
}

# --- 修改被控凭据 (不重装直接更新) ---
modify_config() {
    clear
    echo -e "${Y}--- 快速修改配置 (无需重装) ---${NC}"
    read -p "新主控 IP (回车跳过): " nip
    read -p "新 Token (回车跳过): " ntk
    [ ! -z "$nip" ] && sed -i "s/MASTER_WS = .*/MASTER_WS = \"ws:\/\/$nip:8888\"/" $INSTALL_PATH/agent/agent.py
    [ ! -z "$ntk" ] && sed -i "s/TOKEN = .*/TOKEN = \"$ntk\"/" $INSTALL_PATH/agent/agent.py
    docker restart multix-agent
    echo -e "${G}✅ 凭据更新成功，Agent 已重启。${NC}"
    sleep 1
}

# --- 执行主流程 ---
mkdir -p $INSTALL_PATH
cp "$0" "$INSTALL_PATH/multix.sh" 2>/dev/null
install_shortcut
while true; do
    show_menu
    case $choice in
        1) install_master ;;
        2) install_agent ;;
        3) 
            clear
            echo -e "${G}==================================${NC}"
            echo -e "      🛰️ MultiX V5.2 档案库        "
            echo -e "${G}==================================${NC}"
            [ -f "$INSTALL_PATH/master/app.py" ] && echo -e "主控 Token: ${Y}$(grep "AUTH_TOKEN =" "$INSTALL_PATH/master/app.py" | cut -d'"' -f2)${NC}"
            [ -f "$INSTALL_PATH/agent/agent.py" ] && echo -e "被控连接: ${G}$(grep "MASTER_WS =" "$INSTALL_PATH/agent/agent.py" | cut -d'"' -f2)${NC}"
            echo -e "${G}==================================${NC}"
            read -p "按回车返回..." ;;
        4) 
            echo -e "${Y}[*] 正在执行日志诊断...${NC}"
            docker restart multix-agent >/dev/null
            sleep 3
            docker logs --tail 20 multix-agent
            read -p "诊断完成，按任意键返回..." -n 1 -r ;;
        5) modify_config ;;
        7) 
            pkill -9 -f app.py
            [ -f "$INSTALL_PATH/master/app.py" ] && nohup python3 $INSTALL_PATH/master/app.py > /dev/null 2>&1 &
            docker restart multix-agent 3x-ui
            echo -e "${G}✅ 服务已完成重启流程。${NC}"
            sleep 1 ;;
        9) 
            read -p "确认卸载？(y/n): " confirm
            if [ "$confirm" == "y" ]; then
                docker rm -f 3x-ui multix-agent multix-engine 2>/dev/null
                rm -rf $INSTALL_PATH /usr/local/bin/multix
                echo "已彻底清除系统。"
                exit 0
            fi ;;
        0) exit 0 ;;
        *) echo "无效选项" ; sleep 1 ;;
    esac
done
