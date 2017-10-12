# Contents

* [Linux images](#linux-images)
* [Installing image](#installing-the-image-to-an-sd-card)
* [Network configuration](#network-configuration)
    * [Master](#master)
    * [Slave](#slave)
    * [Laptop](#laptop)
* [eBPF](#ebpf)
    * [Dependencies](#dependencies)
* [Roadblocks](#roadblocks)

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

We will have to see if we need to switch images later


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

	internet --(wlan)-- laptop --- master --- slave

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
enp3s0
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
We updated the master to a fresh armbian install, as eBPF supports connections to traffic control classifiers. We thought it necessary.

# Roadblocks

