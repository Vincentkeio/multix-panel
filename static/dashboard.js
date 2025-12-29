
function multix() {
    return {
        // --- 状态变量 ---
        agents: {}, master: {}, config: {}, 
        drawer: false, adminModal: false, isRefreshing: false,
        isLoggedIn: false, showLoginModal: false,
        curSid: '', curNode: {}, editNodes: [],
        isEditingUser: false, isEditingPass: false, editingSid: null,
        tempUser: '', tempPass: '', tempAlias: '',
        loginUser: '', loginPass: '',

        // --- 初始化 ---
        async init() {
            // 从浏览器缓存检查登录态
            this.isLoggedIn = !!localStorage.getItem('multiy_token');
            await this.fetchState();
            setInterval(() => this.fetchState(), 3000);
        },

        // --- 核心同步 (针对 IPv6 优化) ---
        async fetchState() {
            try {
                const r = await fetch('/api/state');
                const d = await r.json();
                this.agents = d.agents || {};
                this.master = d.master || {};
                this.config = d.config || {};
                if(this.drawer && this.curSid) this.curNode = this.agents[this.curSid];
            } catch(e) { console.error("IPv6/V4 链接异常:", e); }
            finally { this.isRefreshing = false; }
        },

        // --- 管理员权限功能 ---
        openAdminModal() {
            this.tempUser = this.config.user;
            this.tempPass = '';
            this.adminModal = true;
        },
        async confirmUpdateAdmin() {
            const res = await fetch('/api/update_admin', {
                method: 'POST', headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({ user: this.tempUser, pass: this.tempPass || null })
            });
            if(res.ok) { this.isEditingUser = false; await this.fetchState(); alert("配置已安全持久化"); }
        },
        async saveAlias(sid) {
            await this.manageAgent(sid, 'rename', this.tempAlias);
            this.editingSid = null; await this.fetchState();
        },
        get sortedAgents() {
            return Object.fromEntries(Object.entries(this.agents).sort(([,a], [,b]) => (a.order || 0) - (b.order || 0)));
        },
        
        // --- 节点操作 (卡片触发) ---
        openDrawer(sid) {
            this.curSid = sid;
            this.curNode = this.agents[sid];
            this.editNodes = JSON.parse(JSON.stringify(this.curNode.draft_nodes || this.curNode.physical_nodes || []));
            this.drawer = true;
        },
        logout() { if(confirm("退出并清理登录凭证？")) { localStorage.removeItem('multiy_token'); window.location.reload(); } }
        // ... 其他 addVirtualNode, manageAgent, saveDraft, syncPush 保持原逻辑
    }
}
