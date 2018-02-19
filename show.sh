echo "*** QDISC ***"
tc -s qdisc show
echo "*** CLASS eth0 ***"
tc -s -d class show dev eth0
echo "*** CLASS adapter ***"
tc -s -d class show dev enx8cae4cf5b7ae
echo "*** FILTER eth0 ***"
tc filter show dev eth0
echo "*** FILTER ADAPTER ***"
tc filter show dev enx8cae4cf5b7ae
echo "*** Ebtables ***"
ebtables -L --Lc
echo "*** Iptables ***"
iptables -L -v


