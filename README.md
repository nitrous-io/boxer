# Boxer

Boxer is a service which provisions boxes (LXC Containers) on action.io.
It listens for commands on a Redis Message Queue and performs the
requisite operations (provisioning, setting up iptables filters, IPs,
etc.) to setup a working dev environment

## To Run Tests

There will be a task which does this automatically, but in the meantime
perform these steps (on an Ubuntu 12.04 machine)

1. sudo apt-get install lxc bridge-utils
2. Add a bridge network to your network config

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

3. Bring up your bridge network interface

sudo ifup br-lxc

4. Check if it is indeed up

sudo ifconfig br-lxc

5. Install an LXC container called ```test-container-template```

lxc-create -n test-container-template -t ubuntu -f
/root/lxc/default.conf -- -r precise

This will take a while.

6. Once this is complete, you should see a container in
   /var/lib/lxc/test-container-template (this will be used as the
template for all the test containers created in the test suite)

7. Install redis-server

sudo apt-get install redis-server

8. Run redis-server with the default configuration (if you change the
   port, make sure you change it in the config file in boxer as well)

9. Run tests

make


