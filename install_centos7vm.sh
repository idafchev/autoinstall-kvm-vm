#!/bin/sh

print_help(){
	echo -e "Usage: $0 -n vmname -m memory -d disk -s size -a ipaddr -g gwip -p prefix -k netname\n"
	echo -e "   -n\tThe VM name."
	echo -e "   -m\tRAM in megabytes."
	echo -e "   -d\tFull path (dir + filename) to the disk file."
	echo -e "   -s\tThe disk size in megabytes (if new file is created.)"
	echo -e "   -a\tThe VM static IP address."
	echo -e "   -g\tGateway IP address."
	echo -e "   -p\tNetwork prefix in CIDR notation."
	echo -e "   -k\tName of virtual network to create/attach."
	echo -e "   -h\tDisplay this help."
	exit 0
}

print_error(){
	echo -e "$1" >&2
	echo -e "Use -h for help." >&2
}

while getopts ":n:m:d:s:a:g:p:k:h" opt; do
	case $opt in
		n)
			vm_name=$OPTARG
			;;
		m)
			memory=$OPTARG
			;;
		d)
			disk_path=$OPTARG
			;;
		s)
			disk_size=$OPTARG
			;;
		a)
			vm_ip_address=$OPTARG
			;;
		g)
			vm_gateway_ip=$OPTARG
			;;
		p)
			vm_network_prefix=$OPTARG
			;;
		k)
			network_name=$OPTARG
			;;
		h)
			print_help
			;;
		\?)
 			echo "Invalid option: -$OPTARG" >&2
 			print_help
      		exit 1
			;;
		:)
      		echo "Option -$OPTARG requires an argument." >&2
      		print_help
      		exit 1
      		;;
	esac
done

if [ $OPTIND -eq 1 ]; then 
	echo "No options were passed!" >&2
   	print_help
   	exit 1
fi

if [[ "$(virsh net-list --all --name | grep -w "${network_name}")" != "" ]]; then
	echo "[+] Using existing network $network_name."

	vm_gateway_ip="$(virsh net-dumpxml ${network_name} | xmllint --xpath "string(//network/ip/@address)" -)"
	netmask="$(virsh net-dumpxml ${network_name} | xmllint --xpath "string(//network/ip/@netmask)" -)"

	vm_network_prefix="$(ipcalc -p $vm_gateway_ip $netmask | cut -d= -f2)"

	if [ "$(ipcalc -4 -n "$vm_ip_address/$vm_network_prefix")" != "$(ipcalc -4 -n "$vm_gateway_ip/$vm_network_prefix")" ]; then
		print_error "[-] ERROR: $vm_ip_address and $vm_gateway_ip! are not on the same network!"
		exit 1
	fi
else
	sh ./create_virtnet.sh -n "$network_name" -m "nat" -a "$vm_gateway_ip" -p "$vm_network_prefix" -i "wlp8s0"  -f "" -l "" 2>/dev/null
	if [ $exit_code -ne 0 ]; then
		print_error "[-] ERROR: Couldn't create network!."
		exit 1
	fi
fi

sh ./create_vm.sh -n $vm_name -t linux -v centos7.0 -m $memory -c 1 -d $disk_path \
	-s $disk_size -i "/home/iliya/Downloads/CentOS-7-x86_64-Minimal-1611.iso" \
	-a $vm_ip_address -g $vm_gateway_ip -p $vm_network_prefix -k $network_name 2>/dev/null

virsh start $vm_name
