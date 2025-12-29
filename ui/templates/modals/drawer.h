<div x-show="drawer" x-cloak class="fixed inset-0 z-50 flex justify-end">
    <div x-show="drawer" x-transition.opacity class="absolute inset-0 bg-black/80 backdrop-blur-sm" @click="drawer=false"></div>
    <div x-show="drawer" x-transition:enter="transition ease-out duration-300" x-transition:enter-start="translate-x-full" x-transition:enter-end="translate-x-0" 
         class="relative w-full max-w-xl bg-[#020617] h-full border-l border-white/10 p-8 flex flex-col shadow-2xl">
        <div class="flex justify-between items-center mb-8">
            <div>
                <h2 class="text-2xl font-black uppercase tracking-tighter italic">节点配置管理</h2>
                <p class="text-[10px] text-blue-500 font-mono" x-text="curNode.alias || curNode.hostname"></p>
            </div>
            <button @click="drawer=false" class="text-2xl text-slate-500 hover:text-white"><i class="ri-close-fill"></i></button>
        </div>
        <div class="flex-1 overflow-y-auto space-y-6 pr-2 custom-scrollbar">
            <template x-for="(node, idx) in editNodes" :key="idx">
                <div class="glass p-5 rounded-3xl border-l-4 border-blue-600 relative transition-all">
                    <div class="flex justify-between items-center mb-4">
                        <input x-model="node.tag" class="bg-transparent text-sm font-black outline-none border-b border-white/10 focus:border-blue-500 w-2/3 text-white">
                        <button @click="editNodes.splice(idx, 1)" class="text-slate-600 hover:text-red-500 transition"><i class="ri-delete-bin-line"></i></button>
                    </div>
                    <div class="grid grid-cols-2 gap-4">
                        <div class="space-y-1">
                            <label class="text-[9px] font-bold text-slate-500 uppercase italic">协议</label>
                            <select x-model="node.type" class="w-full bg-black/50 border border-white/10 rounded-xl p-2.5 text-xs outline-none text-white">
                                <option value="vless">VLESS</option><option value="hysteria2">Hysteria2</option><option value="shadowsocks">Shadowsocks</option>
                            </select>
                        </div>
                        <div class="space-y-1">
                            <label class="text-[9px] font-bold text-slate-500 uppercase italic">端口</label>
                            <input type="number" x-model="node.listen_port" class="w-full bg-black/50 border border-white/10 rounded-xl p-2.5 text-xs font-mono text-white">
                        </div>
                    </div>
                    <div class="mt-4 pt-4 border-t border-white/5 space-y-3">
                        <template x-if="node.type === 'vless'">
                            <div class="animate-fadeIn">
                                <label class="text-[9px] font-bold text-slate-500 uppercase flex justify-between">UUID <span @click="node.uuid = crypto.randomUUID()" class="text-blue-500 cursor-pointer text-[8px]">随机生成</span></label>
                                <input x-model="node.uuid" class="w-full bg-black/50 border border-white/10 rounded-xl p-2.5 text-[10px] font-mono mt-1 text-white">
                            </div>
                        </template>
                        <template x-if="node.type === 'hysteria2'">
                            <div class="grid grid-cols-2 gap-3">
                                <div class="col-span-2"><label class="text-[9px] font-bold text-slate-500 uppercase italic">认证密码</label><input x-model="node.password" class="w-full bg-black/50 border border-white/10 rounded-xl p-2.5 text-xs mt-1 text-white"></div>
                                <div><label class="text-[9px] font-bold text-slate-500 uppercase italic text-[8px]">上行Mbps</label><input type="number" x-model="node.up_mbps" class="w-full bg-black/50 border border-white/10 rounded-xl p-2.5 text-xs text-white"></div>
                                <div><label class="text-[9px] font-bold text-slate-500 uppercase italic text-[8px]">下行Mbps</label><input type="number" x-model="node.down_mbps" class="w-full bg-black/50 border border-white/10 rounded-xl p-2.5 text-xs text-white"></div>
                            </div>
                        </template>
                    </div>
                </div>
            </template>
            <button @click="addEmptyNode()" class="w-full py-4 border-2 border-dashed border-white/5 rounded-2xl text-slate-500 hover:border-blue-500 font-black text-[10px] uppercase">新增配置</button>
        </div>
        <div class="mt-8 grid grid-cols-2 gap-4">
            <button @click="saveDraft()" class="py-4 rounded-xl bg-white/5 text-[10px] font-black uppercase">暂存草稿</button>
            <button @click="syncPush()" class="py-4 rounded-xl bg-blue-600 text-[10px] font-black uppercase shadow-lg shadow-blue-600/30">即时同步</button>
        </div>
    </div>
</div>
