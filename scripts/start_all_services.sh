#!/bin/ash

SS_MERLIN_HOME=/opt/share/ss-merlin
SHADOW_CONFIG_FILE=${SS_MERLIN_HOME}/etc/shadowsocks/config.json

# 设定一个变量，指定是 clash 还是 ss-redir 。
# 不过没实际意义，改动的地方很多，没办法兼容  ss-redir  了

PROXY_PROC="clash" # ss-redir 
CLASH_HOME=${SS_MERLIN_HOME}/clash/
CLASH_CONFIG_HOME=${SS_MERLIN_HOME}/etc/clash/
CLASH_SERVICE="/opt/etc/init.d/S90clash"

start_proxy(){

  if [[ "${PROXY_PROC}" == 'ss-redir' ]]; then
    ss-redir -c ${SHADOW_CONFIG_FILE} -f /opt/var/run/ss-redir.pid
  else
    if [[ ! -f ${CLASH_SERVICE} ]]; then
      cp ${SS_MERLIN_HOME}/bin/S90clash ${CLASH_SERVICE}

    fi
    # 启动 clash 服务
    ${CLASH_SERVICE} start
  fi

}

kill_proxy(){
  ${CLASH_SERVICE} stop 2>/dev/null
  killall ${PROXY_PROC} 2>/dev/null
}


use_v2ray=0
if [[ -f ${SHADOW_CONFIG_FILE} ]]; then
   use_v2ray=$(grep -w "plugin" ${SHADOW_CONFIG_FILE}|grep "v2ray" -c)
fi

# Start if process not running
ss_pid=$(pidof ${PROXY_PROC})
if [[ -z "$ss_pid" ]]; then
  if [[ ! -f ${SS_MERLIN_HOME}/etc/shadowsocks/config.json ]]; then
    cp ${SS_MERLIN_HOME}/etc/shadowsocks/config.sample.json ${SS_MERLIN_HOME}/etc/shadowsocks/config.json
  fi
  # ss-redir -c ${SS_MERLIN_HOME}/etc/shadowsocks/config.json -f /opt/var/run/ss-redir.pid
  start_proxy
fi

sleep 3

v2ray_pid=$(pidof v2ray-plugin)
if [[ -z "$v2ray_pid" ]]; then
  if [ $use_v2ray -ge 1 ];then 
     killall ${PROXY_PROC} 2>/dev/null
    #  ss-redir -c ${SS_MERLIN_HOME}/etc/shadowsocks/config.json -f /opt/var/run/ss-redir.pid
    start_proxy
  fi
fi

unbound_pid=$(pidof unbound)
if [[ -z "$unbound_pid" ]]; then
  unbound -c ${SS_MERLIN_HOME}/etc/unbound/unbound.conf
fi

echo "All service started."
