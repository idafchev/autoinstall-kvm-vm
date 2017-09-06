#!/bin/sh

print_help(){
	echo -e "Usage: $0 -t template -n vmname -k netname -m netmode -a ipaddr -g gwip -p prefix -i iface\n"
	echo -e "   -t\tName of the template VM."
	echo -e "   -n\tName of the new VM."
	#echo -e "   -s\tVM size [G]"
	echo -e "   -k\tName of the virtual network to create/attach."
	echo -e "   -m\tNetwork mode [nat | route | isolated]"
	echo -e "   -a\tIP address of the VM."
	echo -e "   -g\tGateway IP."
	echo -e "   -p\tVirtual network prefix in CIDR notation."
	echo -e "   -i\tNetwork interface."
	echo -e "   -h\tDisplay this help."
	exit 0
}

print_error(){
	echo -e "$1" >&2
	echo -e "Use -h for help." >&2
}

while getopts ":t:n:k:m:a:g:p:i:s:h" opt; do
	case $opt in
		t)
			vm_template=$OPTARG
			;;
		n)
			vm_name=$OPTARG
			;;
		#s)
		#	vm_size=$OPTARG
		#	;;
		k)
			network_name=$OPTARG
			;;
		m)
			network_mode=$OPTARG
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
		i)
			interface=$OPTARG
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
	sh ./create_virtnet.sh -n "$network_name" -m "$network_mode" -a "$vm_gateway_ip" -p "$vm_network_prefix" -i "$interface"  -f "" -l "" 2>/dev/null
	if [ $exit_code -ne 0 ]; then
		print_error "[-] ERROR: Couldn't create network!."
		exit 1
	fi
fi

#template_size=$(virt-df -h $template | grep $template | awk '{print $2}' | cut -dG -f1)
#if [[ $vm_size > $(echo "$template_size + 0.1" | bc) ]]; then
#	qemu-img create -f qcow2 -o size="2G" kkkkk
#	virt-resize --expand /dev/sda1 basevm-new.qcow2 resize
#fi


virt-clone --connect qemu:///system --original "$vm_template" --name "$vm_name" --file "/media/windows_d_drive/Programs/Linux/kvm_vms/$vm_name"

virsh detach-interface "$vm_name" network --config
virsh attach-interface "$vm_name" network "$network_name" --config --model virtio

virt-sysprep -d $vm_name \
	--operations defaults \
	--firstboot-command 'echo "HWADDR=$(cat /sys/class/net/eth0/address)" >>  /etc/sysconfig/network-scripts/ifcfg-eth0' \
	--firstboot-command "sed -i s/\"192.168.122.1\"/\"$vm_gateway_ip\"/g /etc/sysconfig/network-scripts/ifcfg-eth0" \
	--firstboot-command "sed -i s/\"192.168.122.100\"/\"$vm_ip_address\"/g /etc/sysconfig/network-scripts/ifcfg-eth0" \
	--firstboot-command "sed -i s/\"PREFIX=24\"/\"PREFIX=$vm_network_prefix\"/g /etc/sysconfig/network-scripts/ifcfg-eth0" \
	--network \
	--ssh-inject iliya:file:/home/iliya/.ssh/id_rsa.pub \
	--update \
	--selinux-relabel \
	--ssh-inject iliya:file:/home/iliya/.ssh/id_rsa.pub

virsh start "$vm_name"
	
