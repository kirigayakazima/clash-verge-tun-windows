# Windows 上 Clash Verge Rev TUN 开启后断网：排查与恢复

这份记录来自一次 Windows 电脑的实际排查。现象是：Clash Verge Rev 的**系统代理可用**，切换到 **TUN（虚拟网卡）**后，国内外网页都报连接关闭；关闭 TUN 又恢复。排查时发现，电脑同时运行 O+ Connect、存在 `vgate0` 虚拟网卡，物理网卡的 IPv4 转发已开启。

本次让 TUN 恢复的组合是：为 Mihomo 指定真实出口网卡、关闭自动选择出口，并**临时**关闭该物理网卡的 IPv4 转发。两项同时调整后网络恢复，因此尚不能证明其中任何一项单独就是唯一原因。不同电脑应先诊断，不要照搬网卡名称。

## 先理解三个设置

- **系统代理**只影响会使用 Windows 代理设置的程序。
- **TUN**先接管网络连接，再按 Clash 规则选择 `DIRECT` 或代理节点。TUN 并不自动意味着每条连接都走代理；但如果你的最后一条 `MATCH` 规则指向代理组，未匹配流量会走该组。本案例当前是 `rule` 模式，`GEOIP,CN` 指向“国内网站”策略组；只有该组实际选中 `DIRECT` 时，匹配它的连接才会直连。域名规则、广告拦截规则等也可能先于 `GEOIP,CN` 命中。
- **IPv4 转发**是 Windows 网卡替其他接口转送数据包的能力。关闭物理网卡的转发不会关闭这张网卡的 IPv4 上网，但可能影响网络共享或设备互联软件。

## 快速流程

以下命令均在本项目根目录运行（先 `cd clash-verge-tun-windows`）。

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
