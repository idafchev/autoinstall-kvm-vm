#!/bin/sh

print_help(){
	echo -e "Usage: $0 -n vmname -t ostype -v osvariant -m memory -c vcpus \
			-d diskpath -s disksize [-o] -i isofile -a ipaddr -g gwip -p prefix -k virtnet\n"
	echo -e "   -n\tThe VM name."
	echo -e "   -t\tOS type [linux | unix | windows]"
	echo -e "   -v\tOS variant. Run 'osinfo-query os' for list of variants."
	echo -e "   -m\tRAM in megabytes."
	echo -e "   -c\tNumber of vCPUs."
	echo -e "   -d\tFull path (dir + filename) to the disk file."
	echo -e "     \tTo install on already existing file supply the '-o' switch."
	echo -e "     \tIf it doesn't exist, it'll be created."
	echo -e "     \tOnly qcow2 files are supported!"
	echo -e "   -s\tThe disk size in megabytes (if new file is created.)"
	echo -e "   -o\tOverwrite an existing disk file."
	echo -e "   -i\tFull path to the .iso file."
	echo -e "   -a\tThe VM static IP address."
	echo -e "   -g\tGateway IP address."
	echo -e "   -p\tNetwork prefix in CIDR notation."
	echo -e "   -k\tThe virtual network to attach."
	echo -e "   -h\tDisplay this help."
	exit 0
}

print_error(){
	echo -e "$1" >&2
	echo -e "Use -h for help." >&2
}

validate_options(){
	if [[ "$(whoami)" != "root" ]]; then
		print_error "[-] ERROR: The script must be run as root!"
		exit 1
	fi

	if [[ "$vm_name" == "" || "$os_type" == "" || "$os_variant" == "" || "$memory" == "" \
	 || "$vcpus" == "" || "$disk_path" == "" || "$installation_media" == "" \
	 || "$vm_ip_address" == "" || "$vm_gateway_ip" == "" || "$vm_network_prefix" == "" \
	 || "$network_name" == "" ]]; then
		print_error "[-] ERROR: Not enough arguments!"
		exit 1
	fi

	shopt -s nocasematch
	if [[ "$os_type" != "windows" && "$os_type" != "linux" && "os_type" != "unix" ]]; then
		print_error "[-] ERROR: $os_type is not supported!"
		shopt -u nocasematch
		exit 1
	fi
	shopt -u nocasematch

	if [[ "$(osinfo-query os -f short-id | cut -d' ' -f2 | grep -x "$os_variant")" == "" ]]; then
		print_error "[-] ERROR: $os_variant is not a valid os variant! Check 'osinfo-query os' for supported variants."
		exit 1
	fi

	if [[ $memory -lt 256  ]]; then
		print_error "[-] ERROR: Allocate at least 256 megabytes of memory!"
		exit 1
	elif [[ $memory -gt $(free -tm | grep "Mem" | awk '{print $2}') ]]; then
		print_error "[-] ERROR: You allocate more memory than the host system has!"
		exit 1
	fi

	if [[ $vcpus -gt 8 || $vcpus -lt 1 ]]; then
		print_error "[-] ERROR: $vcpus is not a valid number of vCPUs!"
		exit 1
	fi

	if [ -f "$disk_path" ] && [[ $overwrite == "" ]]; then
		print_error "[-] ERROR: File $disk_path already exists! To overwrite it use -o switch."
		exit 1
	elif [ -f "$disk_path" ] && [[ "$(file -b $disk_path | grep -w "QCOW")" == "" ]]; then
		print_error "[-] ERROR: The disk should be qcow2 file!"
		exit 1
	fi

	if ! [ -d "$(dirname "$disk_path")" ]; then
		print_error "[-] ERROR: Directory '$(dirname "$disk_path")' doesn't exist!"
		exit 1
	fi

	if [[ $overwrite == "" && $disk_size == "" ]]; then
		print_error "[-] ERROR: You didn't specify disk size!"
		exit 1
	elif [[ $overwrite == "" && $disk_size -lt 2000 ]]; then
		print_error "[-] ERROR: Disk size must be at least 2000 megabytes!"
		exit 1
	fi

	if ! [ -f "$installation_media" ]; then
		print_error "[-] ERROR: Installation media '$installation_media' doesn't exist!"
		exit 1
	elif [[ "$(file -b "$installation_media" | grep -w "ISO")" == "" ]]; then
		print_error "[-] ERROR: Installation media must be an .iso file!"
		exit 1
	fi

	ipcalc -4 -c "$vm_ip_address" &> /dev/null
	if [ $? -ne 0 ]; then
		print_error "[-] ERROR: $vm_ip_address is not a valid ip address!"
		exit 1
	fi

	ipcalc -4 -c "$vm_gateway_ip" &> /dev/null
	if [ $? -ne 0 ]; then
		print_error "[-] ERROR: $vm_gateway_ip is not a valid ip address!"
		exit 1
	fi

	ipcalc -4 -m "$vm_ip_address/$vm_network_prefix"  &> /dev/null
	if [ $? != 0 ]; then
		print_error "[-] ERROR: $vm_network_prefix is not a valid prefix!"
		exit 1
	fi

	if [ "$(ipcalc -4 -n "$vm_ip_address/$vm_network_prefix")" != "$(ipcalc -4 -n "$vm_gateway_ip/$vm_network_prefix")" ]; then
		print_error "[-] ERROR: $vm_ip_address and $vm_gateway_ip! are not on the same network!"
		exit 1
	fi

	if [[ "$(virsh net-list --all --name | grep -w "${network_name}")" == "" ]]; then
		print_error "[-] ERROR: Network doesn't exist!"
		exit 1
	fi

}

while getopts ":n:t:v:m:c:d:s:oi:a:g:p:k:h" opt; do
	case $opt in
		n)
			vm_name=$OPTARG
			;;
		t)
			os_type=$OPTARG
			;;
		v)
			os_variant=$OPTARG
			;;
		m)
			memory=$OPTARG
			;;
		c)
			vcpus=$OPTARG
			;;
		d)
			disk_path=$OPTARG
			;;
		s)
			disk_size=$OPTARG
			;;
		o)
			overwrite=1
			;;
		i)
			installation_media=$OPTARG
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

validate_options

kickstart="ks_template.cfg"
if ! [ -f $kickstart ]; then
	print_error "[-] ERROR: No kickstart template file!"
	exit 1
fi

# copy the file as the current user and NOT root
su -c "cp -f 'ks_template.cfg' 'ks.cfg'" $SUDO_USER

# Overwrite is NOT set only when new file is created
if [[ "$overwrite" == "" ]]; then
	qemu-img create -f qcow2 -o size="${disk_size}M" "$disk_path"
	if [[ $? -ne 0 ]]; then
		print_error "[-] ERROR: Could not create $disk_path !"
		exit 1
	fi
fi

network_mask=$(ipcalc -4 -m "$vm_ip_address/$vm_network_prefix" | cut -d= -f2 )

sed -i s/"<vmip>"/"${vm_ip_address}"/g ks.cfg
sed -i s/"<gatewayip>"/"${vm_gateway_ip}"/g ks.cfg
sed -i s/"<netmask>"/"${network_mask}"/g ks.cfg
sed -i s/"<dnsip>"/"${vm_gateway_ip}"/g ks.cfg

virt-install \
	--connect qemu:///system \
	-n ${vm_name} \
	--os-type=${os_type} \
	--os-variant=${os_variant} \
	--ram=${memory} \
	--vcpus=${vcpus} \
	--disk path=${disk_path},bus=virtio,format="qcow2" \
	--nographics \
	--network network=${network_name} \
	--location="${installation_media}" \
	--noreboot --initrd-inject=ks.cfg \
	--extra-args="ks=file:/ks.cfg text console=tty0 utf8 console=ttyS0,115200"

if [ $? -ne 0 ]; then
	# Overwrite is NOT set only when new file is created
	# On fail to install clean up the created file
	if [[ "$overwrite" == "" ]]; then
		rm -f "$disk_path"
	fi
	exit 1
fi

exit 0
