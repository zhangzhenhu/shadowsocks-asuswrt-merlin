# Shadowsocks for Asuswrt-Merlin New Gen


shadowsocks-asuswrt-merlin will install `shadowsocks-libev` and `v2ray-plugin` on your Asuswrt-Merlin New Gen(version 382.xx and higher) based router, tested on NETGEAR R7000 and ASUS RT-AC86U.

For server side set up, you can easily install shadowsocks server and v2ray-plugin with docker by [https://github.com/Acris/docker-shadowsocks-libev](https://github.com/Acris/docker-shadowsocks-libev).

## 变更说明

关键词： xbox,华硕,代理,clash,加速,xbox加速

本项目基于 ``Shadowsocks for Asuswrt-Merlin New Gen`` 修改而来。

### 背景说明

最近 ``xbox`` 总抽风，所以想着给他加个代理，但是 ``xbox`` 本身不支持配置代理，只能想办法在路由器上加一个透明代理。
但是如果把 ``xbox`` 全部请求都走代理，游戏下载速度会超级慢。
参考学习了 ``xbox`` 下载助手（https://github.com/skydevil88/XboxDownload/blob/master/README_OpenWrt.md）
的知识，部分游戏下载链接可以利用302跳转到国内站，其它 ``xbox`` 地址的走代理。
这样就两全其美了，但是要实现起来比较麻烦。

我的路由器是华硕 AX86U 路由器，Armv8 架构，并且刷了原版梅林（merlin）固件，因为不太信任国内团队搞得改版梅林，所以还是用的原版梅林。
原版梅林安装插件就比较麻烦了，找了很久后选中了 ``Shadowsocks for Asuswrt-Merlin New Gen`` 这个项目。

学习资料：

https://blog.gmem.cc/iptables


### 思路

但这个项目也有一点不足，就是它用的 ``Shadowsocks ss-redir`` 做透明代理服务，
使用 ``ss-redir`` 会有几个不足：

1. ``ss-redir`` 只能传入一个代理地址，不能传入多个并自己选择最优的。
2. ``ss-redir`` 只能提供透明代理，不能同时提供 http 代理和 sockets 代理，这很不方便，不能很好的和 ``lighttpd`` 做配合。
   ``lighttpd`` 需要依赖一个 http 代理，之后会讲到为什么需要 ``lighttpd`` 。

鉴于以上，想把 ``ss-redir`` 替换成功能更强大的 ``clash``。


整理一下需求：

1. 能对部分 ``xbox`` 下载链接进行302跳转。
2. 把 ``ss-redir`` 替换成功能更强大的 ``clash``。


我们的主要需求是对部分 ``xbox`` 下载链接进行302跳转，
然而，无论 ``ss-redir`` 还是 ``clash`` 都不能做 302 跳转。
所以又找到 ``lighttpd``,利用 ``lighttpd`` 做302跳转。

但并不是 ``xbox`` 的全部链接都要 302 跳转，
那些不需要跳转的的链接还得转发到代理才行，
``lighttpd`` 有个插件可以转发流量到代理服务，
但这个插件只支持 ``http`` 代理，因此还得需要一个 ``http`` 代理服务，
这时就体现出 ``clash`` 功能丰富了，``clash``
可以同时提供 透明代理、sockets代理、http代理，
因此最好用 ``clash`` 替换掉 ``ss-redir``。


大概的方案：

1. 路由器利用 ``dnsmasq`` 进行 dns 解析，并且自动写相应的 ``ipset`` 。为什么要用 ``dnsmasq`` 下面会讲。
2. 利用 ``iptables`` 进行流量分流
  1. 需要 302 跳转的 ``xbox`` 下载链接所属域名流量，直接转发到 ``lighttpd``。
  2. 需要走透明代理的的流量，转发到 ``clash``。
  3. 其它的直连。

3. 需要 302 跳转的域名流量被转到 ``lighttpd``， ``lighttpd`` 根据正则规则进行 302 跳转。
   命中跳转规则的直接返回 302 给 ``xbox`` 了 ，没有命中的，转发给 ``clash`` 提供的 ``http`` 代理服务。
4. 


### dnsmasq
 
我们知道， ``clash`` 也可以分流，但是  ``clash`` 是分走代理还是直连，不能分流给 ``lighttpd``。
所以我们还得选择用 ``iptables`` 进行分流。

``iptables`` 分流只能按照 ip 分流，不能按照域名分流，但 ``iptables`` 可以和 ``ipset`` 配合使用，
利用 ``ipset`` 进行 ip 地址的匹配，非常适合对批量ip地址进行匹配分流。

这时就体现出 ``dnsmasq`` 的价值了，``dnsmasq`` 可以通过配置实现，不同域名走不同的上游 dns 服务进行查询，
并写入到指定的 ``ipset`` 集合里。

利用 ``dnsmasq`` 的这个特性可以实现对域名进行分流：

1. 需要直连的域名，``dnsmasq`` 走国内dns 查询服务即可，并把解析到的 ip 地址写入到 ``ipset`` 白名单里。
2. 需要302跳转的域名，``dnsmasq`` 走国际dns（或者 ``clash`` 提供的dns服务） 查询服务即可，并把解析到的 ip 地址写入到 ``ipset`` 302 名单里。
3. 需要代理的域名，``dnsmasq`` 走 国际dns（或者 ``clash`` 提供的dns服务） 查询服务即可，并把解析到的 ip 地址写入到 ``ipset`` 代理名单里。

然后配置 ``iptables`` 规则，实现不同 ``ipset`` 名单转发到对应的服务即可。


``Shadowsocks for Asuswrt-Merlin New Gen``  项目本身也是这样做的，
我们只需要稍加修改，加入需要 302跳转 的分组即可。

1. 在 ``rules/`` 目录下，增加一个名为 ``user_302_redirect.txt`` 文件，里面写入需要 302 跳转的 ``xbox`` 下载域名

  ```txt
  assets1.xboxlive.com
  assets2.xboxlive.com
  d1.xboxlive.com
  d2.xboxlive.com
  xvcf1.xboxlive.com
  xvcf2.xboxlive.com
  dlassets.xboxlive.com
  dlassets2.xboxlive.com
  ```

2. 修改 ``bin/ss-merlin`` 文件，加入对 ``user_302_redirect.txt``  处理

```sh
    # 需要跳转到 lighttpd 的域名
    user_domain_name_302list=${SS_MERLIN_HOME}/rules/user_302_redirect.txt

    if [[ -f ${user_domain_name_302list} ]]; then
      for i in $(cat ${user_domain_name_302list} | grep -v '^#'); do
        # 写到 user-gfwlist-domains.conf 这个文件， 就不用再创建新的文件了
        # 注意，这里的作用是，告知 dnsmasq ，此名单里的域名解析得到的 ip 加入到名字为 user302list 的 ipset 集合 
        # 在 iptables 规则里会把这个集合里的数据包强制转发发到 lighttpd 服务
        echo "ipset=/${i}/user302list" >> ${DNSMASQ_CONFIG_DIR}/user-gfwlist-domains.conf
        # 为避免这部分域名被 dns 污染，可以指定这部分域名使用安全的 dns 解析
        # 这里 ${safe_dns_ip} 是一个安全的、国外的 dns服务，这里我用的 clash 提供的dns服务
        # 变量 ${safe_dns_ip} 的配置在文件 etc/ss-merlin.conf 里面
        echo "server=/${i}/${safe_dns_ip}" >>${DNSMASQ_CONFIG_DIR}/user-gfwlist-domains.conf
      done
    fi
```


### lighttpd 的安装与配置

部分站点跳转到 lighttpd ，然后由 lighttpd 进行302跳转

```sh
opkg update
opkg upgrade
opkg install  wget-ssl lighttpd
```
安装完成后，默认 `lighttpd` 的配置文件在目录 `/opt/etc/lighttpd/` ，

`lighttpd` 服务的启动停止操作脚本是

```sh
 /opt/etc/init.d/S80lighttpd

```

配置文件修改

302 跳转规则修改，在文件 `/opt/etc/lighttpd/conf.d/10-redirect.conf` 增加一下内容

```
server.modules += ( "mod_redirect" )
$HTTP["host"] =~ "^(assets1|assets2|d1|d2|xvcf1|xvcf2)\.xboxlive\.com$" {
    url.redirect = ( "(.*)" => "http://assets1.xboxlive.cn$1" )
}
$HTTP["host"] =~ "^(dlassets|dlassets2)\.xboxlive\.com$" {
    url.redirect = ( "(.*)" => "http://dlassets.xboxlive.cn$1" )
}

```

在文件 `/opt/etc/lighttpd/conf.d/30-proxy.conf` 增加以下内容，
这里 ``7890`` 是 ``clash`` 的 http 代理服务端口。

```
server.modules += ( "mod_proxy" )
proxy.server = ( "" => (( "host" => "127.0.0.1", "port" => 7890    )))

```

### clash 的安装与配置

clash 的默认安装目录在 ``${SS_MERLIN_HOME}/clash`` ,
你需要把 clash 的配置文件放到这个目录下。

如果你想更换 clash 的配置文件位置，你需要手动改一下文件 ``bin/S90clash``。


需要改动文件:

1. ``bin/S90clash``
2.  ``scripts/start_all_services.sh.sh``
3.  ``scripts/stop_all_services.sh``


### iptables 规则配置

直接看文件 ``scripts/apply_iptables_rule.sh``

我去掉了对 路由器 本身流量进行透明代理的功能，
首先，这个功能没有太完美的处理方式，经常容易出错，造成困扰。
其次，感觉这个就是伪需求，路由器本身流量没必要增加透明代理，基本上不需要到路由器上干啥。
即使需要，手动通过环境变量（http_proxy,https_proxy,all_proxy）设置一下代理即可。



## Getting Started

### Prerequisites
- Asuswrt-Merlin New Gen(version 382.xx and higher) based router
- Entware **must** be installed, you can find installation documents on [https://github.com/RMerl/asuswrt-merlin/wiki/Entware](https://github.com/RMerl/asuswrt-merlin/wiki/Entware)
- JFFS partition should be enabled
- ca-certificates should be installed for HTTPS support
- git and git-http should be installed
- wget-ssl should be installed

Make sure you have installed all prerequisites software and utils, you can install it by:
```sh
opkg update
opkg upgrade
opkg install ca-certificates git-http wget-ssl
```

### Installation
shadowsocks-asuswrt-merlin is installed by running the following commands in your terminal:
```sh
sh -c "$(wget https://cdn.jsdelivr.net/gh/Acris/shadowsocks-asuswrt-merlin@master/tools/install.sh -O -)"
```

### Configuration
#### Configure shadowsocks
The sample shadowsocks configuration file location is: `/opt/share/ss-merlin/etc/shadowsocks/config.sample.json`, ensure `local_address` is set to `0.0.0.0`.

We highly recommend to enable `v2ray-plugin` on your server side. You can set up your server in several command with: [https://github.com/Acris/docker-shadowsocks-libev](https://github.com/Acris/docker-shadowsocks-libev).

If you want to enable UDP support, you should set `mode` from `tcp_only` to `tcp_and_udp`.

For configuration file documents, you can go to: [https://github.com/shadowsocks/shadowsocks-libev/blob/master/doc/shadowsocks-libev.asciidoc#config-file](https://github.com/shadowsocks/shadowsocks-libev/blob/master/doc/shadowsocks-libev.asciidoc#config-file)
```sh
# Copy and edit the shadowsocks configuration file
cd /opt/share/ss-merlin/etc/shadowsocks
cp config.sample.json config.json
vi config.json
```

#### Configure shadowsocks-asuswrt-merlin
The sample shadowsocks-asuswrt-merlin configuration file location is: `/opt/share/ss-merlin/etc/ss-merlin.sample.conf`. Currently, shadowsocks-asuswrt-merlin support three mode:
- 0: GFW list.
- 1: Bypass mainland China.
- 2: Global mode.

You can also enable or disable UDP support to change `udp=0` or `udp=1`, ensure your server side support UDP and set `"mode": "tcp_and_udp"` in shadowsocks configuration file.
```sh
# Copy and edit the shadowsocks-asuswrt-merlin configuration file
cd /opt/share/ss-merlin/etc
cp ss-merlin.sample.conf ss-merlin.conf
vi ss-merlin.conf
```

Configure which LAN IP will pass transparent proxy by edit `lan_ips`, you can assign a LAN IP like 192.169.1.125 means only this device can pass transparent proxy.

And you can change the default DNS server for Chinese IPs by modifying `china_dns_ip`.

Then, start the service:
```sh
# Start the service
ss-merlin start
```

### Usage
```sh
admin@R7000:/tmp/home/root# ss-merlin 
 Usage: ss-merlin start|stop|restart|status|upgrade|uninstall
```

### Custom user rules
```
# Block domain
## Add domain to this file if you want to block it.
vi /opt/share/ss-merlin/rules/user_domain_name_blocklist.txt

# Force pass proxy
## You can add domain to this file if you want to force the domain pass proxy.
vi /opt/share/ss-merlin/rules/user_domain_name_gfwlist.txt

# Domain whitelist
## You can add domain to this file if you need the domain bypass proxy.
vi /opt/share/ss-merlin/rules/user_domain_name_whitelist.txt

# IP whitelist
## You can add IP address to this file if you need the IP bypass proxy.
vi /opt/share/ss-merlin/rules/user_ip_whitelist.txt

# IP gfwlist
## You can add IP address to this file if you want to force the IP pass proxy.
vi /opt/share/ss-merlin/rules/user_ip_gfwlist.txt

# Then, restart the service
ss-merlin restart
```

## Credits
Thanks for the following awesome projects ❤️
- [shadowsocks-libev](https://github.com/shadowsocks/shadowsocks-libev)
- [v2ray-plugin](https://github.com/shadowsocks/v2ray-plugin)
- [asuswrt-merlin.ng](https://github.com/RMerl/asuswrt-merlin.ng)
- [Entware](https://github.com/Entware/Entware)
- [asuswrt-merlin-transparent-proxy](https://github.com/zw963/asuswrt-merlin-transparent-proxy)
- [unbound](https://nlnetlabs.nl/projects/unbound/about/)
- [dnsmasq-china-list](https://github.com/felixonmars/dnsmasq-china-list)
- [gfwlist](https://github.com/gfwlist/gfwlist)
- [gfwlist2dnsmasq](https://github.com/cokebar/gfwlist2dnsmasq)
- [ss-tproxy](https://github.com/zfl9/ss-tproxy)
- [oh-my-zsh](https://github.com/ohmyzsh/ohmyzsh)
- And much more.

## Thanks
<a href="https://jb.gg/OpenSource?from=shadowsocks-asuswrt-merlin">
  <img alt="JetBrains" src="https://www.jetbrains.com/company/brand/img/jetbrains_logo.png" width="100">
</a>

## License
```
The MIT License (MIT)

Copyright (c) 2016 Billy Zheng

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```
