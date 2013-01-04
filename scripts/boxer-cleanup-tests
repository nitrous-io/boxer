#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

name=${1}
lxc_root='/var/lib/lxc'
quoted_lxc_root='\/var\/lib\/lxc\/'
box_path=${lxc_root}/${name}

if [ -d ${box_path} ]; then
  echo 'Stopping the container'
  lxc-stop -n ${name}
  lxc-wait -n ${name} -s STOPPED

  if [[ `cat /proc/mounts | grep "${box_path}\>"` ]]; then
    echo 'Unmounting the container in cleanup tests'
    umount ${box_path}
    echo 'Removing line from /etc/fstab'
    sed -i "/${quoted_lxc_root}${name}\b/d" /etc/fstab
  fi

  if [ -f /etc/projects ]; then
    echo 'Removing line from /etc/projects'
    sed -i "/:${quoted_lxc_root}${name}_delta\b/d" /etc/projects
  fi

  if [ -f /etc/projid ]; then
    echo 'Removing line from /etc/projid'
    sed -i "/:${name}\b/d" /etc/projid
  fi

  echo 'Deleting all remnants of the container'
  rm -rf ${box_path}*

  echo 'Flushing IPTables'
  iptables -t nat -F
fi
