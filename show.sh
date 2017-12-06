tc -s qdisc show
tc -s -d class show dev eth0
#tc -s -d class show dev enx8cae4cf5b7ae
tc filter show dev eth0
#tc filter show dev enx8cae4cf5b7ae
ebtables -L --Lc

