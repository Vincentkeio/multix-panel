/**
 * Hub-Next Panel Ver 1.0 (Build 202512) 核心控制引擎
 * 功能：响应式状态管理、双栈监控、演示节点自愈、节点排序下发
 */

function multix() {
    return {
        // --- [ 1. 响应式基础状态 ] ---
        lang: localStorage.getItem('m_lang') || 'zh',
        isLoggedIn: false,
        isRefreshing: false,
        showToken: false,
        showIP: false,
        searchQuery: '',
        
        // --- [ 2. 国际化语言包 (i18n) ] ---
        // Hub-Next Panel 品牌名在各语种中保持一致
        i18n: {
            zh: { 
                login: "登录", logout: "注销", guest: "访客身份", identity: "当前身份", 
                control: "管理中心", node_manage: "节点管理列表", sys: "主控机状态", 
                search: "搜索节点名称、IP或别名...", total: "总计", online: "在线",
                unlock: "解除管理限制", back: "返回访客模式", virtual: "演示节点",
                restarting: "系统正在重启，请稍后刷新页面...", sync_ok: "同步成功！系统将重启。",
                export_success: "备份导出成功！", copy_ok: "已复制到剪贴板",
                demo_notice: "演示小鸡 (请添加真实节点)"
            },
            en: { 
                login: "Login", logout: "Logout", guest: "Guest Mode", identity: "Identity Status", 
                control: "Control Center", node_manage: "Node Management", sys: "Master Status", 
                search: "Search by Name, IP or Alias...", total: "Total", online: "Online",
                unlock: "Unlock Console", back: "Back to Guest", virtual: "Demo Node",
                restarting: "System restarting, please refresh later...", sync_ok: "Success! Restarting.",
                export_success: "Backup Exported!", copy_ok: "Copied to clipboard",
                demo_notice: "Demo Instance (Add Real Nodes)"
            }
        },
        t(key) { return this.i18n[this.lang][key] || key; },
        switchLang() { 
            this.lang = this.lang === 'zh' ? 'en' : 'zh'; 
            localStorage.setItem('m_lang', this.lang); 
        },

        // --- [ 3. 核心数据容器 ] ---
        master: { cpu: 0, mem: 0, disk: 0, sys_ver: 'Loading...', sb_ver: 'N/A' },
        agents: {},
        config: { user: 'GUEST', token: '', ip4: '', port: 7575, ws_port: 9339 },
        
        // --- [ 4. 弹窗控制变量 ] ---
        showLoginModal: false,
        adminModal: false,
        showSettings: false, 
        nodeModal: false,
        subModal: false,
        
        // --- [ 5. 交互临时变量 ] ---
        loginForm: { user: '', pass: '' },
        tempUser: '', tempPass: '', tempToken: '', tempHost: '',
        tempPort: 7575, tempWsPort: 9339,
        editingSid: null, tempAlias: '', 
        subType: 'v2ray', 
        
        // --- [ 6. 生命周期钩子 ] ---
        async init() {
            const savedToken = localStorage.getItem('m_token');
            if (savedToken) {
                this.isLoggedIn = true;
                this.token = savedToken;
            }
            await this.fetchState();
            setInterval(() => this.fetchState(), 5000); 
        },

        // --- [ 7. 异步数据同步中心 ] ---
        async fetchState() {
            try {
                const res = await fetch(`/api/state?v=${Date.now()}`);
                if (!res.ok) throw new Error("Offline");
                const data = await res.json();
                
                this.master = data.master || this.master;
                this.agents = data.agents || {};
                this.config = data.config || this.config;
                
                if (this.isLoggedIn && !this.tempUser) {
                    this.initAdminForm();
                }
            } catch (e) { 
                console.error("Hub-Next Sync Error:", e); 
            } finally { 
                this.isRefreshing = false; 
            }
        },

        initAdminForm() {
            this.tempUser = this.config.user;
            this.tempToken = this.config.token;
            this.tempHost = this.config.ip4;
            this.tempPort = this.config.port;
            this.tempWsPort = this.config.ws_port;
            this.tempPass = ""; 
        },

        // --- [ 8. 演示节点自动注入逻辑 ] ---
        get allAgents() {
            const list = this.agents || {};
            // 如果节点数量为 0，自动生成持久化风格的演示节点
            if (Object.keys(list).length === 0) {
                return {
                    "virtual-demo-001": {
                        hostname: "Hub-Next-DEMO",
                        alias: this.t('demo_notice'),
                        order: 1,
                        status: "online",
                        is_demo: true,
                        metrics: { cpu: 12, mem: 24, load: "0.15", net_out: "0B/s", net_in: "0B/s", latency: "28" }
                    }
                };
            }
            return list;
        },

        // --- [ 9. 排序与搜索逻辑 ] ---
        get sortedAgents() {
            return Object.fromEntries(
                Object.entries(this.allAgents).sort(([, a], [, b]) => (a.order || 999) - (b.order || 999))
            );
        },

        get filteredAgents() {
            const q = this.searchQuery.toLowerCase();
            const filtered = Object.entries(this.allAgents).filter(([sid, a]) => {
                const matchSearch = (a.alias || "").toLowerCase().includes(q) || 
                                   a.hostname.toLowerCase().includes(q) || 
                                   sid.includes(q);
                return matchSearch && !a.hidden;
            });
            return Object.fromEntries(filtered.sort(([, a], [, b]) => (a.order || 999) - (b.order || 999)));
        },

        // --- [ 10. 物理配置同步逻辑 ] ---
        async confirmUpdateAdmin() {
            const msg = this.lang === 'zh' 
                ? "确认同步新配置？Hub-Next Panel 将物理重启服务。" 
                : "Sync new config? Hub-Next Panel will restart.";
            
            if(!confirm(msg)) return;

            const payload = {
                user: this.tempUser,
                pass: this.tempPass || "", 
                token: this.tempToken,
                host: this.tempHost,
                port: parseInt(this.tempPort) || 7575,
                ws_port: parseInt(this.tempWsPort) || 9339
            };

            try {
                const res = await fetch('/api/update_admin', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json', 'Authorization': this.token },
                    body: JSON.stringify(payload)
                });
                
                if (res.ok) {
                    alert(this.t('sync_ok'));
                    localStorage.removeItem('m_token');
                    const newUrl = `${window.location.protocol}//${payload.host}:${payload.port}`;
                    setTimeout(() => { window.location.href = newUrl; }, 1500);
                }
            } catch (e) {
                alert(this.t('restarting'));
                setTimeout(() => { window.location.reload(); }, 5000);
            }
        },

        // --- [ 11. 节点管理：增删、隐藏、排序 ] ---
        async manageAgent(sid, action, value = null) {
            try {
                const res = await fetch('/api/manage_agent', {
                    method: 'POST',
                    headers: { 
                        'Content-Type': 'application/json', 
                        'Authorization': this.token 
                    },
                    body: JSON.stringify({ sid, action, value })
                });
                if (res.ok) await this.fetchState();
            } catch (e) { console.error("Operation Failed"); }
        },

        // --- [ 12. 鉴权与辅助工具 ] ---
        exportGlobalNodes() {
            const backup = { brand: "Hub-Next", version: "1.0", agents: this.agents };
            const dataStr = "data:text/json;charset=utf-8," + encodeURIComponent(JSON.stringify(backup, null, 4));
            const dlAnchorElem = document.createElement('a');
            dlAnchorElem.setAttribute("href", dataStr);
            dlAnchorElem.setAttribute("download", `Hub-Next_Backup_${new Date().getTime()}.json`);
            dlAnchorElem.click();
            alert(this.t('export_success'));
        },

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
                    window.location.reload(); 
                } else { alert("Login Failed"); }
            } catch (e) { alert("Connect Error"); }
        },

        logout() {
            if (confirm(this.t('logout') + "?")) {
                localStorage.removeItem('m_token');
                window.location.reload();
            }
        },

        copyToClipboard(text) {
            navigator.clipboard.writeText(text).then(() => alert(this.t('copy_ok')));
        },
        
        generateSubLink() {
            return `${window.location.origin}/sub?token=${this.config.token}&type=${this.subType}`;
        }
    }
}
