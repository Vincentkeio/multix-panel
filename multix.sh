#!/bin/bash

# ==============================================================================
# MultiX Pro V47.0 (3X-UI Exclusive Edition)
# 核心特性：3X-UI 深度适配 | 卡片别名系统 | 失败回滚/报警 | 双栈 NAT 穿透
# ==============================================================================

export M_ROOT="/opt/multix_mvp"
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 0. 快捷命令驻留 ] ---
if [[ "$(readlink -f /usr/bin/multix)" != "$(readlink -f $0)" ]]; then
    cp "$0" /usr/bin/multix && chmod +x /usr/bin/multix
    echo -e "${GREEN}✅ multix 快捷命令已就绪。${PLAIN}"
fi

# --- [ 基础函数 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须 Root 运行！${PLAIN}" && exit 1; }
pause_back() { echo -e "\n${YELLOW}按任意键返回主菜单...${PLAIN}"; read -n 1 -s -r; main_menu; }

get_public_ips() {
    IPV4=$(curl -s4m 2 api.ipify.org || echo "未检测到")
    IPV6=$(curl -s6m 2 api64.ipify.org || echo "未检测到")
}

resolve_ip() {
    local host=$1; local type=$2
    python3 -c "import socket; 
try: print(socket.getaddrinfo('$host', None, socket.$type)[0][4][0])
except: pass"
}

# --- [ 环境修复 ] ---
install_dependencies() {
    echo -e "${YELLOW}⚙️ 检查环境依赖...${PLAIN}"
    if [[ -f /etc/redhat-release ]]; then
        yum install -y epel-release && yum install -y python3 python3-devel python3-pip curl wget socat tar openssl
    else
        apt-get update && apt-get install -y python3 python3-pip curl wget socat tar openssl
    fi
    pip3 install flask websockets psutil --break-system-packages >/dev/null 2>&1 || pip3 install flask websockets psutil >/dev/null 2>&1
    
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker && systemctl start docker
    fi
    # 双栈修复
    if grep -q "net.ipv6.bindv6only" /etc/sysctl.conf; then
        sed -i 's/net.ipv6.bindv6only.*/net.ipv6.bindv6only = 0/' /etc/sysctl.conf
    else
        echo "net.ipv6.bindv6only = 0" >> /etc/sysctl.conf
    fi
    sysctl -p >/dev/null 2>&1
}

# --- [ 深度清理 ] ---
deep_cleanup() {
    echo -e "${RED}⚠️ 执行深度清理...${PLAIN}"
    systemctl stop multix-master 2>/dev/null
    rm -f /etc/systemd/system/multix-master.service
    systemctl daemon-reload
    docker stop multix-agent 2>/dev/null; docker rm -f multix-agent 2>/dev/null
    docker rmi $(docker images | grep "multix-agent" | awk '{print $3}') 2>/dev/null
    pkill -9 -f "master/app.py"; pkill -9 -f "agent/agent.py"
    echo -e "${GREEN}✅ 清理完成。${PLAIN}"
    pause_back
}

# --- [ 凭据中心 ] ---
credential_center() {
    clear
    echo -e "${SKYBLUE}🔐 MultiX 凭据中心${PLAIN}"
    if [ -f $M_ROOT/.env ]; then
        source $M_ROOT/.env
        get_public_ips
        echo -e "${YELLOW}[主控]${PLAIN} http://${IPV4}:${M_PORT}"
        echo -e "Token: ${SKYBLUE}$M_TOKEN${PLAIN}"
    fi
    AGENT_FILE="$M_ROOT/agent/agent.py"
    if [ -f "$AGENT_FILE" ]; then
        CUR_MASTER=$(grep 'MASTER =' $AGENT_FILE | cut -d'"' -f2)
        CUR_TOKEN=$(grep 'TOKEN =' $AGENT_FILE | cut -d'"' -f2)
        echo -e "${YELLOW}[被控]${PLAIN} 连接至: $CUR_MASTER"
    fi
    echo "--------------------------------"
    echo "1. 修改配置"
    echo "0. 返回"
    read -p "选择: " c_opt
    if [[ "$c_opt" == "1" ]]; then
        read -p "新端口: " np; M_PORT=${np:-$M_PORT}
        read -p "新Token: " nt; M_TOKEN=${nt:-$M_TOKEN}
        echo -e "M_TOKEN=$M_TOKEN\nM_PORT=$M_PORT\nM_USER=$M_USER\nM_PASS=$M_PASS" > $M_ROOT/.env
        systemctl restart multix-master
        echo "已重启生效"
    fi
    main_menu
}

# --- [ 主控端安装 ] ---
install_master() {
    install_dependencies
    mkdir -p $M_ROOT/master $M_ROOT/agent/db_data
    if [ -f $M_ROOT/.env ]; then source $M_ROOT/.env; fi
    
    read -p "端口 [${M_PORT:-7575}]: " IN_PORT; M_PORT=${IN_PORT:-${M_PORT:-7575}}
    RAND_TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    read -p "Token [默认随机]: " IN_TOKEN; M_TOKEN=${IN_TOKEN:-${M_TOKEN:-$RAND_TOKEN}}
    M_USER="admin"; M_PASS="admin"
    echo -e "M_TOKEN=$M_TOKEN\nM_PORT=$M_PORT\nM_USER=$M_USER\nM_PASS=$M_PASS" > $M_ROOT/.env
    
    echo -e "${YELLOW}🛰️ 部署主控端 (3X-UI 适配版)...${PLAIN}"
    cat > $M_ROOT/master/app.py <<EOF
import json, asyncio, time, psutil, os, socket, logging
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread

M_PORT, M_TOKEN = int("$M_PORT"), "$M_TOKEN"
app = Flask(__name__); app.secret_key = M_TOKEN
AGENTS = {}
LOOP_GLOBAL = None

def get_sys_info():
    try: return {"cpu": psutil.cpu_percent(), "mem": psutil.virtual_memory().percent, "ipv4": os.popen("curl -4s api.ipify.org").read().strip(), "ipv6": os.popen("curl -6s api64.ipify.org").read().strip()}
    except: return {"cpu":0,"mem":0}

HTML_T = """
{% raw %}
<!DOCTYPE html>
<html class="dark">
<head>
    <meta charset="UTF-8"><title>MultiX Pro V47</title>
    <script src="https://unpkg.com/vue@3/dist/vue.global.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { background: #050505; color: #cbd5e1; font-family: ui-sans-serif, system-ui; }
        .glass { background: rgba(20, 20, 20, 0.9); backdrop-filter: blur(20px); border: 1px solid rgba(255,255,255,0.08); }
        .modal-mask { background: rgba(0,0,0,0.95); position: fixed; inset: 0; z-index: 100; display: flex; align-items: center; justify-content: center; padding: 20px; }
        .sync-glow { animation: glow 1.5s infinite; }
        @keyframes glow { 0%, 100% { filter: drop-shadow(0 0 8px #eab308); opacity: 1; } 50% { opacity: 0.3; } }
        input { background: #111 !important; border: 1px solid rgba(255,255,255,0.1) !important; color: #fff !important; }
        .text-error { color: #ef4444; }
    </style>
</head>
<body class="p-8">
    <div id="app">
        <div class="flex flex-col md:flex-row justify-between items-center mb-10 gap-6">
            <div>
                <h1 class="text-4xl font-black text-blue-500 italic uppercase">🛰️ MultiX Pro <span class="text-xs text-zinc-600">for 3X-UI</span></h1>
                <p class="text-[10px] text-zinc-500 mt-2 font-bold uppercase tracking-widest">
                    TOKEN: <span class="text-yellow-500 font-mono select-all">""" + M_TOKEN + """</span> | 
                    <span class="text-blue-400">{{ sys.ipv4 }}</span>
                </p>
            </div>
            <div class="flex gap-4">
                <div v-for="(val, l) in masterStats" class="px-5 py-2 bg-zinc-900 border border-white/5 rounded-2xl text-center">
                    <div class="text-[8px] text-zinc-500 uppercase">{{ l }}</div><div class="text-xs font-bold text-white">{{ val }}%</div>
                </div>
            </div>
        </div>

        <div class="grid grid-cols-1 md:flex md:flex-wrap gap-8">
            <div v-for="agent in allAgents" :key="agent.ip" class="glass rounded-[3rem] p-8 relative w-full md:w-[380px] hover:border-blue-500/30 transition-all">
                <div class="flex justify-between items-center mb-6">
                    <div @click="editAlias(agent)" class="cursor-pointer group">
                        <div class="text-white text-xl font-black italic group-hover:text-blue-400">{{ agent.alias || 'Node-' + agent.idx }} ✎</div>
                        <div class="text-[9px] text-zinc-600 font-mono">{{ agent.ip }}</div>
                    </div>
                    <div :class="['h-3 w-3 rounded-full', agent.syncing ? 'bg-yellow-500 sync-glow' : (agent.lastSyncError ? 'bg-red-500' : 'bg-green-500')]"></div>
                </div>
                <div class="grid grid-cols-2 gap-4 mb-6 text-center">
                    <div class="bg-black/40 p-4 rounded-3xl border border-white/5"><div class="text-[8px] text-zinc-600">CPU</div><div class="text-xl font-black italic">{{agent.stats.cpu}}%</div></div>
                    <div class="bg-black/40 p-4 rounded-3xl border border-white/5"><div class="text-[8px] text-zinc-600">MEM</div><div class="text-xl font-black italic">{{agent.stats.mem}}%</div></div>
                </div>
                <div class="text-[9px] text-zinc-500 text-center mb-8 italic tracking-widest font-bold">
                    {{ agent.os || 'Linux' }} | 3X-UI: {{ agent.xui_ver || 'v2.x' }} | Nodes: {{ agent.nodes.length }}
                </div>
                <button @click="openManageModal(agent)" class="w-full py-5 bg-blue-600 text-white rounded-3xl font-black text-[10px] uppercase shadow-lg active:scale-95 transition-all">Manage Nodes</button>
            </div>
        </div>

        <div v-if="showListModal" class="modal-mask" @click.self="showListModal = false">
            <div class="bg-zinc-950 border border-white/10 rounded-[3rem] p-10 w-full max-w-4xl shadow-2xl max-h-[85vh] flex flex-col">
                <div class="flex justify-between items-center mb-8 border-b border-white/5 pb-4">
                    <h3 class="text-2xl font-black text-white italic uppercase">{{ activeAgent.alias }} Inbounds</h3>
                    <button @click="showListModal = false" class="text-zinc-500 text-3xl">✕</button>
                </div>
                <div class="flex-1 overflow-y-auto space-y-4 pr-2">
                    <div v-for="node in activeAgent.nodes" :key="node.id" class="bg-zinc-900/50 p-6 rounded-3xl border border-white/5 flex justify-between items-center">
                        <div>
                            <span class="text-blue-500 font-black text-[10px] italic">[{{node.protocol}}]</span>
                            <span class="text-white font-bold ml-4">{{node.remark}}</span>
                            <span v-if="node.isNew && node.syncError" class="text-red-500 text-[9px] ml-2 font-black">⚠️ UNSYNCED</span>
                            <div class="text-[10px] text-zinc-600 mt-1 font-mono">PORT: {{node.port}}</div>
                        </div>
                        <button @click="openEditModal(node)" class="px-6 py-2 bg-zinc-800 text-white rounded-xl text-[10px] font-black uppercase">Edit</button>
                    </div>
                </div>
                <button @click="openAddModal" class="mt-8 w-full py-5 bg-blue-600 text-white rounded-2xl font-black text-[10px] uppercase shadow-xl">+ New Inbound</button>
            </div>
        </div>

        <div v-if="showEditModal" class="modal-mask" @click.self="showEditModal = false">
            <div class="bg-zinc-950 border border-white/10 rounded-[4rem] p-12 w-full max-w-5xl shadow-2xl overflow-y-auto max-h-[95vh]">
                <div class="flex justify-between items-center mb-10 border-b border-white/5 pb-6">
                    <h3 class="text-2xl font-black text-white italic uppercase">Reality Config</h3>
                    <button @click="showEditModal = false" class="text-zinc-500 text-4xl">✕</button>
                </div>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-12 text-zinc-300">
                    <div class="space-y-6">
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">Remark</label><input v-model="conf.remark" class="w-full rounded-2xl p-4 mt-2 text-sm font-bold"></div>
                        <div><label class="text-[9px] text-blue-500 font-black uppercase">Email</label><div class="flex gap-2 mt-1"><input v-model="conf.email" class="flex-1 rounded-2xl p-4 text-sm font-mono"><button @click="genEmail" class="bg-zinc-800 px-5 rounded-2xl text-[10px] font-black">RAND</button></div></div>
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">Port</label><input v-model="conf.port" class="w-full rounded-2xl p-4 mt-2 text-sm font-mono"></div>
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">UUID</label><div class="flex gap-2 mt-1"><input v-model="conf.uuid" class="flex-1 rounded-2xl p-4 text-xs font-mono"><button @click="genUUID" class="bg-zinc-800 px-5 rounded-2xl text-[10px] font-black">GEN</button></div></div>
                    </div>
                    <div class="space-y-6">
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">Dest (SNI)</label><input v-model="conf.dest" class="w-full rounded-2xl p-4 mt-2 text-sm font-mono"></div>
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">Private Key</label><div class="flex gap-2 mt-1"><input v-model="conf.privKey" class="flex-1 rounded-2xl p-4 text-xs font-mono"><button @click="genKeys" class="bg-blue-600/20 text-blue-400 border border-blue-500/20 px-5 rounded-2xl text-[10px] font-black">NEW</button></div></div>
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">Short ID</label><div class="flex gap-2 mt-1"><input v-model="conf.shortId" class="flex-1 rounded-2xl p-4 text-sm font-mono"><button @click="genShortId" class="bg-zinc-800 px-5 rounded-2xl text-[10px] font-black">RAND</button></div></div>
                    </div>
                </div>
                <div class="mt-14 flex gap-6">
                    <button @click="showEditModal = false" class="flex-1 py-6 bg-zinc-900 text-zinc-500 rounded-3xl text-xs font-black uppercase">Discard</button>
                    <button @click="saveNode" class="flex-1 py-6 bg-blue-600 text-white rounded-3xl text-xs font-black uppercase shadow-2xl tracking-widest active:scale-95 transition-all">
                        <span v-if="activeAgent.syncing">Syncing...</span><span v-else>Save & Sync</span>
                    </button>
                </div>
            </div>
        </div>
    </div>
    <script>
        const { createApp, ref, computed, onMounted } = Vue;
        createApp({
            setup() {
                const agents = ref({}); const masterStats = ref({ CPU:0, MEM:0 }); const sys = ref({ ipv4:'...' });
                const showListModal = ref(false); const showEditModal = ref(false); const activeAgent = ref({});
                const conf = ref({}); 
                // Mock Data 模拟真实结构
                const mockAgent = ref({ ip: 'MOCK-SERVER', alias: 'Example Node', idx: 0, stats: {cpu: 25, mem: 40}, nodes: [{id: 99, remark: 'Demo Node', port: 443, protocol: 'vless'}], syncing: false });

                const allAgents = computed(() => {
                    const list = [mockAgent.value];
                    let i = 1;
                    for (let ip in agents.value) {
                        agents.value[ip].ip = ip;
                        agents.value[ip].idx = i++;
                        list.push(agents.value[ip]);
                    }
                    return list;
                });

                const update = async () => {
                    try {
                        const r = await fetch('/api/state'); const d = await r.json();
                        sys.value = d.master; masterStats.value = d.master.stats;
                        for (let ip in d.agents) {
                            if (!agents.value[ip]) agents.value[ip] = { ...d.agents[ip], syncing: false, alias: 'Node' };
                            else if (!agents.value[ip].syncing) {
                                agents.value[ip].stats = d.agents[ip].stats;
                                agents.value[ip].nodes = d.agents[ip].nodes; // 正常更新
                            }
                        }
                    } catch(e){}
                };

                const editAlias = (agent) => { const n = prompt("Enter Alias:", agent.alias); if(n) agent.alias = n; };
                const openManageModal = (agent) => { activeAgent.value = agent; showListModal.value = true; };
                
                const openEditModal = (node) => {
                    conf.value = { ...node, email: 'admin@mx.com', uuid: '', dest: 'www.microsoft.com:443', privKey: '', shortId: '' };
                    showListModal.value = false; showEditModal.value = true;
                };
                
                const openAddModal = () => {
                    // 新建节点：临时 ID
                    conf.value = { id: null, remark: 'New-Node', port: 443, protocol: 'vless', isNew: true };
                    genUUID(); genEmail(); genKeys(); genShortId();
                    showListModal.value = false; showEditModal.value = true;
                };

                const saveNode = async () => {
                    const agent = activeAgent.value;
                    if(agent.ip === 'MOCK-SERVER') {
                        mockAgent.value.syncing = true; showEditModal.value = false;
                        setTimeout(() => { mockAgent.value.syncing = false; }, 2000); return;
                    }
                    
                    const backupNodes = JSON.parse(JSON.stringify(agent.nodes)); // 备份用于回滚
                    agent.syncing = true; showEditModal.value = false;
                    
                    // 乐观更新：如果是新建，先推入列表
                    if (conf.value.isNew) agent.nodes.push(conf.value);

                    try {
                        await fetch('/api/sync', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({ ip: agent.ip, config: conf.value }) });
                        
                        // 10秒超时检查
                        setTimeout(() => {
                            if (agent.syncing) {
                                agent.syncing = false; 
                                agent.lastSyncError = true;
                                // 回滚逻辑
                                if (conf.value.isNew) {
                                    // 标记为未同步的新节点
                                    const n = agent.nodes.find(n => n.remark === conf.value.remark);
                                    if(n) n.syncError = true; 
                                } else {
                                    agent.nodes = backupNodes; // 还原旧配置
                                }
                            }
                        }, 10000);
                    } catch(e) { agent.syncing = false; agent.lastSyncError = true; agent.nodes = backupNodes; }
                };

                const genUUID = () => { conf.value.uuid = crypto.randomUUID(); };
                const genEmail = () => { conf.value.email = 'mx_'+Math.random().toString(36).substring(7)+'@mx.com'; };
                const genKeys = () => { conf.value.privKey = btoa(Math.random().toString()).substring(0,43)+'='; };
                const genShortId = () => { conf.value.shortId = Math.random().toString(16).substring(2,10); };

                onMounted(() => { update(); setInterval(update, 3000); });
                return { allAgents, masterStats, sys, showListModal, showEditModal, conf, activeAgent, editAlias, openManageModal, openEditModal, openAddModal, saveNode, genUUID, genEmail, genKeys, genShortId };
            }
        }).mount('#app');
    </script>
</body></html>
{% endraw %}
"""

@app.route('/api/state')
def get_state():
    s = get_sys_info()
    return jsonify({"agents": {ip: {"stats": info.get("stats", {"cpu":0,"mem":0}), "nodes": info.get("nodes", []), "os": info.get("os", "Linux"), "xui_ver": "3X-UI"} for ip, info in AGENTS.items()}, "master": {"stats": {"CPU": s["cpu"], "MEM": s["mem"], "DISK": s["disk"]}, "ipv4": s["ipv4"], "ipv6": s["ipv6"]}})

@app.route('/api/sync', methods=['POST'])
def do_sync():
    d = request.json; target = d.get('ip'); c = d.get('config', {})
    if target in AGENTS:
        payload = json.dumps({"action": "sync_node", "token": M_TOKEN, "data": {"id": c.get('id'), "remark": c.get('remark'), "port": int(c.get('port')), "protocol": "vless", "settings": json.dumps({"clients": [{"id": c.get('uuid'), "flow": "xtls-rprx-vision", "email": c.get('email')}]}), "stream_settings": json.dumps({"network": "tcp", "security": "reality", "realitySettings": {"dest": c.get('dest', 'www.microsoft.com:443'), "serverNames": [c.get('dest', '').split(':')[0]], "privateKey": c.get('privKey'), "shortIds": [c.get('shortId')]}}), "sniffing": json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic"]})}})
        asyncio.run_coroutine_threadsafe(AGENTS[target]['ws'].send(payload), LOOP_GLOBAL)
        return jsonify({"status": "sent"})
    return jsonify({"status": "offline"}), 404

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(HTML_T)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form['u'] == M_USER and request.form['p'] == M_PASS: session['logged'] = True; return redirect('/')
    return '<h3>Login</h3><form method="post">U: <input name="u"> P: <input name="p" type="password"><button>Login</button></form>'

async def ws_handler(ws):
    ip = ws.remote_address[0]
    try:
        auth = await asyncio.wait_for(ws.recv(), timeout=10)
        if json.loads(auth).get('token') == M_TOKEN:
            AGENTS[ip] = {"ws": ws, "stats": {"cpu":0,"mem":0}, "nodes": []}
            async for msg in ws:
                d = json.loads(msg)
                if d.get('type') == 'heartbeat':
                    AGENTS[ip]['stats'] = d.get('data', {"cpu":0,"mem":0})
                    AGENTS[ip]['nodes'] = d.get('nodes', [])
                    AGENTS[ip]['os'] = d.get('data', {}).get('os', 'Linux')
    except: pass
    finally:
        if ip in AGENTS: del AGENTS[ip]

def start_ws():
    global LOOP_GLOBAL; LOOP_GLOBAL = asyncio.new_event_loop(); asyncio.set_event_loop(LOOP_GLOBAL)
    async def m():
        async with websockets.serve(ws_handler, "0.0.0.0", 8888): await asyncio.Future()
    LOOP_GLOBAL.run_until_complete(m())

if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    app.run(host='0.0.0.0', port=M_PORT)
EOF

    cat > /etc/systemd/system/multix-master.service <<EOF
[Unit]
Description=MultiX Master
After=network.target
[Service]
ExecStart=/usr/bin/python3 $M_ROOT/master/app.py
Restart=always
User=root
WorkingDirectory=$M_ROOT/master
Environment=PYTHONUNBUFFERED=1
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable multix-master; systemctl restart multix-master
    get_public_ips
    echo -e "${GREEN}✅ 主控端部署成功！${PLAIN}"
    echo -e "   IPv4: http://${IPV4}:${M_PORT}"
    [[ "$IPV6" != "未检测到" ]] && echo -e "   IPv6: http://[${IPV6}]:${M_PORT}"
    echo -e "   Token: ${YELLOW}$M_TOKEN${PLAIN}"
    pause_back
}

# --- [ 被控安装 (3X-UI + 双栈) ] ---
install_agent() {
    install_dependencies
    mkdir -p $M_ROOT/agent
    echo -e "${SKYBLUE}>>> 配置被控端${PLAIN}"
    read -p "主控域名/IP: " IN_HOST
    read -p "Token: " IN_TOKEN
    
    echo -e "${YELLOW}连接协议选择 (NAT机建议强制IPv6):${PLAIN}"
    echo " 1. 自动 (默认)"
    echo " 2. 强制 IPv4"
    echo " 3. 强制 IPv6"
    read -p "选择: " NET_OPT
    
    TARGET_HOST="$IN_HOST"
    if [[ "$NET_OPT" == "3" ]]; then
        V6=$(resolve_ip "$IN_HOST" "AF_INET6")
        [[ -n "$V6" ]] && TARGET_HOST="[$V6]"
    elif [[ "$NET_OPT" == "2" ]]; then
        V4=$(resolve_ip "$IN_HOST" "AF_INET")
        [[ -n "$V4" ]] && TARGET_HOST="$V4"
    fi
    
    cat > $M_ROOT/agent/Dockerfile <<EOF
FROM python:3.11-slim
RUN pip install websockets psutil --break-system-packages
WORKDIR /app
CMD ["python", "agent.py"]
EOF
    cat > $M_ROOT/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, socket, platform
MASTER = "$TARGET_HOST"; TOKEN = "$IN_TOKEN"
DB_PATH = "/app/db_share/x-ui.db"
def sync_db(data):
    try:
        conn = sqlite3.connect(DB_PATH, timeout=10); cursor = conn.cursor(); nid = data.get('id')
        vals = (data['remark'], data['port'], data['settings'], data['stream_settings'], data['sniffing'])
        if nid: cursor.execute("UPDATE inbounds SET remark=?, port=?, settings=?, stream_settings=?, sniffing=?, enable=1 WHERE id=?", vals + (nid,))
        else: cursor.execute("INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing) VALUES (1, 0, 0, 0, ?, 1, 0, '', ?, 'vless', ?, ?, 'multix', ?)", vals)
        conn.commit(); conn.close(); return True
    except: return False
async def run():
    uri = f"ws://{MASTER}:8888"
    while True:
        try:
            async with websockets.connect(uri) as ws:
                await ws.send(json.dumps({"token": TOKEN}))
                while True:
                    conn = sqlite3.connect(DB_PATH); cur = conn.cursor()
                    cur.execute("SELECT id, remark, port, protocol FROM inbounds")
                    nodes = [{"id": r[0], "remark": r[1], "port": r[2], "protocol": r[3]} for r in cur.fetchall()]
                    conn.close()
                    stats = { "cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent), "os": platform.system()+" "+platform.release() }
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats, "nodes": nodes}))
                    try:
                        msg = await asyncio.wait_for(ws.recv(), timeout=5)
                        task = json.loads(msg)
                        if task.get('action') == 'sync_node': os.system("docker restart 3x-ui"); sync_db(task['data']); os.system("docker restart 3x-ui")
                    except: continue
        except: await asyncio.sleep(5)
asyncio.run(run())
EOF
    cd $M_ROOT/agent; docker build -t multix-agent-v47 .
    docker rm -f multix-agent 2>/dev/null
    docker run -d --name multix-agent --restart always --network host -v /var/run/docker.sock:/var/run/docker.sock -v $M_ROOT/agent/db_data:/app/db_share -v $M_ROOT/agent:/app multix-agent-v47
    echo -e "${GREEN}✅ 被控已启动 (连接: $TARGET_HOST)${PLAIN}"
    pause_back
}

# --- [ 运维菜单 (3X-UI) ] ---
sys_tools() {
    while true; do
        clear
        echo -e "${YELLOW}🧰 MultiX 运维工具箱 (3X-UI 专版)${PLAIN}"
        echo "1. 开启 BBR 加速"
        echo "2. 安装 3X-UI (MHSanaei)"
        echo "3. 申请 SSL 证书"
        echo "4. 重置 3X-UI 账号"
        echo "5. 清空流量统计"
        echo "0. 返回"
        read -p "选择: " t_opt
        case $t_opt in
            1) bash <(curl -L -s https://github.com/chiakge/Linux-NetSpeed/raw/master/tcp.sh) ;;
            2) bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) ;;
            3) curl https://get.acme.sh | sh ;;
            4) docker exec -it 3x-ui x-ui setting ;;
            5) sqlite3 $M_ROOT/agent/db_data/x-ui.db "UPDATE client_traffics SET up=0, down=0;" && echo "流量清零" ;;
            0) break ;;
        esac
        read -n 1 -s -r -p "按键继续..."
    done
    main_menu
}

main_menu() {
    clear
    echo -e "${SKYBLUE}🛰️ MultiX Pro (V47.0 3X-UI 终极版)${PLAIN}"
    echo "------------------------------------------------"
    echo " 1. 安装/更新 主控端 (Master)"
    echo " 2. 安装/更新 被控端 (Agent) [支持IPv6/NAT]"
    echo "------------------------------------------------"
    echo " 3. 连通性测试 (nc)"
    echo " 4. 被控离线修复 (重启)"
    echo " 5. 深度清理模式"
    echo " 6. 环境依赖修复"
    echo "------------------------------------------------"
    echo " 7. 凭据管理中心"
    echo " 8. 实时日志"
    echo " 9. 运维工具箱 (3X-UI/BBR/SSL)"
    echo "------------------------------------------------"
    echo " 0. 退出"
    read -p "选择: " choice
    case $choice in
        1) install_master ;;
        2) install_agent ;;
        3) read -p "IP: " tip; nc -zv -w 5 $tip 8888; pause_back ;;
        4) docker restart multix-agent; pause_back ;;
        5) deep_cleanup ;;
        6) install_dependencies; pause_back ;;
        7) credential_center ;;
        8) journalctl -u multix-master -f || docker logs -f multix-agent --tail 50; pause_back ;;
        9) sys_tools ;;
        0) exit 0 ;;
        *) main_menu ;;
    esac
}

main_menu
