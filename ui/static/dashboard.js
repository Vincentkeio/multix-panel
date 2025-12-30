/**
 * MULTIX PRO - 核心前端逻辑 V165.0
 * 重点：前后端分离架构、隐私订阅转换、多协议 3X-UI 适配、自定义 JSON 模式
 */
function multix() {
    return {
        // --- [ 1. 状态变量 ] ---
        agents: {},
        config: { user: 'ADMIN', token: '', ip4: location.hostname },
        isLoggedIn: false,
        showLoginModal: false,
        nodeModal: false,
        subModal: false,
        globalExportModal: false,
        
        // --- [ 2. 交互与编辑变量 ] ---
        currentNode: null,
        currentNodeInbounds: [],
        editingInbound: null,
        editingIdx: -1,
        subType: 'v2ray',
        globalLinks: '',
        editingSid: null,
        tempAlias: '',

        // --- [ 3. 初始化 ] ---
        async init() {
            const t = localStorage.getItem('multiy_token');
            if (t) { this.isLoggedIn = true; this.config.token = t; }
            await this.fetchState();
            // 3秒高频同步，确保监控与隐藏状态实时
            setInterval(() => this.fetchState(), 3000);
        },

        // --- [ 4. 数据同步 ] ---
        async fetchState() {
            try {
                const r = await fetch('/api/state');
                if (!r.ok) throw new Error("Offline");
                const d = await r.json();
                this.agents = d.agents || {};
                this.config.user = d.config.user;
                // 弹窗打开时，同步刷新背景数据
                if (this.nodeModal && this.currentNode) {
                    const latest = this.agents[this.currentNode.sid];
                    if (latest) this.currentNode = latest;
                }
            } catch (e) { console.error("Sync Error"); }
        },

        // --- [ 5. 节点管理核心：3X-UI 逻辑 ] ---
        
        // 打开配置弹窗并克隆当前节点配置
        openNodeModal(agent) {
            if (!this.isLoggedIn) return;
            this.currentNode = agent;
            // 深拷贝已有 inbounds，实现“草稿”机制
            this.currentNodeInbounds = JSON.parse(JSON.stringify(agent.metrics?.inbounds || []));
            this.editingInbound = null;
            this.nodeModal = true;
        },

        // 新增节点：初始化默认 VLESS + Reality 模板
        async addNewDraft() {
            this.editingIdx = -1;
            this.editingInbound = {
                type: 'vless',
                tag: 'Node_' + Math.floor(Math.random() * 1000),
                listen_port: 443,
                uuid: crypto.randomUUID(),
                reality_priv: '获取中...',
                reality_pub: '',
                reality_dest: 'yahoo.com:443',
                short_id: Math.random().toString(16).substring(2, 10),
                email: 'admin@multix.pro',
                raw_json: '' // 为自定义 JSON 模式准备
            };
            
            // 自动从后端获取 X25519 密钥对
            try {
                const r = await fetch('/api/gen_keys');
                const d = await r.json();
                this.editingInbound.reality_priv = d.private_key;
                this.editingInbound.reality_pub = d.public_key;
            } catch (e) { this.editingInbound.reality_priv = ''; }
        },

        // 编辑现有节点
        editInbound(idx) {
            this.editingIdx = idx;
            const target = this.currentNodeInbounds[idx];
            // 识别是否为 UI 适配协议，否则进入 JSON 模式
            const uiProtocols = ['vless', 'vmess', 'hysteria2', 'shadowsocks'];
            if (uiProtocols.includes(target.type)) {
                this.editingInbound = JSON.parse(JSON.stringify(target));
            } else {
                this.editingInbound = { 
                    type: 'json', 
                    tag: target.tag, 
                    raw_json: JSON.stringify(target, null, 2) 
                };
            }
        },

        // 保存当前编辑的节点到列表（本地草稿）
        saveInboundDraft() {
            let finalData;
            if (this.editingInbound.type === 'json') {
                try {
                    finalData = JSON.parse(this.editingInbound.raw_json);
                    if (!finalData.tag) finalData.tag = this.editingInbound.tag;
                } catch (e) { return alert("JSON 语法错误，请检查格式！"); }
            } else {
                finalData = { ...this.editingInbound };
            }

            if (this.editingIdx === -1) {
                this.currentNodeInbounds.push(finalData);
            } else {
                this.currentNodeInbounds[this.editingIdx] = finalData;
            }
            this.editingInbound = null;
        },

        // 删除单个节点（本地草稿）
        deleteInbound(idx) {
            if (confirm("确定要移除此节点吗？")) {
                this.currentNodeInbounds.splice(idx, 1);
            }
        },

        // 同步所有 Inbounds 到 Agent（JSON 透传模式）
        async syncConfigToAgent() {
            if (!this.currentNode) return;
            try {
                const res = await fetch('/api/update_node_config', {
                    method: 'POST',
                    headers: { 
                        'Content-Type': 'application/json',
                        'Authorization': this.config.token 
                    },
                    body: JSON.stringify({
                        sid: this.currentNode.sid,
                        inbounds: this.currentNodeInbounds
                    })
                });
                const data = await res.json();
                if (data.res === 'ok') {
                    alert("✅ 配置已下发！Agent 正在重启服务...");
                    this.nodeModal = false;
                    await this.fetchState();
                }
            } catch (e) { alert("通讯失败，请检查主控连接"); }
        },

        // --- [ 6. 隐私分享与订阅逻辑 ] ---

        // 生成受 Token 保护的超级订阅链接
        generateSubLink() {
            return `${location.protocol}//${location.host}/sub?token=${this.config.token}&type=${this.subType}`;
        },

        // 超级导出：汇总所有小鸡节点（隐私处理：仅显示 Tag）
        async exportGlobalNodes() {
            let links = [];
            Object.values(this.agents).forEach(agent => {
                if (agent.hidden) return; // 隐藏的小鸡不参与全局导出
                const ip = agent.ip || location.hostname;
                const inbounds = agent.metrics?.inbounds || [];
                
                inbounds.forEach(inb => {
                    if (inb.type === 'vless') {
                        const pbk = inb.reality_pub || '';
                        const sni = inb.reality_dest?.split(':')[0] || 'yahoo.com';
                        // 隐私构造：只保留节点 Tag
                        links.push(`vless://${inb.uuid}@${ip}:${inb.listen_port}?security=reality&sni=${sni}&fp=chrome&pbk=${pbk}&sid=${inb.short_id || ''}&type=tcp&flow=xtls-rprx-vision#${encodeURIComponent(inb.tag)}`);
                    }
                });
            });

            if (links.length === 0) return alert("当前没有可导出的生效节点");
            this.globalLinks = links.join('\n');
            this.globalExportModal = true;

            // 渲染全量二维码
            this.$nextTick(() => {
                const canvas = document.getElementById('global-qr-canvas');
                if (canvas) QRCode.toCanvas(canvas, this.globalLinks, { width: 180, margin: 2 });
            });
        },

        // --- [ 7. 辅助功能与 Agent 管理 ] ---
        async manageAgent(sid, action, value = null) {
            try {
                const res = await fetch('/api/manage_agent', {
                    method: 'POST',
                    headers: { 
                        'Content-Type': 'application/json',
                        'Authorization': this.config.token 
                    },
                    body: JSON.stringify({ sid, action, value })
                });
                if (res.ok) {
                    if (action === 'delete') delete this.agents[sid];
                    await this.fetchState();
                }
            } catch (e) { console.error("Action Error"); }
        },

        startEditAlias(sid, name) { this.editingSid = sid; this.tempAlias = name; },
        async saveAlias(sid) { await this.manageAgent(sid, 'alias', this.tempAlias); this.editingSid = null; },
        formatSpeed(b) {
            if (!b) return '0 B/s';
            if (b > 1048576) return (b / 1048576).toFixed(1) + ' MB/s';
            return (b / 1024).toFixed(1) + ' KB/s';
        },
        copyToClipboard(text) {
            navigator.clipboard.writeText(text).then(() => alert("已复制到剪贴板"));
        },
        logout() { localStorage.removeItem('multiy_token'); location.reload(); },

        get sortedAgents() {
            return Object.fromEntries(
                Object.entries(this.agents).sort(([,a], [,b]) => (a.order || 0) - (b.order || 0))
            );
        }
    }
}
