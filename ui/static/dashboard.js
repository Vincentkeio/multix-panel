/**
 * Hub-Next Panel Ver 1.0 (Build 202512) 核心控制引擎
 * 深度修复版：IPv4/v6 分权、物理演示鸡自愈、管理员上帝视角、跨域剪贴板
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
        
        // --- [ 2. 国际化语言包 ] ---
        i18n: {
            zh: { 
                login: "登录", logout: "注销", guest: "访客身份", identity: "当前身份", 
                control: "管理中心", node_manage: "节点管理列表", sys: "主控机状态", 
                search: "搜索节点名称、IP或别名...", total: "总计", online: "在线",
                unlock: "解除管理限制", back: "返回访客模式", virtual: "演示节点",
                restarting: "系统正在重启，请稍后刷新页面...", sync_ok: "同步成功！系统将重启。",
                export_success: "备份导出成功！", copy_ok: "已复制到剪贴板",
                demo_notice: "演示小鸡 (自动生成)"
            },
            en: { 
                login: "Login", logout: "Logout", guest: "Guest Mode", identity: "Identity Status", 
                control: "Control Center", node_manage: "Node Management", sys: "Master Status", 
                search: "Search by Name, IP or Alias...", total: "Total", online: "Online",
                unlock: "Unlock Console", back: "Back to Guest", virtual: "Demo Node",
                restarting: "System restarting, please refresh later...", sync_ok: "Success! Restarting.",
                export_success: "Backup Exported!", copy_ok: "Copied to clipboard",
                demo_notice: "Demo Instance (Auto-Generated)"
            }
        },
        t(key) { return this.i18n[this.lang][key] || key; },
        switchLang() { 
            this.lang = this.lang === 'zh' ? 'en' : 'zh'; 
            localStorage.setItem('m_lang', this.lang); 
        },

        // --- [ 3. 核心数据容器 ] ---
        master: { cpu: 0, mem: 0, disk: 0, sys_ver: '', sb_ver: '', ip4: false, ip6: false },
        agents: {},
        config: { user: 'GUEST', token: '', ip4: '', port: 7575, ws_port: 9339 },
        
        // --- [ 4. 弹窗控制变量 ] ---
        showLoginModal: false,
        adminModal: false,
        showSettings: false, 
        nodeModal: false,
        subModal: false,
        isAddingDemo: false, // 防止演示鸡重复写入锁
        
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

        // --- [ 8. 管理中心凭据自愈 ] ---
        toggleSettings() {
            this.showSettings = !this.showSettings;
            if (this.showSettings) {
                this.initAdminForm(); // 唤起时强制同步最新配置
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

        // --- [ 9. 演示节点物理持久化自愈逻辑 ] ---
        get sortedAgents() {
            let list = Object.entries(this.agents || {});
            
            // 检查可见节点数量
            const visibleNodes = list.filter(([_, a]) => !a.hidden);
            
            // 如果无可显示节点，发起物理添加演示节点请求
            if (visibleNodes.length === 0 && !this.isAddingDemo) {
                this.isAddingDemo = true;
                const demoId = 'virtual-' + Math.random().toString(36).substr(2, 7);
                this.manageAgent(demoId, 'add_virtual', { 
                    alias: this.t('demo_notice'), 
                    order: 1 
                }).then(() => { this.isAddingDemo = false; });
            }

            // 权限过滤：管理员看所有，访客只看非隐藏
            return list.filter(([_, a]) => {
                if (this.isLoggedIn) return true;
                return !a.hidden;
            }).sort(([, a], [, b]) => (a.order || 999) - (b.order || 999));
        },

        // --- [ 10. 主页搜索与过滤 ] ---
        get filteredAgents() {
            const q = this.searchQuery.toLowerCase();
            const allPossible = this.sortedAgents; // 依赖 sortedAgents 的权限过滤结果
            
            const filtered = allPossible.filter(([sid, a]) => {
                const match = (a.alias || "").toLowerCase().includes(q) || 
                              a.hostname.toLowerCase().includes(q) || 
                              sid.includes(q);
                return match;
            });
            return Object.fromEntries(filtered);
        },

        // --- [ 11. 节点与物理配置管理 ] ---
        async manageAgent(sid, action, value = null) {
            try {
                const res = await fetch('/api/manage_agent', {
                    method: 'POST',
                    headers: { 
                        'Content-Type': 'application/json', 
                        'Authorization': this.token || ''
                    },
                    body: JSON.stringify({ sid, action, value })
                });
                if (res.ok) await this.fetchState();
            } catch (e) { console.error("Operation Failed"); }
        },

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

        // --- [ 12. 复制逻辑增强版：兼容非 HTTPS ] ---
        copyToClipboard(text) {
            if (navigator.clipboard && window.isSecureContext) {
                navigator.clipboard.writeText(text).then(() => {
                    alert(this.t('copy_ok'));
                }).catch(() => {
                    this.fallbackCopy(text);
                });
            } else {
                this.fallbackCopy(text);
            }
        },

        fallbackCopy(text) {
            const textArea = document.createElement("textarea");
            textArea.value = text;
            textArea.style.position = "fixed"; // 避免页面跳动
            document.body.appendChild(textArea);
            textArea.focus();
            textArea.select();
            try {
                const successful = document.execCommand('copy');
                if (successful) alert(this.t('copy_ok'));
            } catch (err) {
                alert('Copy Failed');
            }
            document.body.removeChild(textArea);
        },

        // --- [ 13. 其他鉴权逻辑 ] ---
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
        
        generateSubLink() {
            return `${window.location.origin}/sub?token=${this.config.token}&type=${this.subType}`;
        }
    }
}
