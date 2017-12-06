tc qdisc del dev eth0 root
tc qdisc del dev enx8cae4cf5b7ae root
ebtables -t filter -F
ebtables -t nat -F
ebtables -t broute -F
iptables -F

