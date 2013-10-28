# Boxer

Boxer is a service which provisions boxes (LXC Containers) on action.io.
It listens for commands on a Redis Message Queue and performs the
requisite operations (provisioning, setting up iptables filters, IPs,
etc.) to setup a working dev environment


## Development

Boxer operations are quite destructive (since it removes iptables,
containers, cleans up redis, etc.) so it is better to work on boxer in a
separate environment than in your regular dev environment (which has the
Rails app, coach, etc. -- the one provided by dev-cookbook).

## Run Boxer Tests

* vagrant up (This will take a while since it downloads a fresh
  `precise` LXC container and puts it in your Vagrant VM).
* vagrant ssh
* cd boxer
* npm install
* export $(cat .env)
* make
