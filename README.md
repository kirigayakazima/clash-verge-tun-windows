# Windows 上 Clash Verge Rev TUN 开启后断网：排查与恢复

这份记录来自一次 Windows 电脑的实际排查。现象是：Clash Verge Rev 的**系统代理可用**，切换到 **TUN（虚拟网卡）**后，国内外网页都报连接关闭；关闭 TUN 又恢复。排查时发现，电脑同时运行 O+ Connect、存在 `vgate0` 虚拟网卡，物理网卡的 IPv4 转发已开启。

本次让 TUN 恢复的组合是：为 Mihomo 指定真实出口网卡、关闭自动选择出口，并**临时**关闭该物理网卡的 IPv4 转发。两项同时调整后网络恢复，因此尚不能证明其中任何一项单独就是唯一原因。不同电脑应先诊断，不要照搬网卡名称。

## 先理解三个设置

- **系统代理**只影响会使用 Windows 代理设置的程序。
- **TUN**先接管网络连接，再按 Clash 规则选择 `DIRECT` 或代理节点。TUN 并不自动意味着每条连接都走代理；但如果你的最后一条 `MATCH` 规则指向代理组，未匹配流量会走该组。本案例当前是 `rule` 模式，`GEOIP,CN` 指向“国内网站”策略组；只有该组实际选中 `DIRECT` 时，匹配它的连接才会直连。域名规则、广告拦截规则等也可能先于 `GEOIP,CN` 命中。
- **IPv4 转发**是 Windows 网卡替其他接口转送数据包的能力。关闭物理网卡的转发不会关闭这张网卡的 IPv4 上网，但可能影响网络共享或设备互联软件。

## 快速流程

**推荐：双击项目根目录的 `启动修复.cmd`。**
现已全面升级为**纯自动免交互模式**：双击并在 Windows 权限提示中允许后，脚本将自动根据度量值识别最优物理出口（如以太网）、关闭 IPv4 转发、自动在后台重启 TUN 虚拟网卡（**无需手动关 TUN 再开 TUN**），3 秒后自动完成并关闭窗口。

若希望开机完全无感、不再手动双击任何脚本，可**直接双击 `安装开机自愈任务.cmd`**（或在管理员 PowerShell 中运行 `.\scripts\Install-StartupTask.ps1`）：
```powershell
.\scripts\Install-StartupTask.ps1
```
该任务将在系统启动（AtStartup，最优先执行，早于用户应用）及用户登录（AtLogon，二次兜底）时以 SYSTEM 权限后台静默执行自愈，彻底压制 O+ Connect 重新开启转发。如需卸载，可双击 `卸载开机自愈任务.cmd` 或运行 `.\scripts\Uninstall-StartupTask.ps1`。

也可在 PowerShell 运行 `./Start-TunRepair.ps1` 进入交互式菜单：
- `1`：⚡ 一键全自动自愈 (自动选网卡 + 关转发 + 热重载 TUN，无需手动操作)。
- `2`：查看网卡、路由与 Clash 详细诊断结果。
- `3`：手动选择特定网卡关闭转发。
- `4`：读取本地备份恢复原转发值。
- `5`：运行国内外多维度连通性测试。
- `6`：安装 Windows 开机静默自愈任务。
- `7`：卸载 Windows 开机自愈任务。
- `0`：退出。

以下是手动分步流程，命令均在本项目根目录运行（先 `cd clash-verge-tun-windows`）。

1. **先保持 TUN 关闭、系统代理可用。** 在 PowerShell 运行只读诊断：

   ```powershell
   .\scripts\Get-TunStatus.ps1
   ```

2. 确认当前真实出口网卡。诊断会列出 IPv4 默认路由和各网卡状态。本案例使用 `以太网`；如果你的电脑实际上用 Wi-Fi，就应使用自己的 WLAN 名称。

3. 在 Clash Verge Rev 的 **设置 → 虚拟网卡模式右侧齿轮**中，关闭**自动选择流量出口接口**，保存。此时仍不要打开 TUN。不要把“虚拟网卡名称”改成物理网卡名称；它指的是 Mihomo 创建的虚拟网卡。

4. 在 **订阅 → 右键当前订阅 → 扩展覆写配置**中加入下面一行，并把 `以太网` 换成第 2 步确认的名称。不要覆盖已有内容，也不要直接改自动生成的 `clash-verge.yaml`。

   ```yaml
   interface-name: 以太网
   ```

5. 如果诊断显示真实出口网卡的 `Forwarding` 为 `Enabled`，可用管理员 PowerShell 做一次**临时、可恢复**的测试。脚本会记录原值到本地 `state/`，并只改 `ActiveStore`：

   ```powershell
   .\scripts\Set-Forwarding.ps1 -Action Disable -InterfaceAlias "以太网"
   .\scripts\Get-TunStatus.ps1
   ```

   如果 O+ Connect 仍在运行，它可能把转发重新打开。先确认输出确实为 `Disabled`。不要删除 `vgate0` 或卸载 O+ Connect 来做这一步。

6. 开启 TUN，分别测试一个普通网站和一个需要代理的网站。也可运行：

   ```powershell
   .\scripts\Test-Connectivity.ps1
   ```

   若网络再次中断，立即在 Clash Verge Rev 关闭 TUN，切回系统代理。然后运行诊断，记录 `Forwarding` 是否被重新开启。不要在全网断开时反复切换设置。

7. 不再使用 TUN 测试时，可先关闭 TUN，再用脚本恢复原来的转发值：

   ```powershell
   .\scripts\Set-Forwarding.ps1 -Action Restore -InterfaceAlias "以太网"
   ```

   如果转发是你在使用本项目脚本之前手动关闭的，本项目没有它的备份；请先确认原值，再手动恢复。本案例原值是 `Enabled`。

## 常见分支问题：国内流媒体/B站“首页能开但视频黑屏打不开”

### 症状
TUN 模式已恢复，网页和桌面端能正常加载 B 站首页、UP主头像、评论和标题，但点进具体视频后播放器区域黑屏，并显示小电视图标“你感兴趣的视频都在B站”加载失败。

### 根因
- B 站业务接口走 `*.bilibili.com`，被直连规则放行；
- 但底层的音视频切片流走独立 CDN `*.bilivideo.com`、`*.bilivideo.cn`，属于 `🇨🇳 国内网站` 策略组；
- 若在 Clash Verge Rev 的“代理”面板中误将 `🇨🇳 国内网站` 切换成了代理节点（如日本节点），国内视频 CDN 对海外节点会产生丢包、超时或阻断，导致播放器拉不到切片报错。

### 快速排查与解决
1. 运行 `.\scripts\Get-TunStatus.ps1`，脚本会检查生成规则是否仍引用 `🇨🇳 国内网站`；若仍有引用，再提示订阅记录中该组是否偏离 `DIRECT`。若已用扩展脚本固定规则，则不再仅凭组内选择报警；
2. 也可运行 `.\scripts\Test-Connectivity.ps1` 查看 CDN 是否有 HTTP 响应；即使返回 `403`，也只能说明服务器有响应，不能证明视频可播放或连接走了直连；
3. 打开 Clash Verge Rev 的 **“代理”** 页面，找到 **`🇨🇳 国内网站`** 策略组，切换回 **`DIRECT`**；
4. 强制刷新网页（`Ctrl + F5`）或在桌面端重新点击视频即可恢复。

### 用本地扩展脚本固定国内规则直连

若希望原本指向 `🇨🇳 国内网站` 策略组的规则始终直连，可以用本地脚本将这些规则的出口改成 `DIRECT`，避免组内选择变化影响它们。此方法保留原有规则顺序，不会把国内规则提到广告拦截或其他特例规则之前。

1. 打开 **订阅 → 右键当前订阅 → 扩展脚本**。
2. 如果当前只是默认的 `return config` 空脚本，用下面的完整代码替换；如果已有自定义逻辑，把其中的 `config.rules = ...` 处理合并到已有 `main` 的 `return config` 前，不要覆盖原逻辑。

   ```javascript
   function main(config) {
     config.rules = (config.rules || []).map(rule =>
       typeof rule === "string"
         ? rule.replace(
             /,\s*🇨🇳 国内网站\s*(?=,\s*no-resolve\s*$|$)/,
             ",DIRECT"
           )
         : rule
     );
     return config;
   }
   ```

3. 保存并重新启用当前订阅，确认生成配置中的对应规则由 `GEOIP,CN,🇨🇳 国内网站` 变为 `GEOIP,CN,DIRECT`，其他原先指向该组的域名规则也应变为 `DIRECT`。
4. 保留原先在 **扩展覆写配置** 中设置的 `interface-name: 以太网`。固定出口网卡与规则分流是两项设置。

可直接复制的独立示例见 [examples/domestic-direct.js](examples/domestic-direct.js)。本地订阅扩展会在配置生成时应用；更新同一订阅时仍可使用。新建或切换到其他订阅需要为那个订阅另行配置。若策略组名称不同，需同步修改脚本中的名称。

脚本只修改原本指向该组的规则，不保证所有国内站点都能被已有规则识别。组内仍显示代理节点时，也不一定意味着这些规则在走代理，应以生成规则和实际连接记录为准。回退时撤销这段处理并重新启用订阅，再在代理页面选择所需出口。

## 常见分支问题：TUN 模式下节点全部 Timeout、网络卡顿，切回系统代理恢复

### 症状
开启 TUN 模式后，Clash Verge 面板中**所有代理节点测速全部显示 Timeout（超时报红）**，访问国内外网页均极其卡顿或无法连接；但一旦切回“系统代理模式”，所有节点测速立刻恢复成正常的几毫秒至几十毫秒，网络恢复。

### 根因
1. **O+ Connect 后台静默重开转发**：虽然此前通过脚本关闭了物理网卡的 IPv4 转发，但 O+ Connect 后台服务（`O+Connect Service`）在设备心跳、重连或休眠唤醒时，会以 SYSTEM 权限重新将物理网卡的 IPv4 `Forwarding` 设为 `Enabled`；
2. **`mixed` 堆栈发生路由死循环**：在默认的 `stack: mixed` 模式下，Mihomo 尝试直连代理节点服务器的握手包，被 Windows 的 IP 转发机制重新抓回了 TUN / `vgate0` 虚拟网卡中，触发 `reject loopback connection` 回环阻断，导致内核根本无法连通任何代理服务器；
3. **切回系统代理恢复的原因**：系统代理模式彻底卸载了 TUN 虚拟网卡及其接管的 `0.0.0.0/1` 路由，内核直接通过普通 Socket 与远端节点通信，绕过了虚拟网卡回环。

### 根治与防护
1. **彻底免疫方案（推荐）**：
   在 Clash Verge Rev 的 **设置 → 虚拟网卡模式（TUN）右侧齿轮** 中，将 **堆栈模式（Stack）** 从默认的 `mixed` 改为 **`gvisor`**。
   * **原理**：`gvisor` 是 Google 开发的用户态网络协议栈，在应用内存中自闭环拼装数据包，不依赖 Windows 内核底层转发逻辑，即使物理网卡开启转发也不会被卷入回环死锁。
2. **应急恢复**：
   以管理员身份在 PowerShell 运行脚本重新关闭物理网卡转发：
   ```powershell
   .\scripts\Set-Forwarding.ps1 -Action Disable -InterfaceAlias "以太网"
   ```
3. **减少干扰**：
   长时间使用 TUN 时建议退出 O+ Connect 客户端，并关闭 Wi-Fi 避免与以太网争抢默认路由。

## 诊断边界

- 若 TUN 模式仍全网断开，不能仅凭浏览器的 `ERR_CONNECTION_CLOSED` 判断是 DNS、路由、自回环还是防火墙。应检查 Clash 核心日志中是否出现 `reject loopback connection`、`interface not found` 或 DNS 解析错误。
- 本案例在 TUN 恢复后重新登录 STOVE，首页已显示《卡厄斯梦境》，因此本机的游戏展示问题也得到解决。若其他电脑仍提示地区限制，需要另查该请求的**实际出口**和账号／商品展示资格；这个结果不能保证所有账号的风控或地区展示相同。
- O+ Connect 可能在重启或重新启动服务后再次开启 IPv4 转发。再次出现故障时先运行诊断脚本，不要直接重复修改。

## 相关资料

- [Mihomo TUN 配置与自动选择出口说明](https://wiki.metacubex.one/en/config/inbound/tun/)
- [Mihomo `interface-name` 出口网卡字段](https://wiki.metacubex.one/en/config/general/#outbound-interface)
- [Clash Verge Rev 扩展覆写配置与设置优先级](https://www.clashverge.dev/guide/extend.html)
- [Clash Verge Rev：O+ Connect、IPv4 转发与 TUN 回环的实测报告](https://github.com/clash-verge-rev/clash-verge-rev/issues/8117)
- [Mihomo：`vgate0` 被误选为出口的案例](https://github.com/MetaCubeX/mihomo/issues/3122)

详细复盘见 [docs/incident-2026-10-31.md](docs/incident-2026-10-31.md)。
