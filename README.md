# Contents

* [Nanopi Neo v1.2](#nanopi-neo-v1.2)
* [Linux images](#linux-images)
* [Installing image](#insstalling-the-image-to-an-sd-card)
* [Serial connection for initial configuration](#serial-connection-for-initial-configuration)
* [Network configuration](#network-configuration)
    * [Master](#master)
    * [Slave](#slave)
    * [Laptop](#laptop)
* [eBPF](#ebpf)
    * [Dependencies](#dependencies)
    * [Useful Resources](#useful-resources)
* [Simple data policing](#simple-data-policing)
    * [Ingress](#ingress)
    * [Egress](#egress)
* [Roadblocks](#roadblocks)
* [Testing the connection](#benchmarking-the-connection)

# Network Device Testing Tool


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


## Serial connection for intial configuration

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

Kernel version 4.1 or newer.
```
Extends the "classic" BPF programmable tc classifier by extending its scope also to native eBPF code, thus allowing userspace to implement own custom, 'safe' C like classifiers that can then be compiled with the LLVM eBPF backend to an eBPF elf file and loaded into the kernel via iproute2's tc, and be JITed in the kernel
```
Running on neo ubuntu core xenial 4.11.2.

## Useful resources

Well explained examples for various network tools in linux:
http://lartc.org/howto/index.html

## Simple data policing

http://lartc.org/howto/lartc.qdisc.filters.html

We used the eth0 port for the slave side, but if you use the adapter you need to change the interface used in these configs
We need to configure an ingress policer and an egress data shaping separately if we want to police the rate both ways.
The bottleneck is located in the interface to the slave side on the master board.

### Ingress

Clear existing policy setups:
```
tc qdisc del dev eth0 ingress
```

Create police rate on ingress:
```
tc qdisc add dev eth0 ingress
tc filter add dev eth0 parent ffff: u32 match u32 0 0 police rate 500kbit burst 100k
```

### Egress
Clear previous config
```
tc qdisc del dev eth0 root
```

Create shaping rate limiter, we will use Token bucket filter.
```
tc qdisc add dev eth0 root tbf rate 500kbit burst 100k latency 100ms
```

# Roadblocks

We updated the master to a fresh armbian install with kernel version 4.11.2, as eBPF supports connections to traffic control classifiers. It resulted in a kernel error. Kernel error occurs on both mainline armbian and neo ubuntu xenial. We will have to see if kernel version 3.x is enough for the project.

Kernel error occurs when connecting to the board via SSH. The kernel dumb is attached in kernel-error-dump.txt

It appears that if the usb-eth adapter is on the slave side no kernel errors occur. The network configuration is now updated.

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

Then you can use iftop to monitor the data rates
```
iftop
```
