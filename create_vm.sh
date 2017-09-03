#!/bin/sh

create_new_disk(){
	if [ -f "$diskpath" ]; then
		echo -e "[-] ERROR: $diskpath already exists!" >&2
		exit 1
	fi

	qemu-img create -f qcow2 -o size="${disksize}G" "$diskpath"
	if [[ $? -ne 0 ]]; then
		echo -e "[-] ERROR: Could not create $diskpath !" >&2
		exit 1
	fi
}

use_existing_disk(){
	if ! [ -w "$diskpath" ]; then
		echo -e "[-] ERROR: $diskpath is not writable!" >&2
		exit 1
	fi
	# get the disk size in [G] (integer value)
	disksize="$(qemu-img info $diskpath  | grep virtual | awk -F' ' "{match(\$3,\"[0-9]\",a)} {print a[0]}")"
}

create_new_virtual_network(){
	if ! [ "$(virsh net-list --all --name | grep "${networkname}")" == "" ]; then
		echo -e "[-] ERROR: Network exists!" >&2
		if [[ "$newdisk" == "yes" ]]; then
			rm -f "$diskpath"
		fi
		exit 1
	fi

	forward="  <forward dev='%interface%' mode='%netmode%'>\n%nat%\n    <interface dev='%interface%'/>\n  </forward>"
	nat="    <nat>\n      <port start='1024' end='65535'/>\n    </nat>"
	dhcp="    <dhcp>\n      <range start='%dhcpstart%' end='%dhcpend%'/>\n    </dhcp>"
	
	case $netmode in
		"route")
			nat=""
			forward=${forward//"%nat%"/$nat}
			forward=${forward//"%netmode%"/$netmode}
			forward=${forward//"%interface%"/$interface}
			;;
		"nat")
			forward=${forward//"%nat%"/$nat}
			forward=${forward//"%netmode%"/$netmode}
			forward=${forward//"%interface%"/$interface}
			;;
		"isolated")
			forward=""
			;;
		*)
			echo -e "[-] ERROR: $netmode is invalid network mode!" >&2
			echo "Use 'create_vm.sh -h' for help..." 1>&2
			exit 1
			;;
	esac

	if [[ "$hasdhcp" == "yes" ]]; then
		dhcp=${dhcp//"%dhcpstart%"/$dhcpstart}
		dhcp=${dhcp//"%dhcpend%"/$dhcpend}
	elif [[ "$hasdhcp" == "no" ]]; then
		dhcp=""
	else
		echo -e "[-] ERROR: Choose yes or no for hasdhcp!" >&2
		echo "Use 'create_vm.sh -h' for help..." 1>&2
		exit 1
	fi

	sed -i s/"<vmip>"/"${vmip}"/g ks.cfg
	sed -i s/"<gatewayip>"/"${gatewayip}"/g ks.cfg
	sed -i s/"<netmask>"/"${netmask}"/g ks.cfg
	sed -i s/"<dnsip>"/"${dnsip}"/g ks.cfg

	sed -i s/"%networkname%"/"$networkname"/g virt_net.xml
	#sed -i s/"%interface%"/"$interface"/g virt_net.xml
	sed -i -e s@"%forward%"@"$forward"@g virt_net.xml
	#sed -i s/"%forwardmode%"/"route"/g virt_net.xml
	sed -i s/"%firstip%"/"$gatewayip"/g virt_net.xml
	sed -i s/"%netmask%"/"$netmask"/g virt_net.xml
	#sed -i s/"%startaddress%"/"$dhcpstart"/g virt_net.xml
	#sed -i s/"%endaddress%"/"$dhcpend"/g virt_net.xml
	sed -i -e s@"%dhcp%"@"$dhcp"@g virt_net.xml

	virsh net-define virt_net.xml
	virsh net-autostart "$networkname"
	virsh net-start "$networkname"
	
	if [ $? -ne 0 ]; then
		virsh net-undefine "$networkname"
		if [ "$newdisk" == "yes" ]; then
			rm -f "$diskpath"
		fi
		exit 1
	fi
}

use_existing_virtual_network(){
	if [ "$(virsh net-list --all --name | grep "${networkname}")" == "" ]; then
		echo -e "[-] ERROR: Network doesn't exist!" >&2
		echo "Use 'create_vm.sh -h' for help..." 1>&2
		return 1
	fi

	gatewayip="$(virsh net-dumpxml ${networkname} | xmllint --xpath "string(//network/ip/@address)" -)"
	netmask="$(virsh net-dumpxml ${networkname} | xmllint --xpath "string(//network/ip/@netmask)" -)"

	#dhcpstart="$(virsh net-dumpxml ${networkname} | xmllint --xpath "string(//network/ip/dhcp/range/@start)" -)"
	#dhcpend="$(virsh net-dumpxml ${networkname} | xmllint --xpath "string(//network/ip/dhcp/range/@end)" -)"

	#interface="$(virsh net-dumpxml ${networkname} | xmllint --xpath "string(//network/forward/@dev)" -)"
	#netmode="$(virsh net-dumpxml ${networkname} | xmllint --xpath "string(//network/forward/@mode)" -)"

	sed -i s/"<vmip>"/"${vmip}"/g ks.cfg
	sed -i s/"<gatewayip>"/"${gatewayip}"/g ks.cfg
	sed -i s/"<netmask>"/"${netmask}"/g ks.cfg
	sed -i s/"<dnsip>"/"${dnsip}"/g ks.cfg
}

install_vm(){
	virt-install \
		--connect qemu:///system \
		-n ${vmname} \
		--os-type=${ostype} \
		--os-variant=${osvariant} \
		--ram=${memory} \
		--vcpus=${vcpus} \
		--disk path=${diskpath},bus=virtio,size=${disksize},format="qcow2" \
		--nographics \
		--location="${installmedia}" \
		--network network=${networkname} \
		--noreboot --initrd-inject=ks.cfg \
		--extra-args="ks=file:/ks.cfg text console=tty0 utf8 console=ttyS0,115200"

	if [ $? -ne 0 ]; then
		if [[ "$newnetwork" == "yes" ]]; then
			virsh net-destroy "$networkname"
			virsh net-undefine "$networkname"
		fi

		if [[ "$newdisk" == "yes" ]]; then
			rm -f "$diskpath"
		fi
	fi
}

# usage:
# create_vm.sh vm_name os_type os_variant ram vcpus new_disk[yes|no] disk_path disk_size \
#              install_media new_network[yes|no] network_name vm_ip dns_ip netmode[isolated|route|nat] \ 
#              hasdhcp[yes|no] gatewayip netmask dhcp_start dhcp_end interface 


vmname="${1}"
ostype="${2}" # ex. Linux
osvariant="${3}" # ex. centos7.0
memory="${4}" # [M]
vcpus="${5}"
newdisk="${6}" #[yes|no]
diskpath="${7}"
disksize="${8}" # [G]
installmedia="${9}" # path to .iso file
newnetwork="${10}" #[yes|no]
networkname="${11}"
vmip="${12}"
dnsip="${13}"
#arguments below are needed only for new net
netmode="${14}" #[isolated|route|nat]
hasdhcp="${15}" #[yes|no]
gatewayip="${16}"
netmask="${17}"
dhcpstart="${18}"
dhcpend="${19}"
interface="${20}"

if [[ "$vmname" == "help" || "$vmname" == "-h" || "$vmname" == "--help" || "$vmname" == "" ]]; then
	echo -e "usage:"
	echo -e "create_vm.sh vm_name os_type os_variant ram vcpus new_disk[yes|no] \\"
	echo -e "             disk_path disk_size install_media new_network[yes|no] \\"
	echo -e "             network_name vm_ip dns_ip netmode[isolated|route|nat] \\"
	echo -e "             hasdhcp[yes|no] gatewayip netmask dhcp_start dhcp_end interface\n"
	exit 0
fi

if [ $(whoami) != root ]; then
	echo "[-] ERROR: The script must be run as root!" 1>&2
	exit 1
fi

if [[ "$newnetwork" == "yes" && $# -ne 20 ]]; then
	echo -e "[-] ERROR: To create new network you need to pass all 20 arguments!" >&2
	echo "Use 'create_vm.sh -h' for help..." 1>&2
	exit 1
elif [[ "$newnetwork" == "no" && $# -lt 13 ]]; then
	echo -e "[-] ERROR: To use existing network you need to pass at least 13 arguments!" >&2
	echo "Use 'create_vm.sh -h' for help..." 1>&2
	exit 1
fi

if ! [ -r "$installmedia" ]; then
	echo -e "[-] ERROR: Can't read $installmedia ! Doesn't exist or not enough permissions!" >&2
	exit 1
fi

kickstart="ks_template.cfg"
if ! [ -f $kickstart ]; then
	echo -e "[-] ERROR: No kickstart template file!" >&2
	exit 1
fi

cp -f "ks_template.cfg" "ks.cfg"

if ! [ -f "virt_networks_template.xml" ]; then
	echo -e "[-] ERROR: No virtual network template file!" >&2
	exit 1
fi

cp -f virt_networks_template.xml virt_net.xml

if [[ "$newdisk" == "yes" ]]; then
	create_new_disk
elif [[ "$newdisk" == "no" ]]; then
	use_existing_disk
else
	echo -e "[-] ERROR: Invalid value for new_disk! Choose 'yes' or 'no'!" >&2
	echo "Use 'create_vm.sh -h' for help..." 1>&2
	exit 1
fi

if [[ "$newnetwork" == "yes" ]]; then
	create_new_virtual_network
elif [[ "$newnetwork" == "no" ]]; then
	use_existing_virtual_network
else
	echo -e "[-] ERROR: Invalid value for new_network! Choose 'yes' or 'no'!" >&2
	echo "Use 'create_vm.sh -h' for help..." 1>&2
	exit 1
fi

install_vm

