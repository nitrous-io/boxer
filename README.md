# Boxer

Boxer is a service which provisions boxes (LXC Containers) on action.io.
It listens for commands on a Redis Message Queue and performs the
requisite operations (provisioning, setting up iptables filters, IPs,
etc.) to setup a working dev environment

## Requirements for lvm

- a volume group named boxhost
- a thin pool named boxes

You can use the following steps to create the pool
```
pvcreate /dev/xvdg1 /dev/xvdg2
vgcreate boxhost /dev/xvdg1 /dev/xvdg2
lvcreate -L 30G --poolmetadatasize 4G --type thin-pool --thinpool boxes boxhost
```

## To Run Tests

If your box is provisioned with bombay ( which it should ) , then just run

- `./script/setup`

- change test environment in your `config/runtimes.coffee` to contain `test:
  "test_container_template"`. 

- `make`

- If test failed, check if there is any extra containers created by failed test
  before ( usually named mclovins-container-** ) and stop/delete those, you may
  make it pass by doing so.
