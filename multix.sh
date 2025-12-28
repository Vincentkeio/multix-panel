#!/bin/bash

# ==============================================================================
# MultiX Pro Perfect Interaction Edition (V43.0)
# 包含：开局快捷键 | 交互式Token | 双栈检测 | 混合凭据管理 | 菜单自循环
# ==============================================================================

# --- [ 全局配置 ] ---
export M_ROOT="/opt/multix_mvp"
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ V43 核心：运行时立即安装快捷命令 ] ---
if [[ "$(readlink -f /usr/bin/multix)" != "$(readlink -f $0)" ]]; then
    cp "$0" /usr/bin/multix && chmod +x /usr/bin/multix
    echo -e "${GREEN}✅ multix 快捷命令已安装，随时输入 multix 调出完整菜单。${PLAIN}"
fi

# --- [ 基础工具函数 ] ---
check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}错误: 请使用 root 用户运行此脚本！${PLAIN}" && exit 1
}

get_public_ips() {
    IPV4=$(curl -s4m 2 api.ipify.org || echo "未检测到")
    IPV6=$(curl -s6m 2 api64.ipify.org || echo "未检测到")
}

pause_back() {
    echo -e "\n${YELLOW}按任意键返回主菜单...${PLAIN}"
    read -n 1 -s -r
    main_menu
}

install_dependencies() {
    echo -e "${YELLOW}⚙️ 正在检查并修复系统环境依赖...${PLAIN}"
    if [[ -f /etc/redhat-release ]]; then
        yum install -y epel-release && yum install -y python3 python3-devel python3-pip curl wget socat tar openssl
    else
        apt-get update && apt-get install -y python3 python3-pip curl wget socat tar openssl
    fi
    # 修复 Python 依赖 (兼容各种系统环境)
    pip3 install flask websockets psutil --break-system-packages >/dev/null 2>&1 || pip3 install flask websockets psutil >/dev/null 2>&1
    
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}正在安装 Docker...${PLAIN}"
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker && systemctl start docker
    fi
    echo -e "${GREEN}✅ 环境依赖修复完成。${PLAIN}"
}

# --- [ 功能：深度清理 ] ---
deep_cleanup() {
    echo -e "${RED}⚠️ 正在执行深度清理模式...${PLAIN}"
    systemctl stop multix-master 2>/dev/null
    systemctl disable multix-master 2>/dev/null
    rm -f /etc/systemd/system/multix-master.service
    systemctl daemon-reload
    
    docker stop multix-agent 2>/dev/null
    docker rm -f multix-agent 2>/dev/null
    # 清理相关镜像，防止旧代码残留
    docker rmi $(docker images | grep "multix-agent" | awk '{print $3}') 2>/dev/null
    
    pkill -9 -f "master/app.py"
    pkill -9 -f "agent/agent.py"
    echo -e "${GREEN}✅ 深度清理完成 (配置文件已保留)。${PLAIN}"
    pause_back
}

# --- [ V43 核心：混合凭据管理中心 ] ---
credential_center() {
    clear
    echo -e "${SKYBLUE}🔐 MultiX 混合凭据管理中心${PLAIN}"
    echo "=================================================="
    
    # 1. 显示主控配置
    if [ -f $M_ROOT/.env ]; then
        source $M_ROOT/.env
        get_public_ips
        echo -e "${YELLOW}[本机主控端配置]${PLAIN}"
        echo -e "  面板入口(IPv4): http://${IPV4}:${M_PORT}"
        [[ "$IPV6" != "未检测到" ]] && echo -e "  面板入口(IPv6): http://[${IPV6}]:${M_PORT}"
        echo -e "  用户: ${GREEN}$M_USER${PLAIN} | 密码: ${GREEN}$M_PASS${PLAIN}"
        echo -e "  Token: ${SKYBLUE}$M_TOKEN${PLAIN}"
    else
        echo -e "${YELLOW}[本机主控端]${PLAIN}: 未安装"
    fi
    
    echo "--------------------------------------------------"
    
    # 2. 显示被控配置 (从 agent.py 提取)
    AGENT_FILE="$M_ROOT/agent/agent.py"
    if [ -f "$AGENT_FILE" ]; then
        CUR_MASTER=$(grep 'MASTER =' $AGENT_FILE | cut -d'"' -f2)
        CUR_TOKEN=$(grep 'TOKEN =' $AGENT_FILE | cut -d'"' -f2)
        echo -e "${YELLOW}[本机被控端配置]${PLAIN}"
        echo -e "  连接主控IP: ${GREEN}$CUR_MASTER${PLAIN}"
        echo -e "  使用Token:  ${SKYBLUE}$CUR_TOKEN${PLAIN}"
    else
        echo -e "${YELLOW}[本机被控端]${PLAIN}: 未安装"
    fi
    
    echo "=================================================="
    echo "1. 修改 [主控] 端口/密码/Token"
    echo "2. 修改 [被控] 连接的主控IP/Token"
    echo "0. 返回主菜单"
    read -p "请选择: " c_opt
    
    case $c_opt in
        1)
            [ ! -f $M_ROOT/.env ] && echo "未安装主控" && pause_back
            read -p "新端口 ($M_PORT): " np; M_PORT=${np:-$M_PORT}
            read -p "新用户 ($M_USER): " nu; M_USER=${nu:-$M_USER}
            read -p "新密码 ($M_PASS): " npa; M_PASS=${npa:-$M_PASS}
            read -p "新Token ($M_TOKEN): " nt; M_TOKEN=${nt:-$M_TOKEN}
            echo -e "M_TOKEN=$M_TOKEN\nM_PORT=$M_PORT\nM_USER=$M_USER\nM_PASS=$M_PASS" > $M_ROOT/.env
            echo -e "${GREEN}已更新配置，正在重启主控服务...${PLAIN}"
            systemctl restart multix-master
            ;;
        2)
            [ ! -f "$AGENT_FILE" ] && echo "未安装被控" && pause_back
            read -p "新主控IP ($CUR_MASTER): " nm; NEW_MASTER=${nm:-$CUR_MASTER}
            read -p "新Token ($CUR_TOKEN): " nt; NEW_TOKEN=${nt:-$CUR_TOKEN}
            # 使用 sed 替换文件内容
            sed -i "s/MASTER = \".*\"/MASTER = \"$NEW_MASTER\"/" $AGENT_FILE
            sed -i "s/TOKEN = \".*\"/TOKEN = \"$NEW_TOKEN\"/" $AGENT_FILE
            # 重建容器以生效
            echo -e "${GREEN}已更新连接信息，正在重载 Agent 容器...${PLAIN}"
            docker restart multix-agent
            ;;
        0) main_menu ;;
        *) credential_center ;;
    esac
    pause_back
}

# --- [ V43 核心：主控安装 (交互优化) ] ---
install_master() {
    install_dependencies
    mkdir -p $M_ROOT/master $M_ROOT/agent/db_data
    
    # 交互式配置
    echo -e "${SKYBLUE}>>> 配置主控端参数 (回车使用默认值)${PLAIN}"
    read -p "管理端口 [7575]: " IN_PORT; M_PORT=${IN_PORT:-7575}
    read -p "管理用户 [admin]: " IN_USER; M_USER=${IN_USER:-admin}
    read -p "管理密码 [admin]: " IN_PASS; M_PASS=${IN_PASS:-admin}
    
    # Token 逻辑：默认生成高强度，用户可覆写
    DEFAULT_TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    echo -e "默认随机 Token: ${YELLOW}${DEFAULT_TOKEN}${PLAIN}"
    read -p "设置 Token [回车使用默认]: " IN_TOKEN
    M_TOKEN=${IN_TOKEN:-$DEFAULT_TOKEN}
    
    # 固化变量
    echo -e "M_TOKEN=$M_TOKEN\nM_PORT=$M_PORT\nM_USER=$M_USER\nM_PASS=$M_PASS" > $M_ROOT/.env
    
    echo -e "${YELLOW}🛰️ 正在部署主控端 (三级 UI + 物理 Token)...${PLAIN}"
    
    # 写入主程序 (完整保留 V39/V40 的三级 UI 逻辑)
    cat > $M_ROOT/master/app.py <<EOF
import json, asyncio, time, psutil, os, socket, logging
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread

# 物理注入
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

# 旗舰 UI (三级交互 + 物理 Token)
HTML_T = """
{% raw %}
<!DOCTYPE html>
<html class="dark">
<head>
    <meta charset="UTF-8"><title>MultiX Pro V43</title>
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
                <button @click="openManageModal(ip)" class="w-full py-5 bg-blue-600 text-white rounded-3xl font-black text-[10px] uppercase shadow-lg">Manage Nodes</button>
            </div>
        </div>

        <div v-if="showListModal" class="modal-mask" @click.self="showListModal = false">
            <div class="bg-zinc-950 border border-white/10 rounded-[3rem] p-10 w-full max-w-4xl shadow-2xl max-h-[85vh] flex flex-col">
                <div class="flex justify-between items-center mb-8 border-b border-white/5 pb-4">
                    <h3 class="text-2xl font-black text-white italic uppercase">{{activeIp}} Inbounds</h3>
                    <button @click="showListModal = false" class="text-zinc-500 text-3xl">✕</button>
                </div>
                <div class="flex-1 overflow-y-auto space-y-4 pr-2">
                    <div v-for="node in (activeIp == 'MOCK' ? mockAgent.nodes : agents[activeIp].nodes)" :key="node.id" class="bg-zinc-900/50 p-6 rounded-3xl border border-white/5 flex justify-between items-center hover:bg-zinc-800 transition">
                        <div><span class="text-blue-500 font-black text-[10px] italic">[{{node.protocol.toUpperCase()}}]</span><span class="text-white font-bold ml-4">{{node.remark}}</span><div class="text-[10px] text-zinc-600 mt-1 font-mono">PORT: {{node.port}}</div></div>
                        <button @click="openEditModal(node)" class="px-6 py-2 bg-zinc-800 text-white rounded-xl text-[10px] font-black uppercase">{{ t[lang].edit }}</button>
                    </div>
                </div>
                <button @click="openAddModal" class="mt-8 w-full py-5 bg-blue-600 text-white rounded-2xl font-black text-[10px] uppercase">+ {{ t[lang].addNode }}</button>
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
                        <div><label class="text-[9px] text-blue-500 font-black uppercase">Email</label><div class="flex gap-2 mt-1"><input v-model="conf.email" class="flex-1 rounded-2xl p-4 text-sm font-mono"><button @click="genEmail" class="bg-zinc-800 px-5 rounded-2xl text-[10px] font-black">Rand</button></div></div>
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">Port</label><input v-model="conf.port" class="w-full rounded-2xl p-4 mt-2 text-sm font-mono"></div>
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">UUID</label><div class="flex gap-2 mt-1"><input v-model="conf.uuid" class="flex-1 rounded-2xl p-4 text-xs font-mono"><button @click="genUUID" class="bg-zinc-800 px-5 rounded-2xl text-[10px] font-black">Gen</button></div></div>
                    </div>
                    <div class="space-y-6">
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">Dest (SNI)</label><input v-model="conf.dest" class="w-full rounded-2xl p-4 mt-2 text-sm font-mono"></div>
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">Private Key</label><div class="flex gap-2 mt-1"><input v-model="conf.privKey" class="flex-1 rounded-2xl p-4 text-xs font-mono"><button @click="genKeys" class="bg-blue-600/20 text-blue-400 border border-blue-500/20 px-5 rounded-2xl text-[10px] font-black">New</button></div></div>
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">Short ID</label><div class="flex gap-2 mt-1"><input v-model="conf.shortId" class="flex-1 rounded-2xl p-4 text-sm font-mono"><button @click="genShortId" class="bg-zinc-800 px-5 rounded-2xl text-[10px] font-black">Rand</button></div></div>
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
                const mockAgent = ref({ syncing: false, nodes: [{ id: 999, remark: 'Mock-Node-V43', port: 443, protocol: 'vless' }] });
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
                    agents.value[ip].syncing = true; showEditModal.value = false;
                    try {
                        await fetch('/api/sync', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({ ip, config: conf.value }) });
                        setTimeout(() => { if (agents.value[ip].syncing) { agents.value[ip].syncing = false; agents.value[ip].lastSyncError = true; } }, 10000);
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
        # 下发数据，严格符合 3X-UI 规范
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

    # Systemd 守护
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
    
    # 成功提示 (含双栈检测)
    get_public_ips
    echo -e "${GREEN}✅ 主控端部署成功！${PLAIN}"
    echo -e "   ---------------------------------------"
    echo -e "   入口 (IPv4): http://${IPV4}:${M_PORT}"
    [[ "$IPV6" != "未检测到" ]] && echo -e "   入口 (IPv6): http://[${IPV6}]:${M_PORT}"
    echo -e "   用户: $M_USER  密码: $M_PASS"
    echo -e "   Token: ${YELLOW}$M_TOKEN${PLAIN}"
    echo -e "   ---------------------------------------"
    pause_back
}

# --- [ 部署：被控端 (数据库规范化) ] ---
install_agent() {
    install_dependencies
    mkdir -p $M_ROOT/agent
    
    # 现场构建轻量镜像
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
        # 强制补全字段
        if nid:
            cursor.execute("UPDATE inbounds SET remark=?, port=?, settings=?, stream_settings=?, sniffing=?, enable=1 WHERE id=?", vals + (nid,))
        else:
            cursor.execute("INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing) VALUES (1, 0, 0, 0, ?, 1, 0, '', ?, 'vless', ?, ?, 'multix', ?)", vals)
        conn.commit(); conn.close(); return True
    except: return False

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
                        "cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent),
                        "os": platform.system() + " " + platform.release(), "xui_ver": "v2.1.2"
                    }
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats, "nodes": nodes}))
                    try:
                        msg = await asyncio.wait_for(ws.recv(), timeout=5)
                        task = json.loads(msg)
                        if task.get('action') == 'sync_node':
                            os.system("docker stop 3x-ui")
                            sync_db(task['data'])
                            os.system("docker start 3x-ui")
                    except: continue
        except: await asyncio.sleep(5)
asyncio.run(run())
EOF

    cd $M_ROOT/agent
    docker build -t multix-agent-v43 .
    docker rm -f multix-agent 2>/dev/null
    # 挂载权限
    docker run -d --name multix-agent --restart always --network host \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v $M_ROOT/agent/db_data:/app/db_share \
        -v $M_ROOT/agent:/app \
        multix-agent-v43
    
    echo -e "${GREEN}✅ 被控端已启动。请在主控面板确认上线状态。${PLAIN}"
    pause_back
}

# --- [ 完整运维菜单 ] ---
sys_tools() {
    while true; do
        clear
        echo -e "${YELLOW}🧰 MultiX 系统运维工具箱${PLAIN}"
        echo "--------------------------"
        echo "1. 开启 BBR 加速"
        echo "2. 安装/重装 3X-UI 面板"
        echo "3. 申请 SSL 证书"
        echo "4. 重置 3X-UI 面板账号"
        echo "5. 清空流量统计"
        echo "6. 开放防火墙端口"
        echo "0. 返回主菜单"
        read -p "选择: " t_opt
        case $t_opt in
            1) bash <(curl -L -s https://github.com/chiakge/Linux-NetSpeed/raw/master/tcp.sh) ;;
            2) bash <(curl -Ls https://raw.githubusercontent.com/mzz2017/v2ray-util/master/install.sh) ;;
            3) curl https://get.acme.sh | sh ;;
            4) docker exec -it 3x-ui x-ui setting ;;
            5) sqlite3 $M_ROOT/agent/db_data/x-ui.db "UPDATE client_traffics SET up=0, down=0;" && echo "流量已归零" ;;
            6) read -p "输入端口: " p; ufw allow $p/tcp 2>/dev/null; firewall-cmd --zone=public --add-port=$p/tcp --permanent 2>/dev/null ;;
            0) break ;;
            *) echo "无效选择" ;;
        esac
        read -n 1 -s -r -p "按任意键继续..."
    done
    main_menu
}

main_menu() {
    clear
    echo -e "${SKYBLUE}🛰️ MultiX Pro 终极交互版 (V43.0)${PLAIN}"
    echo "------------------------------------------------"
    echo -e "${YELLOW}核心部署:${PLAIN}"
    echo " 1. 安装/更新 主控端 (Master)"
    echo " 2. 安装/更新 被控端 (Agent)"
    echo "------------------------------------------------"
    echo -e "${YELLOW}诊断与修复:${PLAIN}"
    echo " 3. 连通性测试 (nc 探测主控)"
    echo " 4. 被控离线修复 (重启服务)"
    echo " 5. 深度清理模式 (删除残留)"
    echo " 6. 环境依赖修复 (Python/Docker)"
    echo "------------------------------------------------"
    echo -e "${YELLOW}系统管理:${PLAIN}"
    echo " 7. 混合凭据中心 (查看/修改/重启)"
    echo " 8. 实时运行日志"
    echo " 9. 运维工具箱 (BBR/SSL/3XUI...)"
    echo "------------------------------------------------"
    echo " 0. 退出系统"
    
    read -p "请输入选项: " choice
    case $choice in
        1) install_master ;;
        2) read -p "输入主控IP: " MASTER_IP; read -p "输入Token: " M_TOKEN; install_agent ;;
        3) read -p "目标IP: " tip; nc -zv -w 5 $tip 8888; pause_back ;;
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
