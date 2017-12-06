#enx8cae4cf5b7ae is on slave side
#eth0 is on computer side

# reset previous config
#tc qdisc del dev eth0 root
#tc qdisc del dev enx8cae4cf5b7ae root
#ebtables -t filter -F
#ebtables -t nat -F
#ebtables -t broute -F

# coming from slave
tc qdisc add dev eth0 parent root handle 1:0 htb default 2
tc class add dev eth0 parent 1:0 classid 1:1 htb rate 100mbit ceil 100mbit
tc class add dev eth0 parent 1:0 classid 1:2 htb rate 100mbit
tc class add dev eth0 parent 1:1 classid 1:3 htb rate 128kbit ceil 128kbit
tc class add dev eth0 parent 1:1 classid 1:4 htb rate 50mbit
tc filter add dev eth0 parent 1:0 protocol ip handle 1 fw flowid 1:1
#tc filter add dev eth0 parent 1:1 prio 2 protocol ip u32 match tcp dst 7575 0xffff flowid 1:4
#tc filter add dev eth0 parent 1:1 prio 1 protocol ip u32 match tcp src 7575 0xffff flowid 1:4
tc filter add dev eth0 parent 1:1 prio 1 handle 2 fw flowid 1:4
tc filter add dev eth0 parent 1:1 prio 2 handle 1 fw flowid 1:3

# going to slave
tc qdisc add dev enx8cae4cf5b7ae parent root handle 1:0 htb default 2
tc class add dev enx8cae4cf5b7ae parent 1:0 classid 1:1 htb rate 100mbit ceil 100mbit
tc class add dev enx8cae4cf5b7ae parent 1:0 classid 1:2 htb rate 100mbit
tc class add dev enx8cae4cf5b7ae parent 1:1 classid 1:3 htb rate 128kbit ceil 128kbit
tc class add dev enx8cae4cf5b7ae parent 1:1 classid 1:4 htb rate 50mbit
tc filter add dev enx8cae4cf5b7ae parent 1:0 protocol ip handle 1 fw flowid 1:1
#tc filter add dev enx8cae4cf5b7ae parent 1:1 prio 2 protocol ip u32 match tcp dst 7575 0xffff flowid 1:4
#tc filter add dev enx8cae4cf5b7ae parent 1:1 prio 1 protocol ip u32 match tcp src 7575 0xffff flowid 1:4
tc filter add dev enx8cae4cf5b7ae parent 1:1 prio 1 handle 2 fw flowid 1:4
tc filter add dev enx8cae4cf5b7ae parent 1:1 prio 2 handle 1 fw flowid 1:3

# marking packets coming and going from the slave
ebtables -A FORWARD -i enx8cae4cf5b7ae -j mark --set-mark 1 --mark-target CONTINUE
ebtables -A FORWARD -o enx8cae4cf5b7ae -j mark --set-mark 1 --mark-target CONTINUE
iptables -A FORWARD -p tcp --dport 7575 -j MARK --set-mark 2
iptables -A FORWARD -p tcp --sport 7575 -j MARK --set-mark 2
#iptables -A FORWARD -p tcp --dport 7575 -j MARK --set-mark 2



# list what is done
#tc -s -dqdisc show
#tc -s -d class show dev eth0
#tc -s -d class show dev enx8cae4cf5b7ae
#tc filter show dev eth0
#tc filter show dev enx8cae4cf5b7ae
#ebtables -L --Lc

#          1:0      root qdisc htb
#         /   \
#        /     \
#      1:2     1:1    child classes: other traffic, slave traffic
#       |     /   \
#       |   1:4   1:3   child classes: usbip traffic, testing data traffic
#       |    |     | 
#      20:  40:    |     automatically generated pfifo qdiscs 
#                  |
#                 30:    netem qdisc for testing data  
