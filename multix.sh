#!/bin/bash

# ==============================================================================
# MultiX Pro Script V48.1 (V48 Fixed Dual-Stack Edition)
# Author: Vincentkeio & Gemini
# Feature: 3X-UI Sync | Dual Stack Fixed | Full UI Interaction | Robust Installer
# ==============================================================================

# --- [ 全局变量定义 ] ---
export M_ROOT="/opt/multix_mvp"
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
SH_VER="V48.1"

# --- [ 颜色配置 ] ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

# --- [ 0. 快捷命令驻留 (开局自检) ] ---
install_shortcut() {
    if [[ "$(readlink -f /usr/bin/multix)" != "$(readlink -f $0)" ]]; then
        cp "$0" /usr/bin/multix && chmod +x /usr/bin/multix
        echo -e "${GREEN}[INFO]${PLAIN} multix 快捷命令已安装成功"
    fi
}
install_shortcut

# --- [ 1. 系统环境检测函数 ] ---
check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}[ERROR]${PLAIN} 请使用 root 用户运行此脚本！" && exit 1
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

install_base() {
    echo -e "${YELLOW}[INFO]${PLAIN} 正在检查系统基础依赖..."
    check_sys
    if [[ "${RELEASE}" == "centos" ]]; then
        yum install -y epel-release
        yum install -y python3 python3-devel python3-pip curl wget socat tar openssl git
    else
        apt-get update
        apt-get install -y python3 python3-pip curl wget socat tar openssl git
    fi
    echo -e "${GREEN}[INFO]${PLAIN} 系统基础依赖检查完毕"
}

check_python_dep() {
    echo -e "${YELLOW}[INFO]${PLAIN} 正在检查 Python 运行环境..."
    # 尝试安装，屏蔽系统包管理器的警告
    pip3 install flask websockets psutil --break-system-packages >/dev/null 2>&1 || pip3 install flask websockets psutil >/dev/null 2>&1
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}[INFO]${PLAIN} 未检测到 Docker，开始安装..."
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker && systemctl start docker
        echo -e "${GREEN}[INFO]${PLAIN} Docker 安装完成"
    else
        echo -e "${GREEN}[INFO]${PLAIN} Docker 环境正常"
    fi
}

fix_dual_stack() {
    echo -e "${YELLOW}[INFO]${PLAIN} 正在修正双栈网络参数..."
    if grep -q "net.ipv6.bindv6only" /etc/sysctl.conf; then
        sed -i 's/net.ipv6.bindv6only.*/net.ipv6.bindv6only = 0/' /etc/sysctl.conf
    else
        echo "net.ipv6.bindv6only = 0" >> /etc/sysctl.conf
    fi
    sysctl -p >/dev/null 2>&1
}

# --- [ 2. 辅助工具函数 ] ---
get_public_ips() {
    IPV4=$(curl -s4m 2 api.ipify.org || echo "未检测到")
    IPV6=$(curl -s6m 2 api64.ipify.org || echo "未检测到")
}

resolve_ip() {
    local host=$1
    local type=$2
    python3 -c "import socket; 
try: print(socket.getaddrinfo('$host', None, socket.$type)[0][4][0])
except: pass"
}

pause_back() {
    echo -e "\n${YELLOW}按任意键返回主菜单...${PLAIN}"
    read -n 1 -s -r
    main_menu
}

# --- [ 3. 深度清理逻辑 ] ---
deep_cleanup() {
    echo -e "${RED}⚠️  警告：此操作将删除所有 MultiX 组件和数据！${PLAIN}"
    read -p "确认执行? [y/N]: " confirm
    [[ "$confirm" != "y" ]] && return

    echo -e "${YELLOW}[INFO]${PLAIN} 停止服务..."
    systemctl stop multix-master 2>/dev/null
    systemctl disable multix-master 2>/dev/null
    rm -f /etc/systemd/system/multix-master.service
    systemctl daemon-reload

    echo -e "${YELLOW}[INFO]${PLAIN} 清理容器与镜像..."
    docker stop multix-agent 2>/dev/null
    docker rm -f multix-agent 2>/dev/null
    docker rmi $(docker images | grep "multix-agent" | awk '{print $3}') 2>/dev/null

    echo -e "${YELLOW}[INFO]${PLAIN} 清理进程与文件..."
    pkill -9 -f "master/app.py"
    pkill -9 -f "agent/agent.py"
    # 保留 .env 除非用户手动删，防止误删配置
    echo -e "${GREEN}[INFO]${PLAIN} 清理完成 (.env 配置文件已保留)"
    pause_back
}

# --- [ 4. 凭据管理中心 ] ---
credential_center() {
    clear
    echo -e "${SKYBLUE}🔐 MultiX 凭据管理中心${PLAIN}"
    echo "=================================================="
    if [ -f $M_ROOT/.env ]; then
        source $M_ROOT/.env
        get_public_ips
        echo -e "${YELLOW}[ 主控端配置 ]${PLAIN}"
        echo -e "面板地址(v4): http://${IPV4}:${M_PORT}"
        [[ "$IPV6" != "未检测到" ]] && echo -e "面板地址(v6): http://[${IPV6}]:${M_PORT}"
        echo -e "User: ${GREEN}$M_USER${PLAIN} | Pass: ${GREEN}$M_PASS${PLAIN}"
        echo -e "Token: ${SKYBLUE}$M_TOKEN${PLAIN}"
    else
        echo -e "${YELLOW}[ 主控端 ]${PLAIN}: 未安装或未配置"
    fi
    
    AGENT_FILE="$M_ROOT/agent/agent.py"
    if [ -f "$AGENT_FILE" ]; then
        CUR_MASTER=$(grep 'MASTER =' $AGENT_FILE | cut -d'"' -f2)
        CUR_TOKEN=$(grep 'TOKEN =' $AGENT_FILE | cut -d'"' -f2)
        echo -e "\n${YELLOW}[ 被控端配置 ]${PLAIN}"
        echo -e "连接地址: ${GREEN}$CUR_MASTER${PLAIN}"
        echo -e "连接Token: ${SKYBLUE}$CUR_TOKEN${PLAIN}"
    fi
    echo "=================================================="
    echo " 1. 修改 [主控] 端口/用户/密码/Token"
    echo " 2. 修改 [被控] 目标IP/连接Token"
    echo " 0. 返回主菜单"
    echo "--------------------------------------------------"
    read -p "请输入选项: " c_opt
    case $c_opt in
        1)
            [ ! -f $M_ROOT/.env ] && echo "请先安装主控" && pause_back
            read -p "新端口 ($M_PORT): " np; M_PORT=${np:-$M_PORT}
            read -p "新用户 ($M_USER): " nu; M_USER=${nu:-$M_USER}
            read -p "新密码 ($M_PASS): " npa; M_PASS=${npa:-$M_PASS}
            read -p "新Token ($M_TOKEN): " nt; M_TOKEN=${nt:-$M_TOKEN}
            echo -e "M_TOKEN=$M_TOKEN\nM_PORT=$M_PORT\nM_USER=$M_USER\nM_PASS=$M_PASS" > $M_ROOT/.env
            systemctl restart multix-master
            echo -e "${GREEN}主控配置已更新并重启${PLAIN}"
            ;;
        2)
            [ ! -f "$AGENT_FILE" ] && echo "请先安装被控" && pause_back
            read -p "新主控IP ($CUR_MASTER): " nm; NEW_MASTER=${nm:-$CUR_MASTER}
            read -p "新Token ($CUR_TOKEN): " nt; NEW_TOKEN=${nt:-$CUR_TOKEN}
            sed -i "s/MASTER = \".*\"/MASTER = \"$NEW_MASTER\"/" $AGENT_FILE
            sed -i "s/TOKEN = \".*\"/TOKEN = \"$NEW_TOKEN\"/" $AGENT_FILE
            docker restart multix-agent
            echo -e "${GREEN}被控配置已更新并重连${PLAIN}"
            ;;
        0) main_menu ;;
        *) credential_center ;;
    esac
    pause_back
}

# --- [ 5. 主控端安装模块 ] ---
install_master() {
    check_root
    install_base
    check_python_dep
    fix_dual_stack
    
    mkdir -p $M_ROOT/master $M_ROOT/agent/db_data
    
    echo -e "${SKYBLUE}>>> 配置主控端参数${PLAIN}"
    # 读取旧配置或使用默认
    if [ -f $M_ROOT/.env ]; then source $M_ROOT/.env; fi
    
    read -p "管理端口 [${M_PORT:-7575}]: " IN_PORT; M_PORT=${IN_PORT:-${M_PORT:-7575}}
    read -p "管理用户 [${M_USER:-admin}]: " IN_USER; M_USER=${IN_USER:-${M_USER:-admin}}
    read -p "管理密码 [${M_PASS:-admin}]: " IN_PASS; M_PASS=${IN_PASS:-${M_PASS:-admin}}
    
    # Token 逻辑
    RAND_TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    CUR_TOKEN_SHOW=${M_TOKEN:-$RAND_TOKEN}
    read -p "API Token [默认随机: ${CUR_TOKEN_SHOW}]: " IN_TOKEN
    M_TOKEN=${IN_TOKEN:-$CUR_TOKEN_SHOW}
    
    # 写入配置
    echo -e "M_TOKEN=$M_TOKEN\nM_PORT=$M_PORT\nM_USER=$M_USER\nM_PASS=$M_PASS" > $M_ROOT/.env
    
    echo -e "${YELLOW}🛰️ 正在生成主控端核心程序 (V48.1 双栈修正版)...${PLAIN}"
    
    # 生成 app.py (包含 Vue3 前端)
    cat > $M_ROOT/master/app.py <<EOF
import json, asyncio, time, psutil, os, socket, logging
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread

# 物理注入 Token，防止渲染失败
M_PORT, M_USER, M_PASS, M_TOKEN = int("$M_PORT"), "$M_USER", "$M_PASS", "$M_TOKEN"

app = Flask(__name__)
app.secret_key = M_TOKEN
AGENTS = {}
LOOP_GLOBAL = None

def get_sys_info():
    try:
        return {
            "cpu": psutil.cpu_percent(), "mem": psutil.virtual_memory().percent,
            "ipv4": os.popen("curl -4 -s --connect-timeout 2 api.ipify.org").read().strip() or "N/A",
            "ipv6": os.popen("curl -6 -s --connect-timeout 2 api64.ipify.org").read().strip() or "N/A"
        }
    except: return {"cpu":0,"mem":0,"disk":0,"ipv4":"N/A","ipv6":"N/A"}

HTML_T = """
{% raw %}
<!DOCTYPE html>
<html class="dark">
<head>
    <meta charset="UTF-8"><title>MultiX Pro V48.1</title>
    <script src="https://unpkg.com/vue@3/dist/vue.global.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { background: #09090b; color: #e4e4e7; font-family: ui-sans-serif, system-ui; }
        .glass { background: rgba(24, 24, 27, 0.85); backdrop-filter: blur(12px); border: 1px solid rgba(255,255,255,0.08); }
        .modal-mask { background: rgba(0,0,0,0.95); position: fixed; inset: 0; z-index: 50; display: flex; align-items: center; justify-content: center; padding: 20px; }
        .sync-glow { animation: glow 2s infinite ease-in-out; }
        @keyframes glow { 0%, 100% { filter: drop-shadow(0 0 8px #f59e0b); opacity: 1; } 50% { opacity: 0.5; } }
        input { background: #18181b !important; border: 1px solid rgba(255,255,255,0.1) !important; color: #fff !important; outline: none; }
        input:focus { border-color: #3b82f6 !important; }
    </style>
</head>
<body class="p-6 md:p-12">
    <div id="app">
        <div class="flex flex-col md:flex-row justify-between items-center mb-10 gap-6">
            <div>
                <h1 class="text-4xl font-black text-blue-500 italic uppercase tracking-tighter">MultiX <span class="text-white">Pro</span></h1>
                <div class="mt-2 text-[10px] font-bold uppercase tracking-widest text-zinc-500 space-y-1">
                    <div>TOKEN: <span class="text-yellow-500 font-mono select-all">""" + M_TOKEN + """</span></div>
                    <div>IPv4: <span class="text-blue-400 select-all">{{ sys.ipv4 }}</span> | IPv6: <span class="text-purple-400 select-all">{{ sys.ipv6 }}</span></div>
                </div>
            </div>
            <div class="flex gap-3">
                <div v-for="(val, l) in masterStats" class="px-5 py-2 bg-zinc-900 border border-white/5 rounded-xl text-center">
                    <div class="text-[8px] text-zinc-500 uppercase font-bold">{{ l }}</div><div class="text-sm font-black text-white">{{ val }}%</div>
                </div>
            </div>
        </div>

        <div class="grid grid-cols-1 md:flex md:flex-wrap gap-6">
            <div v-for="agent in displayAgents" :key="agent.ip" class="glass rounded-[2rem] p-8 relative w-full md:w-[380px] hover:border-blue-500/30 transition-all duration-300">
                <div class="flex justify-between items-center mb-6">
                    <div @click="editAlias(agent)" class="cursor-pointer group">
                        <div class="text-xl font-black italic text-white group-hover:text-blue-400 transition">{{ agent.alias }} <span class="opacity-0 group-hover:opacity-100 text-xs">✎</span></div>
                        <div class="text-[10px] text-zinc-600 font-mono mt-1">{{ agent.ip }}</div>
                    </div>
                    <div :class="['h-3 w-3 rounded-full transition-all duration-500', agent.syncing ? 'bg-yellow-500 sync-glow' : (agent.lastSyncError ? 'bg-red-500' : 'bg-green-500')]"></div>
                </div>
                
                <div class="grid grid-cols-2 gap-4 mb-6">
                    <div class="bg-black/40 p-4 rounded-2xl border border-white/5 text-center"><div class="text-[9px] text-zinc-500 uppercase font-bold">CPU Load</div><div class="text-lg font-black text-zinc-200">{{agent.stats.cpu}}%</div></div>
                    <div class="bg-black/40 p-4 rounded-2xl border border-white/5 text-center"><div class="text-[9px] text-zinc-500 uppercase font-bold">RAM Usage</div><div class="text-lg font-black text-zinc-200">{{agent.stats.mem}}%</div></div>
                </div>
                
                <div class="text-center mb-8">
                    <div class="inline-block px-3 py-1 bg-zinc-900 rounded-lg text-[9px] text-zinc-500 font-bold uppercase tracking-widest border border-white/5">
                        {{ agent.os }} • 3X-UI {{ agent.xui_ver }} • {{ agent.nodes.length }} Nodes
                    </div>
                </div>
                
                <button @click="openManageModal(agent)" class="w-full py-4 bg-blue-600 hover:bg-blue-500 text-white rounded-2xl font-black text-xs uppercase shadow-lg shadow-blue-900/20 active:scale-95 transition-all tracking-widest">
                    Manage Nodes
                </button>
            </div>
        </div>

        <div v-if="showListModal" class="modal-mask" @click.self="showListModal = false">
            <div class="bg-zinc-950 border border-white/10 rounded-[2.5rem] p-8 w-full max-w-4xl shadow-2xl max-h-[85vh] flex flex-col">
                <div class="flex justify-between items-center mb-6 pb-4 border-b border-white/5">
                    <h3 class="text-2xl font-black text-white italic uppercase tracking-tight">{{ activeAgent.alias }} / Inbounds</h3>
                    <button @click="showListModal = false" class="text-zinc-500 hover:text-white text-3xl transition">✕</button>
                </div>
                <div class="flex-1 overflow-y-auto space-y-3 pr-2">
                    <div v-if="activeAgent.nodes.length === 0" class="text-center py-10 text-zinc-700 italic">No inbounds found. Create one?</div>
                    <div v-for="node in activeAgent.nodes" :key="node.id" class="bg-zinc-900/50 p-5 rounded-2xl border border-white/5 flex justify-between items-center group hover:border-blue-500/20 transition-all">
                        <div>
                            <div class="flex items-center gap-3">
                                <span class="text-blue-500 font-black text-[10px] bg-blue-500/10 px-2 py-1 rounded">{{ node.protocol.toUpperCase() }}</span>
                                <span class="text-white font-bold text-sm">{{ node.remark }}</span>
                                <span v-if="node.syncError" class="text-red-500 text-[9px] font-black bg-red-500/10 px-2 py-1 rounded">⚠️ UNSYNCED</span>
                            </div>
                            <div class="text-[10px] text-zinc-600 mt-1 font-mono pl-1">PORT: <span class="text-zinc-400">{{ node.port }}</span></div>
                        </div>
                        <button @click="openEditModal(node)" class="px-5 py-2 bg-zinc-800 hover:bg-zinc-700 text-white rounded-xl text-[10px] font-black uppercase transition-colors">Edit</button>
                    </div>
                </div>
                <button @click="openAddModal" class="mt-6 w-full py-4 bg-zinc-800 hover:bg-zinc-700 text-white rounded-2xl font-black text-xs uppercase transition-all border border-white/5">+ Create New Inbound</button>
            </div>
        </div>

        <div v-if="showEditModal" class="modal-mask" @click.self="showEditModal = false">
            <div class="bg-zinc-950 border border-white/10 rounded-[3rem] p-10 w-full max-w-5xl shadow-2xl overflow-y-auto max-h-[95vh]">
                <div class="flex justify-between items-center mb-8 border-b border-white/5 pb-6">
                    <h3 class="text-2xl font-black text-white italic uppercase">Configuration</h3>
                    <div class="text-[10px] text-zinc-500 font-mono bg-zinc-900 px-3 py-1 rounded-lg">{{ conf.id ? 'UUID: ' + conf.uuid : 'NEW NODE' }}</div>
                </div>
                
                <div class="grid grid-cols-1 md:grid-cols-2 gap-10">
                    <div class="space-y-5">
                        <div class="text-xs font-bold text-blue-500 uppercase tracking-widest mb-2">Basic Settings</div>
                        <div><label class="text-[10px] text-zinc-500 font-bold uppercase ml-1">Remark</label><input v-model="conf.remark" class="w-full rounded-xl p-3 mt-1 text-sm font-bold bg-black border-zinc-800"></div>
                        <div><label class="text-[10px] text-zinc-500 font-bold uppercase ml-1">Email</label><div class="flex gap-2 mt-1"><input v-model="conf.email" class="flex-1 rounded-xl p-3 text-sm font-mono"><button @click="genEmail" class="bg-zinc-800 px-4 rounded-xl text-[10px] font-black hover:bg-zinc-700">RAND</button></div></div>
                        <div><label class="text-[10px] text-zinc-500 font-bold uppercase ml-1">Port</label><input v-model="conf.port" class="w-full rounded-xl p-3 mt-1 text-sm font-mono"></div>
                        <div><label class="text-[10px] text-zinc-500 font-bold uppercase ml-1">UUID</label><div class="flex gap-2 mt-1"><input v-model="conf.uuid" class="flex-1 rounded-xl p-3 text-[10px] font-mono"><button @click="genUUID" class="bg-zinc-800 px-4 rounded-xl text-[10px] font-black hover:bg-zinc-700">GEN</button></div></div>
                    </div>
                    
                    <div class="space-y-5">
                        <div class="text-xs font-bold text-blue-500 uppercase tracking-widest mb-2">Reality Security</div>
                        <div class="bg-blue-500/5 p-5 rounded-3xl border border-blue-500/10 space-y-4">
                            <div><label class="text-[9px] text-zinc-500 font-bold uppercase ml-1">SNI Domain</label><input v-model="conf.dest" class="w-full rounded-xl p-3 mt-1 text-sm font-mono" placeholder="www.microsoft.com:443"></div>
                            <div><label class="text-[9px] text-zinc-500 font-bold uppercase ml-1">Private Key</label><div class="flex gap-2 mt-1"><input v-model="conf.privKey" class="flex-1 rounded-xl p-3 text-[10px] font-mono"><button @click="genKeys" class="bg-blue-600/20 text-blue-400 border border-blue-500/20 px-4 rounded-xl text-[9px] font-black hover:bg-blue-600/30">NEW</button></div></div>
                            <div><label class="text-[9px] text-zinc-500 font-bold uppercase ml-1">Short ID</label><div class="flex gap-2 mt-1"><input v-model="conf.shortId" class="flex-1 rounded-xl p-3 text-sm font-mono"><button @click="genShortId" class="bg-zinc-800 px-4 rounded-xl text-[10px] font-black hover:bg-zinc-700">RAND</button></div></div>
                        </div>
                    </div>
                </div>
                
                <div class="mt-10 flex gap-4 pt-6 border-t border-white/5">
                    <button @click="showEditModal = false" class="flex-1 py-5 bg-zinc-900 hover:bg-zinc-800 text-zinc-400 rounded-2xl text-xs font-black uppercase transition-all">Discard Changes</button>
                    <button @click="saveNode" class="flex-1 py-5 bg-blue-600 hover:bg-blue-500 text-white rounded-2xl text-xs font-black uppercase shadow-xl shadow-blue-600/10 active:scale-95 transition-all">
                        <span v-if="activeAgent.syncing">Syncing to Node...</span>
                        <span v-else>Save & Apply Sync</span>
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
                const showListModal = ref(false); const showEditModal = ref(false); 
                const activeAgent = ref({});
                const conf = ref({});
                
                // Mock Data 结构严格对齐
                const mockAgent = ref({ 
                    ip: 'MOCK-SERVER', 
                    alias: 'Example Node', 
                    stats: {cpu: 25, mem: 40}, 
                    nodes: [{id: 99, remark: 'Reality-Demo', port: 443, protocol: 'vless'}], 
                    syncing: false,
                    os: 'Ubuntu 22.04', xui_ver: 'v2.1.2' 
                });

                // 核心逻辑：合并 Mock 和 真实数据，保证 UI 循环一致
                const displayAgents = computed(() => {
                    const list = [mockAgent.value];
                    for (let ip in agents.value) {
                        // 补全字段防止 UI 报错
                        if(!agents.value[ip].alias) agents.value[ip].alias = 'Node-' + ip.split('.').pop();
                        agents.value[ip].ip = ip;
                        list.push(agents.value[ip]);
                    }
                    return list;
                });

                const update = async () => {
                    try {
                        const r = await fetch('/api/state'); const d = await r.json();
                        sys.value = d.master; masterStats.value = d.master.stats;
                        for (let ip in d.agents) {
                            if (!agents.value[ip]) {
                                agents.value[ip] = { ...d.agents[ip], syncing: false, lastSyncError: false };
                            } else if (!agents.value[ip].syncing) {
                                // 仅在非同步状态下更新，防止 UI 跳变
                                agents.value[ip].stats = d.agents[ip].stats;
                                agents.value[ip].nodes = d.agents[ip].nodes;
                                agents.value[ip].os = d.agents[ip].os;
                                agents.value[ip].xui_ver = d.agents[ip].xui_ver;
                            }
                        }
                    } catch(e){}
                };

                const editAlias = (agent) => { const n = prompt("Rename Node:", agent.alias); if(n) agent.alias = n; };
                const openManageModal = (agent) => { activeAgent.value = agent; showListModal.value = true; };
                
                const openEditModal = (node) => {
                    conf.value = { ...node, email: node.settings?.clients?.[0]?.email || 'admin@mx.com', uuid: node.settings?.clients?.[0]?.id || '', dest: 'www.microsoft.com:443', privKey: '', shortId: '' };
                    showListModal.value = false; showEditModal.value = true;
                };
                
                const openAddModal = () => {
                    conf.value = { id: null, remark: 'New-Reality', port: 443, protocol: 'vless', isNew: true };
                    genUUID(); genEmail(); genKeys(); genShortId();
                    showListModal.value = false; showEditModal.value = true;
                };

                const saveNode = async () => {
                    const agent = activeAgent.value;
                    if(agent.ip === 'MOCK-SERVER') {
                        mockAgent.value.syncing = true; showEditModal.value = false;
                        setTimeout(() => { mockAgent.value.syncing = false; }, 2000); return;
                    }
                    
                    const backupNodes = JSON.parse(JSON.stringify(agent.nodes));
                    agent.syncing = true; showEditModal.value = false;
                    
                    // 乐观更新
                    if (conf.value.isNew) agent.nodes.push(conf.value);

                    try {
                        await fetch('/api/sync', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({ ip: agent.ip, config: conf.value }) });
                        
                        // 10秒超时回滚机制
                        setTimeout(() => {
                            if (agent.syncing) {
                                agent.syncing = false; 
                                agent.lastSyncError = true;
                                if (conf.value.isNew) {
                                    const n = agent.nodes.find(n => n.remark === conf.value.remark);
                                    if(n) n.syncError = true; // 标记报警
                                } else {
                                    agent.nodes = backupNodes; // 回滚
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
                return { displayAgents, masterStats, sys, showListModal, showEditModal, conf, activeAgent, editAlias, openManageModal, openEditModal, openAddModal, saveNode, genUUID, genEmail, genKeys, genShortId };
            }
        }).mount('#app');
    </script>
</body></html>
{% endraw %}
"""

@app.route('/api/state')
def get_state():
    s = get_sys_info()
    return jsonify({"agents": {ip: {"stats": info.get("stats", {"cpu":0,"mem":0}), "nodes": info.get("nodes", []), "os": info.get("os", "Linux"), "xui_ver": info.get("xui_ver", "Unknown")} for ip, info in AGENTS.items()}, "master": {"stats": {"CPU": s["cpu"], "MEM": s["mem"]}, "ipv4": s["ipv4"], "ipv6": s["ipv6"]}})

@app.route('/api/sync', methods=['POST'])
def do_sync():
    d = request.json; target = d.get('ip'); c = d.get('config', {})
    if target in AGENTS:
        # 3X-UI 规范化数据包
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
                    AGENTS[ip]['xui_ver'] = d.get('data', {}).get('xui_ver', 'Unknown')
    except: pass
    finally:
        if ip in AGENTS: del AGENTS[ip]

def start_ws():
    global LOOP_GLOBAL; LOOP_GLOBAL = asyncio.new_event_loop(); asyncio.set_event_loop(LOOP_GLOBAL)
    async def m():
        # V48.1 核心修正：绑定 :: 配合内核 bindv6only=0 实现真·双栈
        async with websockets.serve(ws_handler, "::", 8888, family=socket.AF_INET6): await asyncio.Future()
    LOOP_GLOBAL.run_until_complete(m())

if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    app.run(host='::', port=M_PORT)
EOF

    # 4. 创建 Systemd 服务
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
    
    get_public_ips
    echo -e "${GREEN}✅ 主控端部署成功！${PLAIN}"
    echo -e "   IPv4入口: http://${IPV4}:${M_PORT}"
    [[ "$IPV6" != "未检测到" ]] && echo -e "   IPv6入口: http://[${IPV6}]:${M_PORT}"
    echo -e "   Token: ${YELLOW}$M_TOKEN${PLAIN}"
    pause_back
}

# --- [ 6. 被控端安装模块 (3X-UI 适配) ] ---
install_agent() {
    install_base
    check_docker
    mkdir -p $M_ROOT/agent
    
    echo -e "${SKYBLUE}>>> 配置被控端连接${PLAIN}"
    read -p "请输入主控域名或IP: " IN_HOST
    read -p "请输入主控Token: " IN_TOKEN
    
    echo -e "${YELLOW}连接协议选择 (NAT机/双栈机建议强制IPv6):${PLAIN}"
    echo " 1. 自动检测 (默认)"
    echo " 2. 强制 IPv4"
    echo " 3. 强制 IPv6"
    read -p "选择 [1-3]: " NET_OPT
    
    TARGET_HOST="$IN_HOST"
    if [[ "$NET_OPT" == "3" ]]; then
        V6=$(resolve_ip "$IN_HOST" "AF_INET6")
        [[ -n "$V6" ]] && TARGET_HOST="[$V6]" && echo -e "已解析IPv6: $V6"
    elif [[ "$NET_OPT" == "2" ]]; then
        V4=$(resolve_ip "$IN_HOST" "AF_INET")
        [[ -n "$V4" ]] && TARGET_HOST="$V4"
    fi
    
    # 构建 Agent (3X-UI 适配版)
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
        conn = sqlite3.connect(DB_PATH, timeout=10); cursor = conn.cursor()
        nid = data.get('id')
        # 3X-UI 数据库字段规范化适配
        vals = (data['remark'], data['port'], data['settings'], data['stream_settings'], data['sniffing'])
        if nid:
            cursor.execute("UPDATE inbounds SET remark=?, port=?, settings=?, stream_settings=?, sniffing=?, enable=1 WHERE id=?", vals + (nid,))
        else:
            # 补全 expiry_time, total 等字段
            cursor.execute("INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing) VALUES (1, 0, 0, 0, ?, 1, 0, '', ?, 'vless', ?, ?, 'multix', ?)", vals)
        conn.commit(); conn.close(); return True
    except Exception as e:
        print(f"DB Error: {e}"); return False

async def run():
    # 自动识别 IPv6 方括号
    target = MASTER
    if ":" in target and not target.startswith("["): target = f"[{target}]"
    uri = f"ws://{target}:8888"
    while True:
        try:
            async with websockets.connect(uri) as ws:
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
                        "xui_ver": "v2.1.2" # MHSanaei version
                    }
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats, "nodes": nodes}))
                    try:
                        msg = await asyncio.wait_for(ws.recv(), timeout=5)
                        task = json.loads(msg)
                        if task.get('action') == 'sync_node':
                            # 锁定重启 3x-ui 容器名
                            os.system("docker restart 3x-ui")
                            if sync_db(task['data']):
                                os.system("docker restart 3x-ui")
                    except: continue
        except: await asyncio.sleep(5)
asyncio.run(run())
EOF

    cd $M_ROOT/agent
    docker build -t multix-agent-v48 .
    docker rm -f multix-agent 2>/dev/null
    # 挂载 Docker Sock 核心逻辑
    docker run -d --name multix-agent --restart always --network host \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v $M_ROOT/agent/db_data:/app/db_share \
        -v $M_ROOT/agent:/app \
        multix-agent-v48
    
    echo -e "${GREEN}✅ 被控端已启动 (目标: $TARGET_HOST)${PLAIN}"
    pause_back
}

# --- [ 7. 系统运维工具箱 (回归 GitHub 原版) ] ---
sys_tools() {
    while true; do
        clear
        echo -e "${YELLOW}🧰 MultiX 系统运维工具箱 (3X-UI 适配版)${PLAIN}"
        echo "--------------------------"
        echo " 1. 开启 BBR 加速 (Chiakge)"
        echo " 2. 安装/更新 3X-UI 面板 (MHSanaei)"
        echo " 3. 申请 SSL 证书 (Acme.sh)"
        echo " 4. 重置 3X-UI 面板账号密码"
        echo " 5. 清空 3X-UI 流量统计"
        echo " 6. 开放防火墙端口"
        echo " 0. 返回主菜单"
        echo "--------------------------"
        read -p "选择: " t_opt
        case $t_opt in
            1) bash <(curl -L -s https://github.com/chiakge/Linux-NetSpeed/raw/master/tcp.sh) ;;
            2) bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) ;;
            3) curl https://get.acme.sh | sh ;;
            4) docker exec -it 3x-ui x-ui setting ;;
            5) sqlite3 $M_ROOT/agent/db_data/x-ui.db "UPDATE client_traffics SET up=0, down=0;" && echo "流量清零完成" ;;
            6) read -p "输入端口: " p; ufw allow $p/tcp 2>/dev/null; firewall-cmd --zone=public --add-port=$p/tcp --permanent 2>/dev/null; echo "端口开放完成" ;;
            0) break ;;
            *) echo "无效选择" ;;
        esac
        read -n 1 -s -r -p "按任意键继续..."
    done
    main_menu
}

# --- [ 8. 主菜单逻辑 ] ---
main_menu() {
    clear
    echo -e "${SKYBLUE}🛰️ MultiX Pro 旗舰运维系统 (V48.1 双栈修正版)${PLAIN}"
    echo "------------------------------------------------"
    echo -e "${YELLOW}核心部署:${PLAIN}"
    echo " 1. 安装/更新 主控端 (Master)"
    echo " 2. 安装/更新 被控端 (Agent)"
    echo "------------------------------------------------"
    echo -e "${YELLOW}诊断与修复:${PLAIN}"
    echo " 3. 连通性测试 (nc 探测)"
    echo " 4. 被控离线修复 (重启服务)"
    echo " 5. 深度清理模式 (彻底清除)"
    echo " 6. 环境依赖修复 (Python/Docker)"
    echo "------------------------------------------------"
    echo -e "${YELLOW}系统管理:${PLAIN}"
    echo " 7. 凭据管理中心 (修改配置)"
    echo " 8. 实时运行日志"
    echo " 9. 运维工具箱 (BBR/SSL/3XUI...)"
    echo "------------------------------------------------"
    echo " 0. 退出系统"
    
    read -p "请输入选项: " choice
    case $choice in
        1) install_master ;;
        2) install_agent ;;
        3) read -p "输入目标IP: " tip; nc -zv -w 5 $tip 8888; pause_back ;;
        4) docker restart multix-agent; pause_back ;;
        5) deep_cleanup ;;
        6) install_base; check_python_dep; check_docker; fix_dual_stack; pause_back ;;
        7) credential_center ;;
        8) journalctl -u multix-master -f || docker logs -f multix-agent --tail 50; pause_back ;;
        9) sys_tools ;;
        0) exit 0 ;;
        *) main_menu ;;
    esac
}

main_menu
