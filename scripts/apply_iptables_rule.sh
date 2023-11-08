#!/bin/ash

SS_MERLIN_HOME=/opt/share/ss-merlin
DNSMASQ_CONFIG_DIR=${SS_MERLIN_HOME}/etc/dnsmasq.d

if [[ ! -f ${SS_MERLIN_HOME}/etc/ss-merlin.conf ]]; then
  cp ${SS_MERLIN_HOME}/etc/ss-merlin.sample.conf ${SS_MERLIN_HOME}/etc/ss-merlin.conf
fi
if [[ ! -f ${SS_MERLIN_HOME}/etc/shadowsocks/config.json ]]; then
  cp ${SS_MERLIN_HOME}/etc/shadowsocks/config.sample.json ${SS_MERLIN_HOME}/etc/shadowsocks/config.json
fi
. ${SS_MERLIN_HOME}/etc/ss-merlin.conf

get_lan_ips() {
  lan_ipaddr=$(nvram get lan_ipaddr)
  lan_netmask=$(nvram get lan_netmask)
  # Assumes there's no "255." after a non-255 byte in the mask
  local x=${lan_netmask##*255.}
  set -- 0^^^128^192^224^240^248^252^254^ $(( (${#lan_netmask} - ${#x})*2 )) "${x%%.*}"
  x=${1%%$3*}
  cidr=$(($2 + (${#x}/4)))
  echo "${lan_ipaddr%.*}".0/$cidr
}

modprobe ip_set
modprobe ip_set_hash_net
modprobe ip_set_hash_ip
modprobe xt_set

# Create ipset for user domain name whitelist and user domain name gfwlist
ipset create userwhitelist hash:net 2>/dev/null
ipset create usergfwlist hash:net 2>/dev/null


if [[ ${mode} -eq 0 ]]; then
  # Add GFW list to gfwlist ipset for GFW list mode
  if ipset create gfwlist hash:ip 2>/dev/null; then
    if [[ -s ${DNSMASQ_CONFIG_DIR}/dnsmasq_gfwlist_ipset.conf.bak ]]; then
      rm -f ${DNSMASQ_CONFIG_DIR}/dnsmasq_gfwlist_ipset.conf 2>/dev/null
      cp ${DNSMASQ_CONFIG_DIR}/dnsmasq_gfwlist_ipset.conf.bak ${DNSMASQ_CONFIG_DIR}/dnsmasq_gfwlist_ipset.conf
    fi
  fi
elif [[ ${mode} -eq 1 ]]; then
  # Add China IP to chinaips ipset for Bypass mainland China mode
  if ipset create chinaips hash:net 2>/dev/null; then
    OLDIFS="$IFS" && IFS=$'\n'
    if ipset list chinaips &>/dev/null; then
      count=$(ipset list chinaips | wc -l)
      if [[ "$count" -lt "8000" ]]; then
        echo "Applying China ipset rule, it maybe take several minute to finish..."
        if [[ -s ${SS_MERLIN_HOME}/rules/chinadns_chnroute.txt.bak ]]; then
          rm -f ${SS_MERLIN_HOME}/rules/chinadns_chnroute.txt 2>/dev/null
          cp ${SS_MERLIN_HOME}/rules/chinadns_chnroute.txt.bak ${SS_MERLIN_HOME}/rules/chinadns_chnroute.txt
        fi
        for ip in $(cat ${SS_MERLIN_HOME}/rules/chinadns_chnroute.txt | grep -v '^#'); do
          ipset add chinaips ${ip}
        done
      fi
    fi
    IFS=${OLDIFS}
  fi
fi

# Add intranet IP to localips ipset for Bypass LAN
if ipset create localips hash:net 2>/dev/null; then
  OLDIFS="$IFS" && IFS=$'\n'
  if ipset list localips &>/dev/null; then
    echo "Applying localips ipset rule..."
    for ip in $(cat ${SS_MERLIN_HOME}/rules/localips | grep -v '^#'); do
      ipset add localips ${ip}
    done
  fi
  IFS=${OLDIFS}
fi

# Add whitelist
if ipset create whitelist hash:ip 2>/dev/null; then
  if [[ ! ${china_dns_ip} ]]; then
    china_dns_ip=119.29.29.29
  fi
  remote_server_address=$(cat ${SS_MERLIN_HOME}/etc/shadowsocks/config.json | grep 'server"' | cut -d ':' -f 2 | cut -d '"' -f 2)
  remote_server_ip=${remote_server_address}
  ISIP=$(echo ${remote_server_address} | grep -E '([0-9]{1,3}[\.]){3}[0-9]{1,3}|:')
  if [[ -z "$ISIP" ]]; then
    echo "Resolving server IP address with DNS ${china_dns_ip}..."
    remote_server_ip=$(nslookup ${remote_server_address} ${china_dns_ip} | sed '1,4d' | awk '{print $3}' | grep -v : | awk 'NR==1{print}')
    echo "Server IP address is ${remote_server_ip}"
  fi

  OLDIFS="$IFS" && IFS=$'\n'
  if ipset list whitelist &>/dev/null; then
    # Add China default DNS server
    ipset add whitelist ${china_dns_ip}
    # Add shadowsocks server ip address
    ipset add whitelist ${remote_server_ip}
    # Add rubyfush DNS server
    ipset add whitelist 118.89.110.78
    ipset add whitelist 47.96.179.163
  fi
  IFS=${OLDIFS}
fi

# Add user_ip_whitelist.txt
if [[ -e ${SS_MERLIN_HOME}/rules/user_ip_whitelist.txt ]]; then
  for ip in $(cat ${SS_MERLIN_HOME}/rules/user_ip_whitelist.txt | grep -v '^#'); do
    ipset add userwhitelist ${ip} 2>/dev/null
  done
fi

# Add user_ip_gfwlist.txt
if [[ -e ${SS_MERLIN_HOME}/rules/user_ip_gfwlist.txt ]]; then
  for ip in $(cat ${SS_MERLIN_HOME}/rules/user_ip_gfwlist.txt | grep -v '^#'); do
    ipset add usergfwlist ${ip} 2>/dev/null
  done
fi




local_redir_port=$(cat ${SS_MERLIN_HOME}/etc/shadowsocks/config.json | grep 'local_port' | cut -d ':' -f 2 | grep -o '[0-9]*')

if [[ ! ${lan_ips} || ${lan_ips} == '0.0.0.0/0' ]]; then
  lan_ips=$(get_lan_ips)
fi
echo "LAN IPs are ${lan_ips}"




if iptables -t nat -N SHADOWSOCKS_TCP 2>/dev/null; then
  # TCP rules
  iptables -t nat -N SS_OUTPUT
  iptables -t nat -N SS_PREROUTING
  iptables -t nat -A OUTPUT -j SS_OUTPUT
  iptables -t nat -A PREROUTING -j SS_PREROUTING
  iptables -t nat -A SHADOWSOCKS_TCP -p tcp -m set --match-set localips dst -j RETURN
  iptables -t nat -A SHADOWSOCKS_TCP -p tcp -m set --match-set whitelist dst -j RETURN
  iptables -t nat -A SHADOWSOCKS_TCP -p tcp -m set --match-set userwhitelist dst -j RETURN
  if [[ ${mode} -eq 1 ]]; then
    iptables -t nat -A SHADOWSOCKS_TCP -p tcp -m set --match-set chinaips dst -j RETURN
  fi
  if [[ ${mode} -eq 0 ]]; then
    iptables -t nat -A SHADOWSOCKS_TCP -p tcp -s ${lan_ips} -m set --match-set gfwlist dst -j REDIRECT --to-ports ${local_redir_port}
  else
    iptables -t nat -A SHADOWSOCKS_TCP -p tcp -s ${lan_ips} -j REDIRECT --to-ports ${local_redir_port}
  fi
  iptables -t nat -A SHADOWSOCKS_TCP -p tcp -s ${lan_ips} -m set --match-set usergfwlist dst -j REDIRECT --to-ports ${local_redir_port}
  # Apply TCP rules
  iptables -t nat -A SS_OUTPUT -p tcp -j SHADOWSOCKS_TCP
  iptables -t nat -A SS_PREROUTING -p tcp -s ${lan_ips} -j SHADOWSOCKS_TCP
fi




if [[ ${udp} -eq 1 ]]; then
  if iptables -t mangle -N SHADOWSOCKS_UDP 2>/dev/null; then
    # UDP rules
    modprobe xt_TPROXY
    ip route add local 0.0.0.0/0 dev lo table 100
    ip rule add fwmark 0x2333 table 100
    iptables -t mangle -N SS_OUTPUT
    iptables -t mangle -N SS_PREROUTING
    iptables -t mangle -A OUTPUT -j SS_OUTPUT
    iptables -t mangle -A PREROUTING -j SS_PREROUTING
    iptables -t mangle -A SHADOWSOCKS_UDP -p udp -m set --match-set localips dst -j RETURN
    iptables -t mangle -A SHADOWSOCKS_UDP -p udp -m set --match-set whitelist dst -j RETURN
    iptables -t mangle -A SHADOWSOCKS_UDP -p udp -m set --match-set userwhitelist dst -j RETURN
    if [[ ${mode} -eq 1 ]]; then
      iptables -t mangle -A SHADOWSOCKS_UDP -p udp -m set --match-set chinaips dst -j RETURN
    fi
    if [[ ${mode} -eq 0 ]]; then
      iptables -t mangle -A SHADOWSOCKS_UDP -p udp -s ${lan_ips} -m set --match-set gfwlist dst -j MARK --set-mark 0x2333
    else
      iptables -t mangle -A SHADOWSOCKS_UDP -p udp -s ${lan_ips} -j MARK --set-mark 0x2333
    fi
    iptables -t mangle -A SHADOWSOCKS_UDP -p udp -s ${lan_ips} -m set --match-set usergfwlist dst -j MARK --set-mark 0x2333
    # Apply for udp
    iptables -t mangle -A SS_OUTPUT -p udp -j SHADOWSOCKS_UDP
    iptables -t mangle -A SS_PREROUTING -p udp -s ${lan_ips} --dport 53 -m mark ! --mark 0x2333 -j ACCEPT
    iptables -t mangle -A SS_PREROUTING -p udp -s ${lan_ips} -m mark ! --mark 0x2333 -j SHADOWSOCKS_UDP
    iptables -t mangle -A SS_PREROUTING -p udp -s ${lan_ips} -m mark --mark 0x2333 -j TPROXY --on-ip 127.0.0.1 --on-port ${local_redir_port}
  fi
fi

# 总感觉上面 OUTPUT 链的处理有问题，
# OUTPUT 链也去走规则，那本身代理服务出去的数据包由被代理回来的了？陷入死循环了?
# 没看出是怎么处理 代理服务（SHADOWSOCKS） 本身发出的数据包不被重定向回来的。
# 找到处理方法了：
#     # Add shadowsocks server ip address
#    # ipset add whitelist ${remote_server_ip}
# 上面的代码，把 shadowsocks 远端服务的 ip 加入到 白名单了。
# iptables 的规则里 whitelist 的数据包会被跳过。
# 但是这种方法在用clash 时可能存在问题
# 1. clash 里可以同时配置多个代理服务端，需要都加入白名单，
# 2. clash 本身也可以分流，clash分流成直连的，目标地址就没有加入白名单，这时就出问题了。
# 一个不完美的解决方法，iptables 这里不要启用全局模式，而是要黑名单模式，只有命中黑名单的才进行拦截和转发。
# 这样就能避免 clash 自己发出的流量被拦截

# 学习资料：
# 1.  https://blog.gmem.cc/iptables

# 疑问1 ：-j TPROXY --tproxy-mark 0x2333   和   -j MARK --set-mark  这两中mark 方式，都是mark的同一个位置么？  
#        都能被 ` ip rule add fwmark 0x2333 table 100`  里面的fwmark 识别出来么？

# 解答： 基本已经确定 --tproxy-mark  可以被  ip rule add fwmark 识别。 证明： https://www.kernel.org/doc/Documentation/networking/tproxy.txt


# 疑问2： ip route add local 0.0.0.0/0 dev lo table 2333 会不会导致数据包又进入 PREROUTING 链

# 解答： 尚未找到明确的说明。但猜测应该不会，否则修陷入死循环了，route 后应该是进入 INPUT 链。 





#####################################
# 清除原来添加的规则
#####################################
# 清除前面的 udp 代理规则
iptables -t mangle -D OUTPUT -j SS_OUTPUT 2>/dev/null
iptables -t mangle -D PREROUTING -j SS_PREROUTING 2>/dev/null

iptables -t mangle -F SS_OUTPUT 2>/dev/null
iptables -t mangle -X SS_OUTPUT 2>/dev/null
iptables -t mangle -F SS_PREROUTING 2>/dev/null
iptables -t mangle -X SS_PREROUTING 2>/dev/null
iptables -t mangle -F SHADOWSOCKS_UDP 2>/dev/null
iptables -t mangle -X SHADOWSOCKS_UDP 2>/dev/null

# 清除前面的 tcp 代理规则

iptables -t nat -D OUTPUT -j SS_OUTPUT 2>/dev/null
iptables -t nat -D PREROUTING -j SS_PREROUTING 2>/dev/null
iptables -t nat -F SS_OUTPUT 2>/dev/null
iptables -t nat -X SS_OUTPUT 2>/dev/null
iptables -t nat -F SS_PREROUTING 2>/dev/null
iptables -t nat -X SS_PREROUTING 2>/dev/null
iptables -t nat -F SHADOWSOCKS_TCP
iptables -t nat -X SHADOWSOCKS_TCP

#####################################
# 重新添加规则
#####################################


# 在 merlin 固件上，要使用 TPROXY ，必须手动开启 xt_TPROXY 功能，没有这个不行。
modprobe xt_TPROXY

# 判断一下，如果已经添加过路由表了，就不再添加
if [[ -z "$(ip rule list |grep '0x2333')" ]]; then
  # modprobe xt_TPROXY
  # 将封包通过lo (local，本机回环地址)发出。 注意出口为lo的封包不会真正路由，而是交给本地进程处理
  # 疑问点？这里会不会在重新回到 PREROUTING ？？？？ 目前没找到明确说明，但应该不会。
  ip route add local 0.0.0.0/0 dev lo table 100
  # 表示被标记为 0x2333 的的数据包的走向要查表  100
  ip rule add fwmark 0x2333 table 100
fi


# 添加规则之前，先清除一下。避免重复添加。
iptables -t mangle -N TPROXY_TCP 2>/dev/null
iptables -t mangle -F TPROXY_TCP 2>/dev/null
  

  iptables -t mangle -A TPROXY_TCP -p tcp -m set --match-set localips dst -j RETURN
  iptables -t mangle -A TPROXY_TCP -p tcp -m set --match-set whitelist dst -j RETURN
  iptables -t mangle -A TPROXY_TCP -p tcp -m set --match-set userwhitelist dst -j RETURN
  iptables -t mangle -A TPROXY_TCP -p tcp -m set --match-set user302list dst -j RETURN
  
  if [[ ${mode} -eq 1 ]]; then
    # 白名单，目的地址是白名单里的 **不** 进行拦截
    iptables -t mangle -A TPROXY_TCP -p tcp -m set --match-set chinaips dst -j RETURN
  fi
  if [[ ${mode} -eq 0 ]]; then
    # 黑名单模式，目的地址是黑名单里的才进行拦截，
    iptables -t mangle -A TPROXY_TCP -p tcp -s ${lan_ips} -m set --match-set gfwlist dst -j TPROXY  --on-port ${local_tproxy_port} --tproxy-mark 0x2333
  else
    # 全局模式，所有流量都拦截并打上标记，转发到 clash 
    iptables -t mangle -A TPROXY_TCP -p tcp -s ${lan_ips} -j TPROXY  -on-port ${local_tproxy_port} --tproxy-mark 0x2333
  fi
  # 用户手动添加的黑名单，不管哪个模式都进行拦截
  iptables -t mangle -A TPROXY_TCP -p tcp -s ${lan_ips} -m set --match-set usergfwlist dst -j TPROXY  --on-port ${local_tproxy_port}  --tproxy-mark 0x2333

  # Apply TCP rules
  iptables -t mangle -A PREROUTING  -p tcp -s ${lan_ips} -j TPROXY_TCP

# 应用 302 跳转的规则
# 创建一个针对 302 的ipset， dnsmasq 负责把ip写入这个 set
ipset create user302list hash:net 2>/dev/null
# iptables -t nat -N USER302  
# iptables -t nat -A PREROUTING  -p tcp  -j USER302
# 需要 302 的转给 lighttpd_port
# iptables -t nat -A USER302 -p tcp -s ${lan_ips} -m set --match-set user302list dst -j REDIRECT --to-ports ${lighttpd_port}

echo "Apply iptables rule done."
