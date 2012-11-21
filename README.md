# Boxer

Boxer is a service which provisions boxes (LXC Containers) on action.io.
It listens for commands on a Redis Message Queue and performs the
requisite operations (provisioning, setting up iptables filters, IPs,
etc.) to setup a working dev environment

## To Run Tests

There will be a task which does this automatically, but in the meantime
perform these steps (on an Ubuntu 12.04 machine)

- Install lxc and bridge-utils

`sudo apt-get install lxc bridge-utils`

- Add a bridge network to your network config

```
auto br-lxc
iface br-lxc inet static
    address 192.168.254.1
    netmask 255.255.255.0

    post-up echo 1 > /proc/sys/net/ipv4/ip_forward
    post-up iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    pre-down echo 0 > /proc/sys/net/ipv4/ip_forward
    pre-down iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

    bridge_ports none
    bridge_stp off 
```

- Bring up your bridge network interface

`sudo ifup br-lxc` 

- Check if it is indeed up

`sudo ifconfig br-lxc`

- Install an LXC container called `test-container-template` by running
  `script/setup`

`./script/setup`

- Install redis-server

`sudo apt-get install redis-server`

Run redis-server with the default configuration (if you change the port, make sure you change it in the config file in boxer as well)

9. Run tests


`make`


