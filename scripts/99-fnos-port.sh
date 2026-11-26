#!/system/bin/sh
# fnOS (Droidspaces container) web UI port forwarding
# Adds DNAT rules so the fnOS interface is reachable from LAN:
#   http://<phone-ip>:5666  -> container 5666 (fnOS main UI)
#   http://<phone-ip>:8080  -> container 80   (redirects to 5666)

CFG=/data/local/Droidspaces/img/container.config
IP=$(grep '^static_nat_ip=' "$CFG" 2>/dev/null | cut -d= -f2)
[ -n "$IP" ] || IP=172.28.248.164

# wait for boot to settle (Android rewrites iptables during boot)
i=0
while [ $i -lt 150 ]; do
    [ "$(getprop sys.boot_completed)" = "1" ] && break
    sleep 2
    i=$((i + 1))
done
sleep 20

add_fwd() {
    hp="$1"; cp="$2"
    iptables -t nat -D PREROUTING -p tcp -m addrtype --dst-type LOCAL --dport "$hp" \
        -j DNAT --to-destination "$IP:$cp" 2>/dev/null
    iptables -t nat -I PREROUTING 1 -p tcp -m addrtype --dst-type LOCAL --dport "$hp" \
        -j DNAT --to-destination "$IP:$cp" 2>/dev/null
    iptables -t nat -D OUTPUT -p tcp --dport "$hp" \
        -j DNAT --to-destination "$IP:$cp" 2>/dev/null
    iptables -t nat -I OUTPUT 1 -p tcp --dport "$hp" \
        -j DNAT --to-destination "$IP:$cp" 2>/dev/null
}

add_fwd 5666 5666
add_fwd 8080 80
