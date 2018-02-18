clang -O2 -emit-llvm -c filter.c -o - | llc -march=bpf -filetype=obj -o filter.o
#clang -target bpf -O2 -c filter.c -o filter.o

sudo tc qdisc del dev wlp4s0 root
sudo tc qdisc add dev wlp4s0 root handle 1:0 htb default 2
sudo tc class add dev wlp4s0 parent 1:0 classid 1:1 htb rate 10000mbit
sudo tc class add dev wlp4s0 parent 1:0 classid 1:2 htb rate 10000mbit
sudo tc filter add dev wlp4s0 parent 1:0 bpf obj filter.o classid 1:1
sudo tc qdisc add dev wlp4s0 parent 1:1 netem loss 100%



sudo tc qdisc show dev wlp4s0
sudo tc class show dev wlp4s0
sudo tc filter show dev wlp4s0
