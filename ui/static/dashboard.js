/**
 * Multiy Pro 旗舰版核心逻辑控制中心 - 深度增强版
 */
function multix() {
    return {
        // --- [ 1. 基础响应式状态 ] ---
        isLoggedIn: false,
        isRefreshing: false,
        showToken: false, 
        searchQuery: '',
        
        // --- [ 2. 数据容器 ] ---
        master: { cpu: 0, mem: 0, disk: 0, sys_ver: '加载中...', sb_ver: 'N/A' },
        agents: {},
        config: { user: '', token: '', ip4: '', web_port: 7575 },
        
        // --- [ 3. 弹窗控制变量 ] ---
        showLoginModal: false,
        adminModal: false,
        nodeModal: false,
        subModal: false,
        globalExportModal: false,
        
        // --- [ 4. 表单与交互临时变量 ] ---
        loginForm: { user: '', pass: '' },
        tempUser: '', tempPass: '', tempToken: '', 
        editingSid: null, tempAlias: '', 
        subType: 'v2ray', 
        globalLinks: '',
        
        // --- [ 5. 节点详情变量 ] ---
        currentNode: null,
        currentNodeInbounds: [],
        editingInbound: null,

        // --- [ 6. 初始化 ] ---
        init() {
            const savedToken = localStorage.getItem('m_token');
            if (savedToken) {
                this.isLoggedIn = true;
                this.fetchState();
            }
            setInterval(() => this.fetchState(), 5000); // 5秒高频心跳
        },

        // --- [ 7. 核心数据同步 ] ---
        async fetchState() {
            try {
                const res = await fetch('/api/state');
                if (!res.ok) throw new Error("Backend Offline");
                const data = await res.json();
                
                this.master = data.master;
                this.agents = data.agents;
                this.config = data.config;
                
                if (this.isLoggedIn && !this.tempUser) {
                    this.tempUser = this.config.user;
                    this.tempToken = this.config.token;
                }
            } catch (e) { 
                console.error("同步失败:", e); 
            } finally { 
                this.isRefreshing = false; 
            }
        },

        // --- [ 8. 节点管理逻辑 - 核心重构 ] ---
        
        // 原始排序逻辑
        get sortedAgents() {
            return Object.fromEntries(
                Object.entries(this.agents).sort(([, a], [, b]) => (a.order || 999) - (b.order || 999))
            );
        },

        // 旗舰版：计算属性 - 过滤、隐藏感知与虚拟补全
        get filteredAgents() {
            let list = Object.entries(this.agents);
            
            // A. 如果没有任何真实节点，生成虚拟小鸡占位符
            if (list.length === 0) {
                return {
                    "virtual-001": {
                        hostname: "PRO-NODE-DEMO",
                        alias: "待接入演示节点",
                        is_demo: true, 
                        order: 1,
                        status: "online",
                        metrics: { cpu: 12, mem: 24, load: "0.15", net_out: "0B/s", net_in: "0B/s", latency: "28" }
                    }
                };
            }

            // B. 搜索过滤逻辑
            const q = this.searchQuery.toLowerCase();
            let filtered = list.filter(([sid, a]) => {
                const matchSearch = (a.alias && a.alias.toLowerCase().includes(q)) || 
                                    a.hostname.toLowerCase().includes(q) || 
                                    sid.includes(q);
                
                // 访客模式下强制隐藏 hidden 节点；管理员模式下在管理面板显示，主页网格依然隐藏以保持视图整洁
                return matchSearch && !a.hidden;
            });

            return Object.fromEntries(filtered.sort(([, a], [, b]) => (a.order || 999) - (b.order || 999)));
        },

        // 管理面板专用：显示所有节点（含隐藏节点）以便管理
        get adminNodeList() {
            return this.sortedAgents;
        },

        async manageAgent(sid, action, value = null) {
            try {
                const res = await fetch('/api/manage_agent', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json', 'Authorization': this.config.token },
                    body: JSON.stringify({ sid, action, value })
                });
                if (res.ok) await this.fetchState();
            } catch (e) { alert("操作失败"); }
        },

        async saveAlias(sid) {
            await this.manageAgent(sid, 'alias', this.tempAlias);
            this.editingSid = null;
        },

        // --- [ 9. 超级订阅与导出 ] ---
        generateSubLink() {
            return `http://${window.location.host}/sub?token=${this.config.token}&type=${this.subType}`;
        },

        async exportGlobalNodes() {
            this.globalLinks = "";
            let count = 0;
            Object.values(this.agents).forEach(agent => {
                if (agent.hidden) return;
                const ip = agent.ip || this.config.ip4;
                (agent.metrics?.inbounds || []).forEach(inb => {
                    if (inb.type === 'vless') {
                        this.globalLinks += `vless://${inb.uuid}@${ip}:${inb.listen_port || inb.port}?security=reality&sni=${inb.reality_dest?.split(':')[0] || 'yahoo.com'}&fp=chrome&pbk=${inb.reality_pub || ''}&sid=${inb.short_id || ''}&type=tcp&flow=xtls-rprx-vision#${inb.tag}\n`;
                        count++;
                    }
                });
            });
            if (count === 0) return alert("无可导出的 VLESS 节点");
            this.globalExportModal = true;
            setTimeout(() => this.renderQR(this.globalLinks), 150);
        },

        renderQR(text) {
            const container = document.getElementById('global-qr-code');
            if (container) {
                container.innerHTML = "";
                new QRCode(container, { text, width: 200, height: 200, colorDark: "#000000", colorLight: "#ffffff" });
            }
        },

        copyToClipboard(text) {
            navigator.clipboard.writeText(text).then(() => alert("已复制到剪贴板"));
        },

        // --- [ 10. 认证管理 ] ---
        async login() {
            if (!this.loginForm.user || !this.loginForm.pass) return;
            try {
                const res = await fetch('/api/login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(this.loginForm)
                });
                const data = await res.json();
                if (res.ok && data.status === "success") {
                    localStorage.setItem('m_token', data.token);
                    this.isLoggedIn = true;
                    this.showLoginModal = false;
                    await this.fetchState();
                } else { alert("凭据错误"); }
            } catch (e) { alert("服务器连接超时"); }
        },

        logout() {
            if (confirm("确定注销？")) {
                localStorage.removeItem('m_token');
                window.location.reload();
            }
        }
    }
}
