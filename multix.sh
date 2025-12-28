#!/bin/bash
# MultiX V5.1 - 旗舰最终版 (Docker引擎 + 拨测自检 + 凭据修改)

INSTALL_PATH="/opt/multix_mvp"
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

# --- 快捷命令修复逻辑 ---
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
    echo -e "      MultiX 管理系统 V5.1        "
    echo -e "   Docker引擎 | 拨测自检 | 凭据修改 "
    echo -e "${G}==================================${NC}"
    echo "1. 🚀 安装/重装 主控端 (Master)"
    echo "2. 📡 安装/重装 被控端 (Agent)"
    echo "----------------------------------"
    echo "3. 🔍 查看配置档案 (Token/地址)"
    echo "4. 📊 连通性自检 (被控端专用)"
    echo "5. ⚙️  修改配置/凭据 (无需重装)"
    echo "----------------------------------"
    echo "7. ⚡ 重启所有服务"
    echo "9. 🗑️  完全卸载"
    echo "0. 🚪 退出"
    echo -e "${G}==================================${NC}"
    read -p "选择操作 [0-9]: " choice
}

# --- 主控端安装 (集成 Docker 3x-ui 引擎) ---
install_master() {
    echo -e "${Y}[*] 正在拉取 Docker 3x-ui 加密引擎...${NC}"
    docker pull ghcr.io/mhsanaei/3x-ui:latest &>/dev/null
    docker run -d --name multix-engine -p 2053:2053 ghcr.io/mhsanaei/3x-ui:latest &>/dev/null

    read -p "设置 Web 端口 [默认 7575]: " M_PORT
    M_PORT=${M_PORT:-7575}
    M_TOKEN=$(openssl rand -hex 8)
    read -p "设置通信 Token [默认 $M_TOKEN]: " M_TOKEN
    M_TOKEN=${M_TOKEN:-$M_TOKEN}

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
        # 核心修复：通过 Docker 引擎生成标准密钥
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
        <div class="w-64 bg-zinc-950 border-r border-white/10 p-6">
            <h1 class="text-xl font-bold text-white italic">🛰️ MultiX V5.1</h1>
            <p class="text-[10px] text-zinc-500 mt-2">Engine: Docker 3x-ui</p>
            <button onclick="location.reload()" class="w-full mt-10 p-3 bg-blue-600 rounded-xl text-white font-bold">刷新集群</button>
        </div>
        <div class="flex-1 p-10">
            <h2 class="text-2xl font-bold mb-8 text-white">在线小鸡 ({{ agents_count }})</h2>
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
        <div class="bg-zinc-900 w-[450px] p-8 rounded-3xl border border-white/10">
            <h3 class="text-white mb-6 font-bold text-lg">节点配置: <span id="tip" class="text-blue-500"></span></h3>
            <div class="space-y-4">
                <input id="uuid" placeholder="UUID" class="w-full bg-black border border-white/5 p-3 rounded-xl text-sm">
                <div class="flex gap-2"><input id="priv" placeholder="私钥" class="flex-1 bg-black border border-white/5 p-3 rounded-xl text-sm"><button onclick="gk()" class="bg-green-600/20 text-green-500 px-4 rounded-xl text-xs">生成密钥对</button></div>
                <input id="pub" readonly placeholder="公钥" class="w-full bg-zinc-800/50 p-3 rounded-xl text-xs text-zinc-500 border-dashed border border-zinc-700">
                <div class="flex gap-4 pt-4"><button onclick="closeM()" class="flex-1 py-3 bg-zinc-800 rounded-xl">取消</button><button onclick="ss()" class="flex-1 py-3 bg-blue-600 text-white font-bold rounded-xl">同步到小鸡</button></div>
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
    return '<h3>Auth</h3><form method="post"><input name="u"><input name="p" type="password"><button>Go</button></form>'

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(HTML_TEMPLATE, agents_count=len(AGENTS), agents=AGENTS, auth_token=AUTH_TOKEN)

@app.route('/send', methods=['POST'])
def send():
    req = request.json
    node_data = {"remark": "V51_Reality", "port": 443, "protocol": "vless", "settings": json.dumps({"clients": [{"id": req['uuid'], "flow": "xtls-rprx-vision"}]}), "stream_settings": json.dumps({"network": "tcp", "security": "reality", "realitySettings": {"privateKey": req['priv'], "dest": "www.microsoft.com:443", "serverNames": ["www.microsoft.com"]}}), "sniffing": json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic"]})}
    payload = json.dumps({"action": "sync_node", "data": node_data, "token": AUTH_TOKEN})
    if req['ip'] in AGENTS:
        asyncio.run_coroutine_threadsafe(AGENTS[req['ip']]['ws'].send(payload), LOOP)
        return jsonify({"msg": "✅ 已下发"})
    return jsonify({"msg": "❌ 小鸡离线"})

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
    echo -e "${G}✅ 主控已就绪！面板端口: $M_PORT, Token: $M_TOKEN${NC}"
}

# --- 连通性自检 (拨测) ---
diagnose_agent() {
    clear
    echo -e "${Y}[*] 正在启动 Agent 连通性自检...${NC}"
    if [ ! -f "$INSTALL_PATH/agent/agent.py" ]; then echo "未安装 Agent"; return; fi
    A_WS=$(grep "MASTER_WS =" "$INSTALL_PATH/agent/agent.py" | cut -d'"' -f2)
    A_TOKEN=$(grep "TOKEN =" "$INSTALL_PATH/agent/agent.py" | cut -d'"' -f2)
    A_IP=$(echo $A_WS | cut -d'/' -f3 | cut -d':' -f1)
    
    echo -n "[1/2] 网络链路检测 ($A_IP): "
    if nc -ztw 3 $A_IP 8888 &>/dev/null; then echo -e "${G}通畅${NC}"; else echo -e "${R}阻塞 (请检查主控防火墙)${NC}"; fi
    
    echo -n "[2/2] 凭据握手检测: "
    docker restart multix-agent >/dev/null && sleep 3
    if docker logs --tail 20 multix-agent 2>&1 | grep -q "Authentication Successful" || docker logs --tail 20 multix-agent 2>&1 | grep -q "heartbeat"; then
        echo -e "${G}✅ 凭据匹配，握手成功！${NC}"
    else
        echo -e "${R}❌ 握手失败 (Token 可能不正确)${NC}"
    fi
    echo -e "\n${Y}----------------------------------${NC}"
    read -p "诊断完成。按任意键返回..." -n 1 -r
}

# --- 修改配置/凭据 ---
modify_agent_config() {
    echo -e "${G}--- 修改被控配置 ---${NC}"
    read -p "新主控 IP [当前: $A_IP]: " nip
    read -p "新通信 Token [当前: $A_TOKEN]: " ntk
    [ ! -z "$nip" ] && sed -i "s/MASTER_WS = .*/MASTER_WS = \"ws:\/\/$nip:8888\"/" $INSTALL_PATH/agent/agent.py
    [ ! -z "$ntk" ] && sed -i "s/TOKEN = .*/TOKEN = \"$ntk\"/" $INSTALL_PATH/agent/agent.py
    docker restart multix-agent
    echo "✅ 配置已重载。"; sleep 1
}

# --- 主流程 ---
cp "$0" "$INSTALL_PATH/multix.sh" 2>/dev/null
install_shortcut
while true; do
    show_menu
    case $choice in
        1) install_master ;;
        2) install_agent ;; # 保持 V4.5 安装逻辑
        4) diagnose_agent ;;
        5) modify_agent_config ;;
        7) pkill -9 -f app.py; [ -f "$INSTALL_PATH/master/app.py" ] && nohup python3 $INSTALL_PATH/master/app.py > /dev/null 2>&1 &; docker restart multix-agent; echo "服务已重启"; sleep 1 ;;
        9) docker rm -f 3x-ui multix-agent multix-engine; rm -rf $INSTALL_PATH; exit 0 ;;
        0) exit 0 ;;
    esac
done
