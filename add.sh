#enx8cae4cf5b7ae is on slave side
#eth0 is on computer side

# going to network
tc qdisc add dev eth0 parent root handle 1:0 htb default 1
tc class add dev eth0 parent 1:0 classid 1:1 htb rate 1mbit ceil 10mbit
tc class add dev eth0 parent 1:0 classid 1:2 htb rate 100mbit
tc class add dev eth0 parent 1:0 classid 1:3 htb rate 128kbit ceil 128kbit
tc class add dev eth0 parent 1:3 classid 1:4 htb rate 128kbit ceil 128kbit
tc class add dev eth0 parent 1:3 classid 1:5 htb rate 128kbit ceil 128kbit
#tc filter add dev eth0 parent 1:1 prio 2 protocol ip u32 match tcp dst 7575 0xffff flowid 1:4
#tc filter add dev eth0 parent 1:1 prio 1 protocol ip u32 match tcp src 7575 0xffff flowid 1:4
tc filter add dev eth0 parent 1:0 prio 1 handle 1 fw flowid 1:2
tc filter add dev eth0 parent 1:0 prio 2 handle 2 fw flowid 1:3
tc filter add dev eth0 parent 1:0 prio 3 handle 3 fw flowid 1:3
tc filter add dev eth0 parent 1:3 prio 1 handle 3 fw flowid 1:4
tc filter add dev eth0 parent 1:3 prio 2 u32 match u32 0 0 flowid 1:5
tc qdisc add dev eth0 parent 1:4 netem loss 100%

# going to slave
tc qdisc add dev enx8cae4cf5b7ae parent root handle 1:0 htb default 1
tc class add dev enx8cae4cf5b7ae parent 1:0 classid 1:1 htb rate 1mbit ceil 10mbit
tc class add dev enx8cae4cf5b7ae parent 1:0 classid 1:2 htb rate 100mbit
tc class add dev enx8cae4cf5b7ae parent 1:0 classid 1:3 htb rate 128kbit ceil 128kbit
tc class add dev enx8cae4cf5b7ae parent 1:3 classid 1:4 htb rate 128kbit ceil 128kbit
tc class add dev enx8cae4cf5b7ae parent 1:3 classid 1:5 htb rate 128kbit ceil 128kbit
#tc filter add dev enx8cae4cf5b7ae parent 1:1 prio 2 protocol ip u32 match tcp dst 7575 0xffff flowid 1:4
#tc filter add dev enx8cae4cf5b7ae parent 1:1 prio 1 protocol ip u32 match tcp src 7575 0xffff flowid 1:4
tc filter add dev enx8cae4cf5b7ae parent 1:0 prio 1 handle 1 fw flowid 1:2
tc filter add dev enx8cae4cf5b7ae parent 1:0 prio 2 handle 2 fw flowid 1:3
tc filter add dev enx8cae4cf5b7ae parent 1:0 prio 3 handle 3 fw flowid 1:3
tc filter add dev enx8cae4cf5b7ae parent 1:3 prio 1 handle 3 fw flowid 1:4
tc filter add dev enx8cae4cf5b7ae parent 1:3 prio 2 u32 match u32 0 0 flowid 1:5
tc qdisc add dev enx8cae4cf5b7ae parent 1:4 netem loss 100%

# marking packets coming and going from the slave
ebtables -A FORWARD -i enx8cae4cf5b7ae -j mark --set-mark 2 --mark-target CONTINUE
ebtables -A FORWARD -o enx8cae4cf5b7ae -j mark --set-mark 2 --mark-target CONTINUE
iptables -A OUTPUT -p tcp --dport 7575 -j MARK --set-mark 1
iptables -A INPUT -p tcp --sport 7575 -j MARK --set-mark 1
iptables -A FORWARD -m statistic --mode nth --every 20 --packet 0 -j MARK --set-mark 3

#          1:0      root qdisc htb
#        /  |  \
#       /   |   \
#    1:1   1:2   1:3    child classes: other traffic(1:1), usbip traffic(1:2), slave traffic(1:3)
#     |     |    / \  
#    10:   20:  /   \     automatically generated pfifo qdiscs 
#              /     \
#            1:4     1:5    child classes for filtering every nth packet with bpf to 1:4 and the rest to 1:5
#             |       |
#            40:     50:      netem qdiscs for testing data, 100% loss and 0% loss to begin with  
