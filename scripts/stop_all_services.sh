#!/bin/ash
SS_MERLIN_HOME=/opt/share/ss-merlin

# Kill all services
killall clash 2>/dev/null
killall ss-redir 2>/dev/null
killall v2ray-plugin 2>/dev/null
killall unbound 2>/dev/null

rm ${SS_MERLIN_HOME}/etc/dnsmasq.d/user-gfwlist-domains.conf
echo "All service stopped."
