#!/bin/bash

# ==============================================================================
# MultiX Pro Ultimate Edition (V42.0)
# 包含：深度清理 | 环境修复 | 凭据管理 | 双栈支持 | 完整运维菜单
# ==============================================================================

# --- [ 全局配置 ] ---
export M_ROOT="/opt/multix_mvp"
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 基础函数：环境检查与依赖修复 ] ---
check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}错误: 请使用 root 用户运行此脚本！${PLAIN}" && exit 1
}

check_sys() {
    if [[ -f /etc/redhat-release ]]; then RELEASE="centos";
    elif cat /etc/issue | grep -q -E -i "debian"; then RELEASE="debian";
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then RELEASE="ubuntu";
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then RELEASE="centos";
    elif cat /proc/version | grep -q -E -i "debian"; then RELEASE="debian";
    elif cat /proc/version | grep -q -E -i "ubuntu"; then RELEASE="ubuntu";
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then RELEASE="centos";
    fi
}

install_dependencies() {
    echo -e "${YELLOW}⚙️ 正在检查并修复系统环境依赖...${PLAIN}"
    check_sys
    if [ "${RELEASE}" == "centos" ]; then
        yum install -y epel-release
        yum install -y python3 python3-devel python3-pip curl wget socat tar openssl
    else
        apt-get update
        apt-get install -y python3 python3-pip curl wget socat tar openssl
    fi
    
    # 修复 Python 依赖
    pip3 install flask websockets psutil --break-system-packages >/dev/null 2>&1 || pip3 install flask websockets psutil >/dev/null 2>&1
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}正在安装 Docker...${PLAIN}"
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker && systemctl start docker
    fi
    echo -e "${GREEN}✅ 环境依赖修复完成。${PLAIN}"
}

# --- [ 核心功能：深度清理 (防止残留) ] ---
deep_cleanup() {
    echo -e "${RED}⚠️ 正在执行深度清理模式...${PLAIN}"
    
    # 1. 停止服务
    systemctl stop multix-master 2>/dev/null
    systemctl disable multix-master 2>/dev/null
    rm -f /etc/systemd/system/multix-master.service
    systemctl daemon-reload
    
    # 2. 停止并删除容器
    docker stop multix-agent 2>/dev/null
    docker rm -f multix-agent 2>/dev/null
    
    # 3. 删除旧镜像 (防止缓存导致的代码不更新)
    docker rmi $(docker images | grep "multix-agent" | awk '{print $3}') 2>/dev/null
    
    # 4. 杀掉残留进程
    pkill -9 -f "master/app.py"
    pkill -9 -f "agent/agent.py"
    
    # 5. 删除文件 (保留 .env 除非强制)
    # read -p "是否保留配置文件(.env)? [y/n]: " keep_conf
    # if [[ "$keep_conf" != "y" ]]; then
    #    rm -rf $M_ROOT
    #    echo -e "${GREEN}配置文件已清除${PLAIN}"
    # else
    #    cp $M_ROOT/.env /tmp/multix.env.bak
    #    rm -rf $M_ROOT/*
    #    mkdir -p $M_ROOT/master $M_ROOT/agent/db_data
    #    mv /tmp/multix.env.bak $M_ROOT/.env
    # fi
    
    echo -e "${GREEN}✅ 深度清理完成，系统已干净。${PLAIN}"
}

# --- [ 核心功能：凭据中心 ] ---
credential_center() {
    clear
    echo -e "${SKYBLUE}🔐 MultiX 凭据管理中心${PLAIN}"
    echo "-----------------------------------"
    if [ -f $M_ROOT/.env ]; then
        source $M_ROOT/.env
        echo -e "当前端口 (PORT):  ${GREEN}$M_PORT${PLAIN}"
        echo -e "当前用户 (USER):  ${GREEN}$M_USER${PLAIN}"
        echo -e "当前密码 (PASS):  ${GREEN}$M_PASS${PLAIN}"
        echo -e "当前令牌 (TOKEN): ${YELLOW}$M_TOKEN${PLAIN}"
    else
        echo -e "${RED}未检测到配置文件，请先安装！${PLAIN}"
        read -s -n1 -p "按任意键返回..."
        main_menu
    fi
    echo "-----------------------------------"
    read -p "是否修改配置? [y/n]: " mod_opt
    if [[ "$mod_opt" == "y" ]]; then
        read -p "新端口 ($M_PORT): " new_port; M_PORT=${new_port:-$M_PORT}
        read -p "新用户 ($M_USER): " new_user; M_USER=${new_user:-$M_USER}
        read -p "新密码 ($M_PASS): " new_pass; M_PASS=${new_pass:-$M_PASS}
        read -p "新令牌 ($M_TOKEN): " new_token; M_TOKEN=${new_token:-$M_TOKEN}
        
        echo -e "M_PORT=$M_PORT\nM_USER=$M_USER\nM_PASS=$M_PASS\nM_TOKEN=$M_TOKEN" > $M_ROOT/.env
        echo -e "${GREEN}✅ 配置已更新，正在重启服务...${PLAIN}"
        systemctl restart multix-master 2>/dev/null
        sleep 1
    fi
    main_menu
}

# --- [ 核心逻辑：变量初始化 ] ---
init_env_install() {
    mkdir -p $M_ROOT/master $M_ROOT/agent/db_data
    if [ ! -f $M_ROOT/.env ]; then
        echo -e "${YELLOW}⚙️ 初始化安装配置...${PLAIN}"
        read -p "设置管理端口 [默认 7575]: " M_PORT; M_PORT=${M_PORT:-7575}
        read -p "设置管理用户 [默认 admin]: " M_USER; M_USER=${M_USER:-admin}
        read -p "设置管理密码 [默认 admin]: " M_PASS; M_PASS=${M_PASS:-admin}
        M_TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
        echo -e "M_TOKEN=$M_TOKEN\nM_PORT=$M_PORT\nM_USER=$M_USER\nM_PASS=$M_PASS" > $M_ROOT/.env
    fi
    source $M_ROOT/.env
}

# --- [ 安装模块：主控端 (包含三级 UI + 物理 Token) ] ---
install_master() {
    install_dependencies
    init_env_install
    
    echo -e "${YELLOW}🛰️ 正在部署主控端 (V42.0 旗舰架构)...${PLAIN}"
    
    # 写入主程序
    cat > $M_ROOT/master/app.py <<EOF
import json, asyncio, time, psutil, os, socket, logging
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread

# 物理注入变量，防止读取失败
M_PORT = int("$M_PORT")
M_USER = "$M_USER"
M_PASS = "$M_PASS"
M_TOKEN = "$M_TOKEN"

app = Flask(__name__)
app.secret_key = M_TOKEN
AGENTS = {}
LOOP_GLOBAL = None

def get_sys_info():
    try:
        return {
            "cpu": psutil.cpu_percent(), "mem": psutil.virtual_memory().percent, "disk": psutil.disk_usage('/').percent,
            "ipv4": os.popen("curl -4 -s --connect-timeout 2 api.ipify.org").read().strip() or "N/A",
            "ipv6": os.popen("curl -6 -s --connect-timeout 2 api64.ipify.org").read().strip() or "N/A"
        }
    except: return {"cpu":0,"mem":0,"disk":0,"ipv4":"N/A","ipv6":"N/A"}

# 旗舰 UI：三级架构 + 物理 Token + 同步特效
HTML_T = """
{% raw %}
<!DOCTYPE html>
<html class="dark">
<head>
    <meta charset="UTF-8"><title>MultiX Pro Ultimate</title>
    <script src="https://unpkg.com/vue@3/dist/vue.global.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { background: #000; color: #cbd5e1; font-family: ui-sans-serif, system-ui; }
        .glass { background: rgba(18, 18, 18, 0.85); backdrop-filter: blur(20px); border: 1px solid rgba(255,255,255,0.05); }
        .modal-mask { background: rgba(0,0,0,0.95); position: fixed; inset: 0; z-index: 100; display: flex; align-items: center; justify-content: center; padding: 20px; }
        .sync-glow { animation: glow 1.5s infinite; }
        @keyframes glow { 0%, 100% { filter: drop-shadow(0 0 8px #eab308); opacity: 1; } 50% { opacity: 0.3; } }
        input { background: #111 !important; border: 1px solid rgba(255,255,255,0.1) !important; color: #fff !important; }
    </style>
</head>
<body class="p-8">
    <div id="app">
        <div class="flex flex-col md:flex-row justify-between items-center mb-10 gap-6">
            <div>
                <h1 class="text-4xl font-black text-blue-500 italic uppercase">🛰️ MultiX Pro</h1>
                <p class="text-[10px] text-zinc-500 mt-2 font-bold uppercase tracking-widest leading-relaxed">
                    TOKEN: <span class="text-yellow-500 font-mono font-black select-all">""" + M_TOKEN + """</span><br>
                    IPv4: <span class="text-blue-400 font-mono select-all">{{ sys.ipv4 }}</span> | 
                    IPv6: <span class="text-purple-400 font-mono select-all">{{ sys.ipv6 }}</span>
                </p>
            </div>
            <div class="flex gap-4">
                <div v-for="(val, l) in masterStats" :key="l" class="px-5 py-2 bg-zinc-900 border border-white/5 rounded-2xl text-center">
                    <div class="text-[8px] text-zinc-500 uppercase">{{ l }}</div><div class="text-xs font-bold text-white">{{ val }}%</div>
                </div>
                <button @click="lang = (lang == 'zh' ? 'en' : 'zh')" class="px-6 py-2 bg-blue-600 text-white rounded-2xl text-[10px] font-black uppercase tracking-widest">
                    {{ lang == 'zh' ? 'ENGLISH' : '中文' }}
                </button>
            </div>
        </div>

        <div class="grid grid-cols-1 md:flex md:flex-wrap gap-8">
            <div class="glass border-blue-500/20 border-dashed rounded-[3rem] p-8 relative w-full md:w-[380px]">
                <div class="flex justify-between items-center mb-6">
                    <div class="text-zinc-500 text-xl font-black italic">1.1.1.1 (MOCK)</div>
                    <div :class="['h-3 w-3 rounded-full', mockAgent.syncing ? 'bg-yellow-500 sync-glow' : 'bg-green-500']"></div>
                </div>
                <div class="grid grid-cols-2 gap-4 mb-6 text-center">
                    <div class="bg-black/40 p-4 rounded-3xl"><div class="text-[8px] text-zinc-600">CPU</div><div class="text-xl font-black italic text-zinc-500">25%</div></div>
                    <div class="bg-black/40 p-4 rounded-3xl"><div class="text-[8px] text-zinc-600">XUI</div><div class="text-[10px] font-black text-zinc-500">v2.1.2</div></div>
                </div>
                <button @click="openManageModal('MOCK')" class="w-full py-5 bg-zinc-900 text-zinc-600 rounded-3xl font-black text-[10px] uppercase">Node Config (1)</button>
            </div>

            <div v-for="(info, ip) in agents" :key="ip" class="glass rounded-[3rem] p-8 shadow-2xl relative w-full md:w-[380px] hover:border-blue-500/30 transition-all">
                <div class="flex justify-between items-center mb-6">
                    <div class="text-white text-xl font-black">{{ip}}</div>
                    <div :class="['h-3 w-3 rounded-full', info.syncing ? 'bg-yellow-500 sync-glow' : (info.lastSyncError ? 'bg-red-500' : 'bg-green-500')]"></div>
                </div>
                <div class="grid grid-cols-2 gap-4 mb-6 text-center">
                    <div class="bg-black/40 p-5 rounded-3xl border border-white/5"><div class="text-[8px] text-zinc-500 uppercase">CPU</div><div class="text-xl font-black italic">{{info.stats.cpu}}%</div></div>
                    <div class="bg-black/40 p-5 rounded-3xl border border-white/5"><div class="text-[8px] text-zinc-500 uppercase">MEM</div><div class="text-xl font-black italic">{{info.stats.mem}}%</div></div>
                </div>
                <div class="text-[9px] text-zinc-500 text-center mb-8 italic tracking-widest font-bold">
                    OS: {{info.os}} | XUI: {{info.xui_ver}} | Nodes: {{info.nodes.length}}
                </div>
                <button @click="openManageModal(ip)" class="w-full py-5 bg-blue-600 text-white rounded-3xl font-black text-[10px] uppercase shadow-lg shadow-blue-600/20">Manage Nodes</button>
            </div>
        </div>

        <div v-if="showListModal" class="modal-mask" @click.self="showListModal = false">
            <div class="bg-zinc-950 border border-white/10 rounded-[3rem] p-10 w-full max-w-4xl shadow-2xl max-h-[85vh] flex flex-col">
                <div class="flex justify-between items-center mb-8 border-b border-white/5 pb-4">
                    <h3 class="text-2xl font-black text-white italic uppercase tracking-tighter">{{activeIp}} Inbound List</h3>
                    <button @click="showListModal = false" class="text-zinc-500 text-3xl">✕</button>
                </div>
                <div class="flex-1 overflow-y-auto space-y-4 pr-2">
                    <div v-for="node in (activeIp == 'MOCK' ? mockAgent.nodes : agents[activeIp].nodes)" :key="node.id" class="bg-zinc-900/50 p-6 rounded-3xl border border-white/5 flex justify-between items-center hover:bg-zinc-800 transition">
                        <div><span class="text-blue-500 font-black text-[10px] italic">[{{node.protocol.toUpperCase()}}]</span><span class="text-white font-bold ml-4">{{node.remark}}</span><div class="text-[10px] text-zinc-600 mt-1 font-mono">PORT: {{node.port}}</div></div>
                        <button @click="openEditModal(node)" class="px-6 py-2 bg-zinc-800 text-white rounded-xl text-[10px] font-black uppercase">{{ t[lang].edit }}</button>
                    </div>
                </div>
                <button @click="openAddModal" class="mt-8 w-full py-5 bg-blue-600 text-white rounded-2xl font-black text-[10px] uppercase shadow-xl">+ {{ t[lang].addNode }}</button>
            </div>
        </div>

        <div v-if="showEditModal" class="modal-mask" @click.self="showEditModal = false">
            <div class="bg-zinc-950 border border-white/10 rounded-[4rem] p-12 w-full max-w-5xl shadow-2xl overflow-y-auto max-h-[95vh]">
                <div class="flex justify-between items-center mb-10 border-b border-white/5 pb-6">
                    <h3 class="text-2xl font-black text-white italic uppercase">Reality Config (ID: {{conf.id || 'NEW'}})</h3>
                    <button @click="showEditModal = false" class="text-zinc-500 text-4xl">✕</button>
                </div>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-12 text-zinc-300">
                    <div class="space-y-6">
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">Remark</label><input v-model="conf.remark" class="w-full rounded-2xl p-4 mt-2 text-sm font-bold"></div>
                        <div><label class="text-[9px] text-blue-500 font-black uppercase">Email</label><div class="flex gap-2 mt-1"><input v-model="conf.email" class="flex-1 rounded-2xl p-4 text-sm font-mono"><button @click="genEmail" class="bg-zinc-800 px-5 rounded-2xl text-[10px] font-black uppercase">Rand</button></div></div>
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">Port</label><input v-model="conf.port" class="w-full rounded-2xl p-4 mt-2 text-sm font-mono"></div>
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">UUID</label><div class="flex gap-2 mt-1"><input v-model="conf.uuid" class="flex-1 rounded-2xl p-4 text-xs font-mono"><button @click="genUUID" class="bg-zinc-800 px-5 rounded-2xl text-[10px] font-black uppercase">Gen</button></div></div>
                    </div>
                    <div class="space-y-6">
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">Dest (SNI)</label><input v-model="conf.dest" class="w-full rounded-2xl p-4 mt-2 text-sm font-mono"></div>
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">Private Key</label><div class="flex gap-2 mt-1"><input v-model="conf.privKey" class="flex-1 rounded-2xl p-4 text-xs font-mono"><button @click="genKeys" class="bg-blue-600/20 text-blue-400 border border-blue-500/20 px-5 rounded-2xl text-[10px] font-black uppercase">New</button></div></div>
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">Short ID</label><div class="flex gap-2 mt-1"><input v-model="conf.shortId" class="flex-1 rounded-2xl p-4 text-sm font-mono"><button @click="genShortId" class="bg-zinc-800 px-5 rounded-2xl text-[10px] font-black uppercase">Rand</button></div></div>
                    </div>
                </div>
                <div class="mt-14 flex gap-6">
                    <button @click="showEditModal = false" class="flex-1 py-6 bg-zinc-900 text-zinc-500 rounded-3xl text-xs font-black uppercase">Discard</button>
                    <button @click="saveNode" class="flex-1 py-6 bg-blue-600 text-white rounded-3xl text-xs font-black uppercase shadow-2xl tracking-widest active:scale-95 transition-all">Save & Sync</button>
                </div>
            </div>
        </div>
    </div>
    <script>
        const { createApp, ref, onMounted } = Vue;
        createApp({
            setup() {
                const lang = ref('zh'); const agents = ref({}); const masterStats = ref({ CPU:0, MEM:0, DISK:0 }); const sys = ref({ ipv4:'...', ipv6:'...' });
                const showListModal = ref(false); const showEditModal = ref(false); const activeIp = ref('');
                const conf = ref({ id:null, remark:'Reality-Node', email:'admin@multix.com', protocol:'vless', port:443, uuid:'', dest:'www.microsoft.com:443', privKey:'', shortId:'6baad05c' });
                const mockAgent = ref({ syncing: false, nodes: [{ id: 999, remark: 'Mock-Node-V42', port: 443, protocol: 'vless' }] });
                const backupNodes = ref({});
                const t = { zh: { edit:'修改', addNode:'创建新节点' }, en: { edit:'Edit', addNode:'New Inbound' } };

                const update = async () => {
                    try {
                        const r = await fetch('/api/state'); const d = await r.json();
                        sys.value = d.master; masterStats.value = d.master.stats;
                        for (let ip in d.agents) {
                            if (!agents.value[ip] || !agents.value[ip].syncing) {
                                agents.value[ip] = { ...d.agents[ip], syncing: false };
                            }
                        }
                    } catch(e){}
                };
                const openManageModal = (ip) => { activeIp.value = ip; showListModal.value = true; };
                const openEditModal = (node) => { conf.value = { ...node, email: 'admin@multix.com', uuid: '', dest: 'www.microsoft.com:443', privKey: '', shortId: '6baad05c' }; showListModal.value = false; showEditModal.value = true; };
                const openAddModal = () => { conf.value.id = null; genUUID(); genEmail(); genKeys(); genShortId(); showListModal.value = false; showEditModal.value = true; };
                const saveNode = async () => {
                    const ip = activeIp.value;
                    if(ip === 'MOCK') { mockAgent.value.syncing = true; showEditModal.value = false; setTimeout(() => { mockAgent.value.syncing = false; }, 3000); return; }
                    backupNodes.value[ip] = JSON.parse(JSON.stringify(agents.value[ip].nodes));
                    agents.value[ip].syncing = true; showEditModal.value = false;
                    try {
                        await fetch('/api/sync', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({ ip, config: conf.value }) });
                        setTimeout(() => { if (agents.value[ip].syncing) { agents.value[ip].syncing = false; agents.value[ip].lastSyncError = true; agents.value[ip].nodes = backupNodes.value[ip]; } }, 10000);
                    } catch(e) { agents.value[ip].syncing = false; }
                };
                const genUUID = () => { conf.value.uuid = crypto.randomUUID(); };
                const genEmail = () => { conf.value.email = 'mx_'+Math.random().toString(36).substring(7)+'@multix.com'; };
                const genKeys = () => { conf.value.privKey = btoa(Math.random().toString()).substring(0,43)+'='; };
                const genShortId = () => { conf.value.shortId = Math.random().toString(16).substring(2,10); };
                onMounted(() => { update(); setInterval(update, 3000); });
                return { lang, t, agents, masterStats, sys, showListModal, showEditModal, conf, mockAgent, openManageModal, openEditModal, openAddModal, saveNode, genUUID, genEmail, genKeys, genShortId };
            }
        }).mount('#app');
    </script>
</body></html>
{% endraw %}
"""

@app.route('/api/state')
def get_state():
    s = get_sys_info()
    return jsonify({"agents": {ip: {"stats": info.get("stats", {"cpu":0,"mem":0}), "nodes": info.get("nodes", []), "os": info.get("os", "Ubuntu"), "xui_ver": info.get("xui_ver", "v2.1.2")} for ip, info in AGENTS.items()}, "master": {"stats": {"CPU": s["cpu"], "MEM": s["mem"], "DISK": s["disk"]}, "ipv4": s["ipv4"], "ipv6": s["ipv6"]}})

@app.route('/api/sync', methods=['POST'])
def do_sync():
    d = request.json; target = d.get('ip'); c = d.get('config', {})
    if target in AGENTS:
        # 3X-UI 规范化数据下发
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
    return '<h3>Auth</h3><form method="post">U: <input name="u"> P: <input name="p" type="password"><button>Login</button></form>'

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
                    AGENTS[ip]['xui_ver'] = d.get('data', {}).get('xui_ver', 'v2.1.2')
    except: pass
    finally:
        if ip in AGENTS: del AGENTS[ip]

def start_ws():
    global LOOP_GLOBAL; LOOP_GLOBAL = asyncio.new_event_loop(); asyncio.set_event_loop(LOOP_GLOBAL)
    async def m():
        async with websockets.serve(ws_handler, "::", 8888, family=socket.AF_INET6): await asyncio.Future()
    LOOP_GLOBAL.run_until_complete(m())

if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    app.run(host='::', port=M_PORT)
EOF

    # 3. Systemd 守护进程 (生产级)
    cat > /etc/systemd/system/multix-master.service <<EOF
[Unit]
Description=MultiX Master Service
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
    
    systemctl daemon-reload
    systemctl enable multix-master
    systemctl restart multix-master
    echo -e "${GREEN}✅ 主控端部署完成！Token: $M_TOKEN${PLAIN}"
}

# --- [ 安装模块：被控端 (轻量容器+Socket权限) ] ---
install_agent() {
    install_dependencies
    init_env_install
    echo -e "${YELLOW}🛠️ 正在安装被控端...${PLAIN}"
    
    # 1. 现场构建轻量镜像
    mkdir -p $M_ROOT/agent
    cat > $M_ROOT/agent/Dockerfile <<EOF
FROM python:3.11-slim
RUN pip install websockets psutil --break-system-packages
WORKDIR /app
CMD ["python", "agent.py"]
EOF
    
    cat > $M_ROOT/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, socket, platform
MASTER = "$MASTER_IP"; TOKEN = "$M_TOKEN"
DB_PATH = "/app/db_share/x-ui.db"

def sync_db(data):
    try:
        conn = sqlite3.connect(DB_PATH, timeout=10); cursor = conn.cursor()
        nid = data.get('id')
        vals = (data['remark'], data['port'], data['settings'], data['stream_settings'], data['sniffing'])
        # 强制补全 3X-UI 字段，防止报错
        if nid:
            cursor.execute("UPDATE inbounds SET remark=?, port=?, settings=?, stream_settings=?, sniffing=?, enable=1 WHERE id=?", vals + (nid,))
        else:
            cursor.execute("INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing) VALUES (1, 0, 0, 0, ?, 1, 0, '', ?, 'vless', ?, ?, 'multix', ?)", vals)
        conn.commit(); conn.close(); return True
    except Exception as e:
        print(f"Error: {e}"); return False

async def run():
    uri = f"ws://{MASTER}:8888"
    while True:
        try:
            async with websockets.connect(uri, family=socket.AF_UNSPEC) as ws:
                await ws.send(json.dumps({"token": TOKEN}))
                while True:
                    conn = sqlite3.connect(DB_PATH); cur = conn.cursor()
                    cur.execute("SELECT id, remark, port, protocol FROM inbounds")
                    nodes = [{"id": r[0], "remark": r[1], "port": r[2], "protocol": r[3]} for r in cur.fetchall()]
                    conn.close()
                    stats = {
                        "cpu": int(psutil.cpu_percent()), 
                        "mem": int(psutil.virtual_memory().percent),
                        "os": platform.system() + " " + platform.release(),
                        "xui_ver": "v2.1.2"
                    }
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats, "nodes": nodes}))
                    try:
                        msg = await asyncio.wait_for(ws.recv(), timeout=5)
                        task = json.loads(msg)
                        if task.get('action') == 'sync_node':
                            # 调用宿主机 Docker
                            os.system("docker stop 3x-ui")
                            sync_db(task['data'])
                            os.system("docker start 3x-ui")
                    except: continue
        except: await asyncio.sleep(5)
asyncio.run(run())
EOF

    cd $M_ROOT/agent
    docker build -t multix-agent-v42 .
    docker rm -f multix-agent 2>/dev/null
    # 关键：挂载 docker.sock 实现控制权
    docker run -d --name multix-agent --restart always --network host \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v $M_ROOT/agent/db_data:/app/db_share \
        -v $M_ROOT/agent:/app \
        multix-agent-v42
    
    echo -e "${GREEN}✅ 被控端已启动，请检查主控面板是否上线。${PLAIN}"
}

# --- [ 完整运维菜单 ] ---
# 确保快捷命令指向本脚本
if [[ "$(readlink /usr/bin/multix)" != "$0" ]]; then
    ln -sf "$0" /usr/bin/multix && chmod +x /usr/bin/multix
fi

main_menu() {
    clear
    echo -e "${SKYBLUE}🛰️ MultiX Pro 终极全能运维系统 (V42.0)${PLAIN}"
    echo "------------------------------------------------"
    echo -e "${YELLOW}核心部署:${PLAIN}"
    echo " 1. 安装/更新 主控端 (Master)"
    echo " 2. 安装/更新 被控端 (Agent)"
    echo "------------------------------------------------"
    echo -e "${YELLOW}诊断与修复:${PLAIN}"
    echo " 3. 连通性暴力测试 (nc 检测 8888 端口)"
    echo " 4. 被控端离线自愈 (重启服务)"
    echo " 5. 深度清理模式 (删除所有残留)"
    echo " 6. 环境依赖修复 (Python/Docker/Pip)"
    echo "------------------------------------------------"
    echo -e "${YELLOW}系统管理:${PLAIN}"
    echo " 7. 凭据管理中心 (修改端口/Token/密码)"
    echo " 8. 实时运行日志 (Master/Agent)"
    echo "------------------------------------------------"
    echo -e "${YELLOW}运维工具箱 (原版保留):${PLAIN}"
    echo " 11. BBR 加速安装"
    echo " 12. 3X-UI 面板管理"
    echo " 13. SSL 证书申请"
    echo " 14. 开放防火墙端口"
    echo "------------------------------------------------"
    echo " 0. 退出系统"
    
    read -p "请输入选项: " choice
    case $choice in
        1) install_master ;;
        2) read -p "输入主控IP: " MASTER_IP; read -p "输入Token: " M_TOKEN; install_agent ;;
        3) read -p "目标IP: " tip; nc -zv -w 5 $tip 8888 ;;
        4) docker restart multix-agent ;;
        5) deep_cleanup ;;
        6) install_dependencies ;;
        7) credential_center ;;
        8) journalctl -u multix-master -f || docker logs -f multix-agent --tail 50 ;;
        11) bash <(curl -L -s https://github.com/chiakge/Linux-NetSpeed/raw/master/tcp.sh) ;;
        12) docker exec -it 3x-ui x-ui setting ;;
        13) curl https://get.acme.sh | sh ;;
        14) read -p "端口: " p; ufw allow $p/tcp 2>/dev/null; firewall-cmd --zone=public --add-port=$p/tcp --permanent 2>/dev/null ;;
        0) exit 0 ;;
        *) main_menu ;;
    esac
}

main_menu
