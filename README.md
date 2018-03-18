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
    * [Goals with eBpf](#goals-with-ebpf)
    * [Dependencies](#dependencies)
    * [Workflow for eBpf programs](#workflow-for-ebpf-programs)
    * [BCC](#bcc)
    * [Tc filter every nth packet with eBpf](#tc-filter-every-nth-packet-with-ebpf)
* [Simple version of the setup](#simple-version-of-the-setup)
    * [Mark packets for the tc filters](#mark-packets-for-the-tc-filters)
    * [Going to network](#going-to-network)
    * [Going to slave](#going-to-slave)
* [Testing the connection](#benchmarking-the-connection)
    * [Testing if every nth packet is being dropped](#testing-if-every-nth-packet-is-being-dropped)
* [USBIP](#usbip)
    * [VirtualHere USBIP drivers](#virtualhere-usbip-drivers)
* [DAPLink](#daplink)
    * [Test on windows machine](#test-on-windows-machine)
    * [Test on linux machine](#test-on-linux-machine)
    * [Test on windows machine over linux USBIP server](#test-on-windows-machine-over-linux-usbip-server)
    * [Test on windows machine over windows USBIP server](#test-on-windows-machine-over-windows-usbip-server)
    * [Test on windows machine over NanoPi Neo USBIP server](#test-on-windows-machine-over-nanopi-neo-usbip-server)
* [Roadblocks](#roadblocks)
* [Useful Resources](#useful-resources)
* [Next Step](#next-step)

Test on windows machine over linux USBIP server
Test on windows machine over windows USBIP server
Test on windows machine over NanoPi Neo USBIP server    
    

# Nanopi Neo v1.2
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


# Network configuration
Testing is currently run with two of the boards chained like so:

	internet---router---master---slave
		      |
		   laptop

## Master
```
/etc/network/interfaces
iface enx8cae4cf5b7ae inet manual
iface eth0 inet manual

auto br0
iface br0 inet static
	bridge_ports enx8cae4cf5b7ae eth0
	address 192.168.1.107
	netmask 255.255.255.0
```
where enx8cae4cf5b7ae is an usb-to-eth 10/100 adapter

## Slave
```
/etc/network/interfaces
auto eth0
iface eth0 inet static
	address 192.168.1.148
	netmask 255.255.255.0
```

## Laptop
```
/etc/network/interfaces
auto enp3s0
allow-hotplug enp3s0
iface enp3s0 inet static
        address 192.168.1.147
	netmask 255.255.255.0
```
where enp3s0 is eth0

# eBPF
Berkeley packet filter. Originally was used for filtering/modifying network packets. Bpf programs were loaded straight to the kernel for performance and speed. Later in 2014 the extended Berkeley packet filter was created. This time it added support for a lot of things. Notable additions are maps (essentially memory), more hookpoints in different locations, helper functions and bigger registers and stack.

Since kernel 3.18, which is usable in the device, eBPF-maps make memory usage between BPF runs possible. 
"Thanks to eBPF-maps, programs written in eBPF can maintain state and thus aggregate information across events plus have dynamic behavior. Uses of eBPF continue to expanded due to its minimalistic implementation and lightening speed performance. Now onto what to expect for the future of eBPF."

## Goals with eBpf
The reason we are using bpf is to learn to use it and to make a filter for packets that drops or modifies every nth packet. The netem queue discipline in tc is not sufficient since it relies on a probability per packet.

## Dependencies
Some parts require kernel version 4.1 or newer, we will have to see if the newer things are needed.
```
Extends the "classic" BPF programmable tc classifier by extending its scope also to native eBPF code, thus allowing userspace to implement own custom, 'safe' C like classifiers that can then be compiled with the LLVM eBPF backend to an eBPF elf file and loaded into the kernel via iproute2's tc, and be JITed in the kernel
```

## Workflow for eBpf programs
Write code in restricted C, compile to an object file with LLVM, load the object file into kernel with the bpf() syscall or tc. The object file will be verified before loading it into the kernel.

## Bcc
We found an tool for using eBPF called BCC, but the github page says: "Much of what BCC uses requires Linux 4.1 and above."
https://github.com/iovisor/bcc
Bcc is essentially a python/C frontend for creating ebpf programs.

## Tc filter every nth packet with eBpf
A working version of the filter is in filter.c.
Since tc ebpf classifier requires 4.1 kernel we could not use it in our device. A workaround would be to use the bpf() syscall to load a bpf program to listen to a raw socket and mark the packets that way, but we ended up using iptables for that.

The tc bpf filter uses elf sections to distinquish sections for the verifier and tc to load automatically. They search for sections like: map, classifier, action...

```
# Compile into an object file
clang -O2 -emit-llvm -c filter.c -o - | llc -march=bpf -filetype=obj -o filter.o
# Load and verify in kernel
sudo tc filter add dev DEV parent 1:0 bpf obj filter.o classid 1:1
```


# Simple version of the setup

We used the enx8cae4cf5b7ae interface on the slave side. Ingress and Egress is handled separately but they both are essentially the same configurations. We used Hierarchical Token Bucket bucket for the limiting and classification of packets. Filtering the packets are done with marking them first. Didn't seem to get u32 matching to work for tcp port so instead used iptables to set mark 2 for usbip traffic. Mark 1 and 3 are used for the slave traffic, 3 is the traffic that will be dropped. There is a priority lane for USBIP traffic for the port 7575.

Our goal was to use bpf for the every nth filtering originally but ended up using iptables. More information above.

Tc configuration
```
          1:0      root qdisc htb
        /  |  \
       /   |   \
    1:1   1:2   1:3    child classes: other traffic(1:1), usbip traffic(1:2), slave traffic(1:3)
     |     |    / \  
    10:   20:  /   \     automatically generated pfifo qdiscs 
              /     \
            1:4     1:5    child classes for filtering every nth packet with bpf to 1:4 and the rest to 1:5
             |       |
            40:     50:      netem qdiscs for testing data, 100% loss and 0% loss to begin with  
```

## Mark packets for the tc filters
```
ebtables -A FORWARD -i enx8cae4cf5b7ae -j mark --set-mark 2 --mark-target CONTINUE
ebtables -A FORWARD -o enx8cae4cf5b7ae -j mark --set-mark 2 --mark-target CONTINUE
iptables -A OUTPUT -p tcp --dport 7575 -j MARK --set-mark 1
iptables -A INPUT -p tcp --sport 7575 -j MARK --set-mark 1
iptables -A FORWARD -m statistic --mode nth --every 20 --packet 0 -j MARK --set-mark 3
```
## Going to network
```
tc qdisc add dev eth0 parent root handle 1:0 htb default 1
tc class add dev eth0 parent 1:0 classid 1:1 htb rate 1mbit ceil 10mbit
tc class add dev eth0 parent 1:0 classid 1:2 htb rate 100mbit
tc class add dev eth0 parent 1:0 classid 1:3 htb rate 128kbit ceil 128kbit
tc class add dev eth0 parent 1:3 classid 1:4 htb rate 128kbit ceil 128kbit
tc class add dev eth0 parent 1:3 classid 1:5 htb rate 128kbit ceil 128kbit
tc filter add dev eth0 parent 1:0 prio 1 handle 1 fw flowid 1:2
tc filter add dev eth0 parent 1:0 prio 2 handle 2 fw flowid 1:3
tc filter add dev eth0 parent 1:0 prio 3 handle 3 fw flowid 1:3
tc filter add dev eth0 parent 1:3 prio 1 handle 3 fw flowid 1:4
tc filter add dev eth0 parent 1:3 prio 2 u32 match u32 0 0 flowid 1:5
tc qdisc add dev eth0 parent 1:4 netem loss 100%
```
## Going to slave
```
tc qdisc add dev enx8cae4cf5b7ae parent root handle 1:0 htb default 1
tc class add dev enx8cae4cf5b7ae parent 1:0 classid 1:1 htb rate 1mbit ceil 10mbit
tc class add dev enx8cae4cf5b7ae parent 1:0 classid 1:2 htb rate 100mbit
tc class add dev enx8cae4cf5b7ae parent 1:0 classid 1:3 htb rate 128kbit ceil 128kbit
tc class add dev enx8cae4cf5b7ae parent 1:3 classid 1:4 htb rate 128kbit ceil 128kbit
tc class add dev enx8cae4cf5b7ae parent 1:3 classid 1:5 htb rate 128kbit ceil 128kbit
tc filter add dev enx8cae4cf5b7ae parent 1:0 prio 1 handle 1 fw flowid 1:2
tc filter add dev enx8cae4cf5b7ae parent 1:0 prio 2 handle 2 fw flowid 1:3
tc filter add dev enx8cae4cf5b7ae parent 1:0 prio 3 handle 3 fw flowid 1:3
tc filter add dev enx8cae4cf5b7ae parent 1:3 prio 1 handle 3 fw flowid 1:4
tc filter add dev enx8cae4cf5b7ae parent 1:3 prio 2 u32 match u32 0 0 flowid 1:5
tc qdisc add dev enx8cae4cf5b7ae parent 1:4 netem loss 100%
```

# Testing the connection

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
netperf -H 192.168.1.147 -p 16604 -l 100
```
Then you can use iftop or nload to monitor the data rates
```
iftop
nload
```

## Testing if every nth packet is being dropped
Every 20th packet should be marked and dropped.
The rate should also be around 128kbit.
```
MASTER:
*** Ebtables ***
Bridge table: filter
Bridge chain: INPUT, entries: 0, policy: ACCEPT
Bridge chain: FORWARD, entries: 2, policy: ACCEPT
-i enx8cae4cf5b7ae -j mark --mark-set 0x2 --mark-target CONTINUE, pcnt = 0 -- bcnt = 0
-o enx8cae4cf5b7ae -j mark --mark-set 0x2 --mark-target CONTINUE, pcnt = 0 -- bcnt = 0
Bridge chain: OUTPUT, entries: 0, policy: ACCEPT

*** Iptables ***
Chain INPUT (policy ACCEPT 46 packets, 2680 bytes)
 pkts bytes target     prot opt in     out     source               destination         
    0     0 MARK       tcp  --  any    any     anywhere             anywhere             tcp spt:7575 MARK set 0x1
Chain FORWARD (policy ACCEPT 0 packets, 0 bytes)
 pkts bytes target     prot opt in     out     source               destination         
    0     0 MARK       all  --  any    any     anywhere             anywhere             statistic mode nth every 20 MARK set 0x3
Chain OUTPUT (policy ACCEPT 51 packets, 10428 bytes)
 pkts bytes target     prot opt in     out     source               destination         
    0     0 MARK       tcp  --  any    any     anywhere             anywhere             tcp dpt:7575 MARK set 0x1


SLAVE:
root@slave:~# netperf -H 192.168.1.147 -p 16604 -l 10
MIGRATED TCP STREAM TEST from 0.0.0.0 () port 0 AF_INET to 192.168.1.147 () port 0 AF_INET : demo
Recv   Send    Send                          
Socket Socket  Message  Elapsed              
Size   Size    Size     Time     Throughput  
bytes  bytes   bytes    secs.    10^6bits/sec  
 87380  16384  16384    12.01       0.12   


LAPTOP:
Incoming:
     Curr: 117.97 kBit
     Avg: 5.55 kBit/s
     Min: 0.00 Bit/s
     Max: 13.31 MBit/s
     Ttl: 814.37 MByte

MASTER:
*** Ebtables ***
Bridge table: filter
Bridge chain: INPUT, entries: 0, policy: ACCEPT
Bridge chain: FORWARD, entries: 2, policy: ACCEPT
-i enx8cae4cf5b7ae -j mark --mark-set 0x2 --mark-target CONTINUE, pcnt = 174 -- bcnt = 204068
-o enx8cae4cf5b7ae -j mark --mark-set 0x2 --mark-target CONTINUE, pcnt = 160 -- bcnt = 13618
Bridge chain: OUTPUT, entries: 0, policy: ACCEPT

*** Iptables ***
Chain INPUT (policy ACCEPT 119 packets, 6516 bytes)
 pkts bytes target     prot opt in     out     source               destination         
    0     0 MARK       tcp  --  any    any     anywhere             anywhere             tcp spt:7575 MARK set 0x1
Chain FORWARD (policy ACCEPT 324 packets, 217K bytes)
 pkts bytes target     prot opt in     out     source               destination         
   17  9794 MARK       all  --  any    any     anywhere             anywhere             statistic mode nth every 20 MARK set 0x3
Chain OUTPUT (policy ACCEPT 132 packets, 23724 bytes)
 pkts bytes target     prot opt in     out     source               destination         
    0     0 MARK       tcp  --  any    any     anywhere             anywhere             tcp dpt:7575 MARK set 0x1
```
Here we can see that 174+160=334 packets were forwarded during the network test. 17 packets were marked and dropped. This equals to ~20 as it was supposed to. We had to change to number to a higher one because the could not be established with every 3 packet dropping.

The dropping works because the connection grew increasingly unsteady the lower the nth value was.

117 kBit is as expected with the packet loss.

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

No such issues running the server on a linux laptop.

# DAPLink
* https://github.com/ARMmbed/DAPLink/tree/master/test/stress_tests
Testing an FRDM-K64F board.
The tests use python 2.7.

### Test on windows machine
##### msd_remount_test
```
c:\Python27\python.exe msd_remount_test.py
Triggering remount for 0 F: - 0240000033514e450044500585d4000be981000097969900 at 0.048000 - 15:38:26
Drive F: dismount
Remount complete as F:
Triggering remount for 0 F: - 0240000033514e450044500585d4000be981000097969900 at 3.669000 - 15:38:30
Drive F: dismount
Remount complete as F:
Triggering remount for 0 F: - 0240000033514e450044500585d4000be981000097969900 at 7.194000 - 15:38:33
Drive F: dismount
Remount complete as F:
Triggering remount for 0 F: - 0240000033514e450044500585d4000be981000097969900 at 10.792000 - 15:38:37
Drive F: dismount
Remount complete as F:
Triggering remount for 0 F: - 0240000033514e450044500585d4000be981000097969900 at 14.757000 - 15:38:41
Drive F: dismount
Remount complete as F:
Triggering remount for 0 F: - 0240000033514e450044500585d4000be981000097969900 at 18.767000 - 15:38:45
Exiting
```
##### hid_usb_test
```
c:\Python27\python.exe hid_usb_test.py
Thread 0 exception board 0240000033514e450044500585d4000be981000097969900
Exiting
Exception in thread Thread-3:
Traceback (most recent call last):
  File "c:\Python27\lib\threading.py", line 801, in __bootstrap_inner
    self.run()
  File "c:\Python27\lib\threading.py", line 754, in run
    self.__target(*self.__args, **self.__kwargs)
  File "hid_usb_test.py", line 43, in hid_main
    device = pyOCD.pyDAPAccess.DAPAccess.get_device(board_id)
  File "c:\Python27\lib\site-packages\pyOCD\pyDAPAccess\dap_access_cmsis_dap.py", line 367, in get_device
    assert isinstance(device_id, str)
AssertionError
```
##### cdc_stress_test
```
c:\Python27\python.exe cdc_stress_test.py
Thread 0 on loop          0 at 0.142000 - 15:37:19 - port COM3
Thread 0 on loop         10 at 0.251000 - 15:37:19 - port COM3
Thread 0 on loop         20 at 0.352000 - 15:37:19 - port COM3
Thread 0 on loop         30 at 0.455000 - 15:37:19 - port COM3
Thread 0 on loop         40 at 0.558000 - 15:37:19 - port COM3
Thread 0 on loop         50 at 0.660000 - 15:37:19 - port COM3
Thread 0 on loop         60 at 0.764000 - 15:37:19 - port COM3
Thread 0 on loop         70 at 0.865000 - 15:37:19 - port COM3
Thread 0 on loop         80 at 0.966000 - 15:37:19 - port COM3
Thread 0 on loop         90 at 1.069000 - 15:37:20 - port COM3
Thread 0 on loop        100 at 1.172000 - 15:37:20 - port COM3
Thread 0 on loop        110 at 1.275000 - 15:37:20 - port COM3
Thread 0 on loop        120 at 1.378000 - 15:37:20 - port COM3
```
Some problems with the hid test, sometimes worked when replugged the cable and other times not.

### Test on windows machine over linux USBIP server
Virtualhere server running on debian stretch, client on a windows 10. Connection over local network.

##### msd_remount_test
```
c:\Python27\python.exe msd_remount_test.py
Triggering remount for 0 F: - 0240000033514e450044500585d4000be981000097969900 at 0.049000 - 15:44:29
Drive F: dismount
Remount complete as F:
Triggering remount for 0 F: - 0240000033514e450044500585d4000be981000097969900 at 3.687000 - 15:44:33
Drive F: dismount
Remount complete as F:
Triggering remount for 0 F: - 0240000033514e450044500585d4000be981000097969900 at 7.531000 - 15:44:37
Drive F: dismount
Remount complete as F:
Triggering remount for 0 F: - 0240000033514e450044500585d4000be981000097969900 at 11.492000 - 15:44:41
Drive F: dismount
Remount complete as F:
Triggering remount for 0 F: - 0240000033514e450044500585d4000be981000097969900 at 15.531000 - 15:44:45
Drive F: dismount
Remount complete as F:
Triggering remount for 0 F: - 0240000033514e450044500585d4000be981000097969900 at 19.496000 - 15:44:49
Exiting

```
##### cdc_stress_test
```
c:\Python27\python.exe cdc_stress_test.py
Thread 0 on loop          0 at 0.090000 - 15:44:03 - port COM3
Thread 0 on loop         10 at 0.323000 - 15:44:03 - port COM3
Thread 0 on loop         20 at 0.541000 - 15:44:03 - port COM3
Thread 0 on loop         30 at 0.741000 - 15:44:03 - port COM3
Thread 0 on loop         40 at 0.948000 - 15:44:04 - port COM3
Thread 0 on loop         50 at 1.195000 - 15:44:04 - port COM3
Thread 0 on loop         60 at 1.468000 - 15:44:04 - port COM3
Thread 0 on loop         70 at 1.691000 - 15:44:04 - port COM3
Thread 0 on loop         80 at 1.915000 - 15:44:05 - port COM3
Thread 0 on loop         90 at 2.134000 - 15:44:05 - port COM3
Thread 0 on loop        100 at 2.360000 - 15:44:05 - port COM3
Thread 0 on loop        110 at 2.577000 - 15:44:05 - port COM3
Thread 0 on loop        120 at 2.800000 - 15:44:05 - port COM3
```

### Test on windows machine over windows USBIP server
Virtualhere server running on windows 10, virtualhere client on a windows 10. Connection over local network.

##### msd_remount_test
```
c:\Python27\python.exe msd_remount_test.py
Triggering remount for 0 F: - 0240000033514e450044500585d4000be981000097969900 at 0.119000 - 15:48:25
Drive F: dismount
Remount complete as F:
Triggering remount for 0 F: - 0240000033514e450044500585d4000be981000097969900 at 3.824000 - 15:48:29
Drive F: dismount
Remount complete as F:
Triggering remount for 0 F: - 0240000033514e450044500585d4000be981000097969900 at 7.357000 - 15:48:33
Drive F: dismount
Remount complete as F:
Triggering remount for 0 F: - 0240000033514e450044500585d4000be981000097969900 at 10.975000 - 15:48:36
Drive F: dismount
Remount complete as F:
Triggering remount for 0 F: - 0240000033514e450044500585d4000be981000097969900 at 14.671000 - 15:48:40
Drive F: dismount
Remount complete as F:
Triggering remount for 0 F: - 0240000033514e450044500585d4000be981000097969900 at 18.486000 - 15:48:44
Exiting
```
##### cdc_stress_test
```
c:\Python27\python.exe cdc_stress_test.py
Thread 0 on loop          0 at 0.134000 - 15:47:27 - port COM3
Thread 0 on loop         10 at 0.532000 - 15:47:27 - port COM3
Thread 0 on loop         20 at 0.897000 - 15:47:27 - port COM3
Thread 0 on loop         30 at 1.250000 - 15:47:28 - port COM3
Thread 0 on loop         40 at 1.621000 - 15:47:28 - port COM3
Thread 0 on loop         50 at 1.940000 - 15:47:28 - port COM3
Thread 0 on loop         60 at 2.284000 - 15:47:29 - port COM3
Thread 0 on loop         70 at 2.677000 - 15:47:29 - port COM3
Thread 0 on loop         80 at 3.084000 - 15:47:30 - port COM3
Thread 0 on loop         90 at 3.507000 - 15:47:30 - port COM3
Thread 0 on loop        100 at 3.913000 - 15:47:30 - port COM3
Thread 0 on loop        110 at 4.343000 - 15:47:31 - port COM3
Thread 0 on loop        120 at 4.751000 - 15:47:31 - port COM3
```
Same functionality over USBIP, a bit longer loading times as expected.

### Test on windows machine over NanoPi Neo USBIP server
Virtualhere server running on the masters usb port, virtualhere client on a windows 10. Connection over local network.

##### msd_remount_test
These are in a separate file called nanopineo-virtualhere-usbip.txt
The tests themselves varied quite a lot so I took them many times.
Unfortunately my version of armbian did not come with usbmon so I could not investigate the dodgy virtualhere connection.

##### cdc_stress_test
```
c:\Python27\python.exe cdc_stress_test.py
Thread 0 on loop          0 at 0.139000 - 16:02:39 - port COM3
Thread 0 on loop         10 at 0.735000 - 16:02:40 - port COM3
Thread 0 on loop         20 at 1.347000 - 16:02:40 - port COM3
Thread 0 on loop         30 at 1.995000 - 16:02:41 - port COM3
Thread 0 on loop         40 at 2.613000 - 16:02:42 - port COM3
Thread 0 on loop         50 at 3.322000 - 16:02:42 - port COM3
Thread 0 on loop         60 at 3.985000 - 16:02:43 - port COM3
Thread 0 on loop         70 at 4.700000 - 16:02:44 - port COM3
Thread 0 on loop         80 at 5.356000 - 16:02:44 - port COM3
Thread 0 on loop         90 at 6.052000 - 16:02:45 - port COM3
Thread 0 on loop        100 at 6.944000 - 16:02:46 - port COM3
Thread 0 on loop        110 at 7.793000 - 16:02:47 - port COM3
Thread 0 on loop        120 at 8.592000 - 16:02:47 - port COM3
```
### Test on linux machine over linux  server
Server running on nanopineo armbian, client on debian stretch. Connection over local network.

##### msd_remount_test
```
Triggering remount for 0 /media/samuli/DAPLINK - 0240000033514e450044500585d4000be981000097969900 at 0.010320 - 19:46:55
Drive /media/samuli/DAPLINK dismount
No handlers could be found for logger "mbedls.lstools_base"
Remount complete as /media/samuli/DAPLINK
Triggering remount for 0 /media/samuli/DAPLINK - 0240000033514e450044500585d4000be981000097969900 at 8.045644 - 19:47:03
Drive /media/samuli/DAPLINK dismount
Remount complete as /media/samuli/DAPLINK
Triggering remount for 0 /media/samuli/DAPLINK - 0240000033514e450044500585d4000be981000097969900 at 15.110410 - 19:47:10
Drive /media/samuli/DAPLINK dismount
Remount complete as /media/samuli/DAPLINK
Triggering remount for 0 /media/samuli/DAPLINK - 0240000033514e450044500585d4000be981000097969900 at 21.834280 - 19:47:16
Drive /media/samuli/DAPLINK dismount
Remount complete as /media/samuli/DAPLINK
Triggering remount for 0 /media/samuli/DAPLINK - 0240000033514e450044500585d4000be981000097969900 at 28.805145 - 19:47:23
Drive /media/samuli/DAPLINK dismount
Remount complete as /media/samuli/DAPLINK
Triggering remount for 0 /media/samuli/DAPLINK - 0240000033514e450044500585d4000be981000097969900 at 35.648887 - 19:47:30
Drive /media/samuli/DAPLINK dismount
Remount complete as /media/samuli/DAPLINK
Triggering remount for 0 /media/samuli/DAPLINK - 0240000033514e450044500585d4000be981000097969900 at 42.493699 - 19:47:37
Drive /media/samuli/DAPLINK dismount
```
Connection seems to be much more stable compared to windows side. No jumps in delay.

##### cdc_stress_test
```
Thread 0 on loop          0 at 0.033271 - 19:45:57 - port /dev/ttyACM0
Thread 0 on loop         10 at 0.328773 - 19:45:57 - port /dev/ttyACM0
Thread 0 on loop         20 at 0.597770 - 19:45:57 - port /dev/ttyACM0
Thread 0 on loop         30 at 0.859739 - 19:45:57 - port /dev/ttyACM0
Thread 0 on loop         40 at 1.124546 - 19:45:58 - port /dev/ttyACM0
Thread 0 on loop         50 at 1.387713 - 19:45:58 - port /dev/ttyACM0
Thread 0 on loop         60 at 1.649646 - 19:45:58 - port /dev/ttyACM0
Thread 0 on loop         70 at 1.917756 - 19:45:58 - port /dev/ttyACM0
Thread 0 on loop         80 at 2.179626 - 19:45:59 - port /dev/ttyACM0
Thread 0 on loop         90 at 2.446772 - 19:45:59 - port /dev/ttyACM0
Thread 0 on loop        100 at 2.710774 - 19:45:59 - port /dev/ttyACM0
Thread 0 on loop        110 at 3.010037 - 19:45:59 - port /dev/ttyACM0
Thread 0 on loop        120 at 3.331701 - 19:46:00 - port /dev/ttyACM0
```

## Linux builtin USBIP drivers

### Test on linux machine

##### msd_remount_test
```
Triggering remount for 0 /media/samuli/DAPLINK - 0240000033514e450044500585d4000be981000097969900 at 0.011876 - 19:34:28
Drive /media/samuli/DAPLINK dismount
No handlers could be found for logger "mbedls.lstools_base"
Remount complete as /media/samuli/DAPLINK
Triggering remount for 0 /media/samuli/DAPLINK - 0240000033514e450044500585d4000be981000097969900 at 7.245219 - 19:34:36
Drive /media/samuli/DAPLINK dismount
Remount complete as /media/samuli/DAPLINK
Triggering remount for 0 /media/samuli/DAPLINK - 0240000033514e450044500585d4000be981000097969900 at 13.720506 - 19:34:42
Drive /media/samuli/DAPLINK dismount
Remount complete as /media/samuli/DAPLINK
Triggering remount for 0 /media/samuli/DAPLINK - 0240000033514e450044500585d4000be981000097969900 at 20.231599 - 19:34:49
Drive /media/samuli/DAPLINK dismount
Remount complete as /media/samuli/DAPLINK
Triggering remount for 0 /media/samuli/DAPLINK - 0240000033514e450044500585d4000be981000097969900 at 26.663832 - 19:34:55
Drive /media/samuli/DAPLINK dismount
Remount complete as /media/samuli/DAPLINK
Triggering remount for 0 /media/samuli/DAPLINK - 0240000033514e450044500585d4000be981000097969900 at 33.093323 - 19:35:01
Drive /media/samuli/DAPLINK dismount
^CExiting
```
Have to remount the device everytime the tests dismounts it. This creates a bit of lag since I didn't get the automount to work properly.
##### cdc_stress_test
```
Thread 0 on loop          0 at 0.010331 - 19:16:26 - port /dev/ttyACM0
Thread 0 on loop         10 at 0.029908 - 19:16:26 - port /dev/ttyACM0
Thread 0 on loop         20 at 0.049909 - 19:16:26 - port /dev/ttyACM0
Thread 0 on loop         30 at 0.069871 - 19:16:26 - port /dev/ttyACM0
Thread 0 on loop         40 at 0.089967 - 19:16:26 - port /dev/ttyACM0
Thread 0 on loop         50 at 0.109921 - 19:16:26 - port /dev/ttyACM0
Thread 0 on loop         60 at 0.129886 - 19:16:26 - port /dev/ttyACM0
Thread 0 on loop         70 at 0.150006 - 19:16:26 - port /dev/ttyACM0
Thread 0 on loop         80 at 0.169914 - 19:16:26 - port /dev/ttyACM0
Thread 0 on loop         90 at 0.190008 - 19:16:26 - port /dev/ttyACM0
Thread 0 on loop        100 at 0.209860 - 19:16:26 - port /dev/ttyACM0
Thread 0 on loop        110 at 0.229958 - 19:16:26 - port /dev/ttyACM0
Thread 0 on loop        120 at 0.249887 - 19:16:26 - port /dev/ttyACM0
```
### Test on linux machine over linux  server
Server running on nanopineo armbian, client on debian stretch. Connection over local network.
Some issues with loading the daemon, the version is older than on newer kernels. Most likely due to that. There are some required modules completely missing.

# Roadblocks
We updated the master to a fresh armbian install with kernel version 4.11.2, as eBPF supports connections to traffic control classifiers. It resulted in a kernel error. Kernel error occurs on both mainline armbian and neo ubuntu xenial. We will have to see if kernel version 3.x is enough for the project.

Kernel error occurs when connecting to the board via SSH. The kernel dumb is attached in kernel-error-dump.txt

Further testing shows that the crash occurs when an SSH connection is made over the Usb-to-ethernet adapter, might be a driver issue.

Just-in-time compiling (JITting) can't be done on 32 bit ARM processor as it has only ARM64 support. This is just a performance increase with bigger eBpf programs.

3.18 kernel has the ebpf support with maps so making a filter that for example drops every packet is possible. However we found a module in iptables that allows us to do the same thing. You can do an iptables action to every nth packet using the statistics module. There is a working version of the tc version of the filter that requires 4.1 kernel. More info in load_bpf.sh.

Issues running the test at all on linux. Does not crash, but does not print anything.
```
No handlers could be found for logger "mbedls.platform_database"
No handlers could be found for logger "mbedls.lstool_base"
```
Solution was to mount the daplink drive manually.

# Useful resources
Well explained examples for various network tools in linux:
* http://lartc.org/howto/index.html
* http://lartc.org/howto/lartc.qdisc.filters.html

BPF samples
* https://github.com/torvalds/linux/tree/master/samples/bpf
* https://github.com/netoptimizer/prototype-kernel/tree/master/kernel/samples/bpf
* https://github.com/CumulusNetworks/iproute2/tree/master/examples/bpf
* https://github.com/idosch/iproute2/tree/master/examples/bpf
* https://elixir.bootlin.com/linux/v4.4.13/source/samples/bpf

Bpf features by linux kernel version
https://github.com/iovisor/bcc/blob/master/docs/kernel-versions.md

marking with ebtables example:
* http://ebtables.netfilter.org/examples/example5.html

A well written introduction to eBPF:
* https://ferrisellis.com/posts/ebpf_past_present_future/

network emulation qdisc:
* https://wiki.linuxfoundation.org/networking/netem

great image of linux network stack: iptables / ebtables
* https://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg

# Next step
* Do a netboot for the board so the image is centralized
* Emulate a gadget with gpio(usb) -> usb port of device
