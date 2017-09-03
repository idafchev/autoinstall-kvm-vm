#!/bin/sh

sh ./create_vm.sh $1 Linux centos7.0 1024 1 yes /media/windows_d_drive/Programs/Linux/kvm_vms/${1}.qcow2 2 "/media/windows_d_drive/ISOs and VMs/CentOS-7-x86_64-Minimal-1511.iso" yes "${1}Net" $2 $3 route no $3 $4 192.168.0.200 192.168.0.210 wlp8s0
