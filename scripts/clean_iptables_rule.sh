#!/bin/ash

# delete related rules
iptables -t mangle -D OUTPUT -j SS_OUTPUT 2>/dev/null
iptables -t mangle -D PREROUTING -j SS_PREROUTING 2>/dev/null

iptables -t nat -D OUTPUT -j SS_OUTPUT 2>/dev/null
iptables -t nat -D PREROUTING -j SS_PREROUTING 2>/dev/null
iptables -t nat -F SS_OUTPUT 2>/dev/null
iptables -t nat -X SS_OUTPUT 2>/dev/null
iptables -t nat -F SS_PREROUTING 2>/dev/null
iptables -t nat -X SS_PREROUTING 2>/dev/null
iptables -t nat -F SHADOWSOCKS_TCP 2>/dev/null
iptables -t nat -X SHADOWSOCKS_TCP 2>/dev/null

iptables -t mangle -D PREROUTING -j SHADOWSOCKS_TCP 2>/dev/null

# dsff 
iptables -t nat -D PREROUTING -j USER302 2>/dev/null
iptables -t nat -F USER302 2>/dev/null
iptables -t nat -X USER302 2>/dev/null
iptables -t nat -D PREROUTING -j USER302 2>/dev/null
iptables -t nat -F USER302 2>/dev/null
iptables -t nat -X USER302 2>/dev/null


iptables -t mangle -F SS_OUTPUT 2>/dev/null
iptables -t mangle -X SS_OUTPUT 2>/dev/null

iptables -t mangle -F SS_PREROUTING 2>/dev/null
iptables -t mangle -X SS_PREROUTING 2>/dev/null

iptables -t mangle -F SHADOWSOCKS_UDP 2>/dev/null
iptables -t mangle -X SHADOWSOCKS_UDP 2>/dev/null

iptables -t mangle -F SHADOWSOCKS_TCP 2>/dev/null
iptables -t mangle -X SHADOWSOCKS_TCP 2>/dev/null


iptables -t mangle -F SS_OUTPUT 2>/dev/null
iptables -t mangle -X SS_OUTPUT 2>/dev/null


ip rule del fwmark 0x2333 table 100 2>/dev/null
ip route del local 0.0.0.0/0 dev lo table 100 2>/dev/null

# Destory ipset
ipset destroy chinaips 2>/dev/null
ipset destroy gfwlist 2>/dev/null
ipset destroy localips 2>/dev/null
ipset destroy whitelist 2>/dev/null
ipset destroy userwhitelist 2>/dev/null
ipset destroy usergfwlist 2>/dev/null
ipset destroy user302list 2>/dev/null

echo "Clean iptables rule done."
