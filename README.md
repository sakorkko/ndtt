# Network Device Testing Tool

# Contents
* [Nanopi Neo v1.2](#nanopi-neo-v1.2)
* [Linux images](#linux-images)
* [Installing image](#installing-the-image-to-an-sd-card)
* [Serial connection for initial configuration](#serial-connection-for-initial-configuration)
* [Network configuration](#network-configuration)
    * [Master](#master)
    * [Slave](#slave)
    * [Laptop](#laptop)
* [eBPF](#ebpf)
    * [Dependencies](#dependencies)
    * [Useful Resources](#useful-resources)
* [Simple data policing](#simple-data-policing)
    * [Mark packets for the tc filters](#mark-packets-for-the-tc-filters)
    * [Coming from slave](#coming-from-slave)
    * [Going to slave](#going-to-slave)
* [Roadblocks](#roadblocks)
* [Testing the connection](#benchmarking-the-connection)
* [USBIP](#usbip)
    * [VirtualHere USBIP drivers](#virtualhere-usbip-drivers)

## Nanopi Neo v1.2
A board that runs linux similar to the Raspberry pi but more affordable and barebone.

## Linux Images
Armbian Ubuntu server
https://dl.armbian.com/nanopineo/

FriendlyArm Ubuntu/Debian
http://wiki.friendlyarm.com/wiki/

We chose Armbian Ubuntu server - legacy kernel
https://dl.armbian.com/nanopineo/Ubuntu_xenial_default.7z

We will have to see if we need to switch images later.
There seems to be an issue with our usb-to-eth adapter on the newer kernel versions so we have to use the legacy kernel 3.4.


## Installing the image to an sd card
On linux first you can check the path to your card with:
```
lsblk
```
Then you can use dd to install the image
```
sudo dd if=/path/to/image.img of=/dev/mmcblk0 bs=16M
```

## Serial connection for initial configuration
Minicom seems to work on linux and Putty on windows.
Settings used are: 115200 baudrate, 8N1, NOR
Com ports on linux usually are on /dev/ttyUSBX, where X is 0-3


## Network configuration
Testing is currently run with two of the boards chained like so:

	internet--[wlan]---LAPTOP---MASTER---SLAVE

All hardware connections are given static ips so no dhcp server is needed 

### Master
```
/etc/network/interfaces
iface enx8cae4cf5b7ae inet manual
iface eth0 inet manual

auto br0
iface br0 inet static
	bridge_ports enx8cae4cf5b7ae eth0
	address 192.168.50.5
	netmask 255.255.255.0
```
where enx8cae4cf5b7ae is an usb-to-eth 10/100 adapter

### Slave
```
/etc/network/interfaces
auto eth0
iface eth0 inet static
	address 192.168.50.6
	netmask 255.255.255.0
```

### Laptop
```
/etc/network/interfaces
auto enp3s0
allow-hotplug enp3s0
iface enp3s0 inet static
        address 192.168.50.4
	netmask 255.255.255.0
```
where enp3s0 is eth0

# eBPF

## Dependencies
Some parts require kernel version 4.1 or newer, we will have to see if the newer things are needed.
```
Extends the "classic" BPF programmable tc classifier by extending its scope also to native eBPF code, thus allowing userspace to implement own custom, 'safe' C like classifiers that can then be compiled with the LLVM eBPF backend to an eBPF elf file and loaded into the kernel via iproute2's tc, and be JITed in the kernel
```

## Useful resources
Well explained examples for various network tools in linux:
http://lartc.org/howto/index.html

Since kernel 3.18, which is usable in the device, eBPF-maps make memory usage between BPF runs possible. 
"Thanks to eBPF-maps, programs written in eBPF can maintain state and thus aggregate information across events plus have dynamic behavior. Uses of eBPF continue to expanded due to its minimalistic implementation and lightening speed performance. Now onto what to expect for the future of eBPF."

Better explanation with much more in the the article that can be found through this link: https://ferrisellis.com/posts/ebpf_past_present_future/

## Simple data policing
http://lartc.org/howto/lartc.qdisc.filters.html

We used the enx8cae4cf5b7ae interface on the slave side. Ingress and Egress is handled separately but they both are essentially the same configurations. We used Hierarchical Token Bucket bucket for the limiting and classification of packets. Didn't seem to get u32 matching to work for tcp port so instead used iptables to set mark 2 for usbip traffic.

Configuration
```
          1:0           root qdisc htb
         /   \
        /     \
      1:2     1:1       child classes: other traffic, slave traffic (mark 1)
       |     /   \
       |   1:4   1:3    child classes: usbip traffic (mark 2), testing data traffic
       |    |     | 
      20:  40:    |     automatically generated pfifo qdiscs 
                  |
                 30:    netem qdisc for testing data  
```

### Mark packets for the tc filters
```
ebtables -A FORWARD -i enx8cae4cf5b7ae -j mark --set-mark 1 --mark-target CONTINUE
ebtables -A FORWARD -o enx8cae4cf5b7ae -j mark --set-mark 1 --mark-target CONTINUE
iptables -A FORWARD -p tcp --dport 7575 -j MARK --set-mark 2
iptables -A FORWARD -p tcp --sport 7575 -j MARK --set-mark 2
```

### Coming from slave

```
tc qdisc add dev eth0 parent root handle 1:0 htb default 2
tc class add dev eth0 parent 1:0 classid 1:1 htb rate 100mbit ceil 100mbit
tc class add dev eth0 parent 1:0 classid 1:2 htb rate 100mbit
tc class add dev eth0 parent 1:1 classid 1:3 htb rate 128kbit ceil 128kbit
tc class add dev eth0 parent 1:1 classid 1:4 htb rate 50mbit
tc filter add dev eth0 parent 1:0 protocol ip handle 1 fw flowid 1:1
tc filter add dev eth0 parent 1:1 prio 1 handle 2 fw flowid 1:4
tc filter add dev eth0 parent 1:1 prio 2 handle 1 fw flowid 1:3
```

### Going to slave

```
tc qdisc add dev enx8cae4cf5b7ae parent root handle 1:0 htb default 2
tc class add dev enx8cae4cf5b7ae parent 1:0 classid 1:1 htb rate 100mbit ceil 100mbit
tc class add dev enx8cae4cf5b7ae parent 1:0 classid 1:2 htb rate 100mbit
tc class add dev enx8cae4cf5b7ae parent 1:1 classid 1:3 htb rate 128kbit ceil 128kbit
tc class add dev enx8cae4cf5b7ae parent 1:1 classid 1:4 htb rate 50mbit
tc filter add dev enx8cae4cf5b7ae parent 1:0 protocol ip handle 1 fw flowid 1:1
tc filter add dev enx8cae4cf5b7ae parent 1:1 prio 1 handle 2 fw flowid 1:4
tc filter add dev enx8cae4cf5b7ae parent 1:1 prio 2 handle 1 fw flowid 1:3
```

# Roadblocks
We updated the master to a fresh armbian install with kernel version 4.11.2, as eBPF supports connections to traffic control classifiers. It resulted in a kernel error. Kernel error occurs on both mainline armbian and neo ubuntu xenial. We will have to see if kernel version 3.x is enough for the project.

Kernel error occurs when connecting to the board via SSH. The kernel dumb is attached in kernel-error-dump.txt

It appears this was not a fix since the kernel error happens again when there is a shh connection between master and slave boards.

### Update

The kernel error seems to be connected to the usb-to-eth adapter or its drivers. Everytime a ssh connection is made over it the adapter, the board connected to it will crash if it contains the newer kernel.

## Bcc

We found an tool for using eBPF called BCC, but the github page says: "Much of what BCC uses requires Linux 4.1 and above."
https://github.com/iovisor/bcc

# Benchmarking the connection

install netperf on all devices
```
sudo apt-get install netperf
```
Start server on laptop for testing the connection from slave to laptop.
You can also start a server on the slave to test the connection the other way
```
netserver -4 -p 16604
```
Then you can test the connection by using the netperf command
```
netperf -H 192.168.50.6 -p 16604 -l 100
```

Then you can use iftop or nload to monitor the data rates
```
iftop
nload
```

# USBIP
## VirtualHere USBIP drivers
Server installation instructions from 
```
wget https://virtualhere.com/sites/default/files/usbserver/vhusbdarm
chmod +x ./vhusbdarm
sudo ./vhusbdarm -b
```
Client versions of the software can be downloaded here
https://virtualhere.com/usb_client_software

After installation and running the executables, it should work straight away.

TODO: Add server configuration to only use tcp 7575 for to get past policer on the bridge.

Performance testing will be updated later, but at the moment the initial connection seems to take atleast 20 seconds everytime.
