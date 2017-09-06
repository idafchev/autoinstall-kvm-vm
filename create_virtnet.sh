#!/bin/sh

print_help(){
	echo -e "Usage: $0 -n netname -m netmode -a ipaddr -p prefix [-i iface] [-f dhcpstart] [-l dhcpend]\n"
	echo -e "  Mandatory:"
	echo -e "   -n\t\tNetwork name"
	echo -e "   -m\t\tNetwork mode. [route | nat | isolated]"
	echo -e "   -a\t\tFirst IP address from the network."
	echo -e "   -p\t\tNetwork prefix CIDR notation."
	echo -e "  Optional:"
	echo -e "   -i\t\tNetwork interface. Used in [route | nat] modes"
	echo -e "   -f\t\tFirst IP from the DHCP pool. If not supplied -> no DHCP."
	echo -e "   -l\t\tLast IP from the DHCP pool. If not supplied -> no DHCP."
	echo -e "   -h\t\tDisplay this help."
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

	if [[ "$network_name" == "" || "$network_mode" == "" || "$first_ip_address" == "" || "$network_prefix" == "" ]]; then
		print_error "[-] ERROR: Not enough arguments!"
		exit 1
	fi

	if [[ "$(virsh net-list --all --name | grep -w "${network_name}")" != "" ]]; then
		print_error "[-] ERROR: Network exists!"
		exit 2
	fi

	if [[ "$network_mode" != "route" && "$network_mode" != "nat" && "$network_mode" != "isolated" ]]; then
		print_error "[-] ERROR: $network_mode is not a valid network mode!"
		exit 1
	fi

	ipcalc -4 -c "$first_ip_address" &>/dev/null
	if [ $? -ne 0 ]; then
		print_error "[-] ERROR: $first_ip_address is not a valid ip address!"
		exit 1
	fi

	ipcalc -4 -m "$first_ip_address/$network_prefix"  &> /dev/null
	if [ $? != 0 ]; then
		print_error "[-] ERROR: $network_prefix is not a valid prefix!"
		exit 1
	fi

	if ! [ -e "/sys/class/net/$interface" ] && [[ "$network_mode" != "isolated" ]]; then
		print_error "[-] ERROR: $interface interface doesn't exist!"
		exit 1
	fi


	if [[ "$dhcp_first_ip" != "" || "$dhcp_last_ip" != "" ]]; then
		ipcalc -4 -c "$dhcp_first_ip" &> /dev/null
		if [ $? -ne 0 ]; then
			print_error "[-] ERROR: $dhcp_first_ip is not a valid ip address!"
		fi

		if [ "$(ipcalc -4 -n "$dhcp_first_ip/$network_prefix")" != "$(ipcalc -4 -n "$first_ip_address/$network_prefix")" ]; then
			print_error "[-] ERROR: $dhcp_first_ip address for DHCP is not in the valid network range for $first_ip_address/$network_prefix!"
			exit 1
		fi

		ipcalc -4 -c "$dhcp_last_ip" &> /dev/null
		if [ $? -ne 0 ]; then
			print_error "[-] ERROR: $dhcp_last_ip is not a valid ip address!"
			exit 1
		fi

		if [ "$(ipcalc -4 -n "$dhcp_last_ip/$network_prefix")" != "$(ipcalc -4 -n "$first_ip_address/$network_prefix")" ]; then
			print_error "[-] ERROR: $dhcp_last_ip address for DHCP is not in the valid network range for $first_ip_address/$network_prefix!"
			exit 1
		fi
	fi
	
}

while getopts ":n:m:a:p:i:f:l:h" opt; do
	case $opt in
		n)
			network_name=$OPTARG
			;;
		m)
			network_mode=$OPTARG
			;;
		a)
			first_ip_address=$OPTARG
			;;
		p)
			network_prefix=$OPTARG
			;;
		i)
			interface=$OPTARG
			;;
		f)
			dhcp_first_ip=$OPTARG
			;;
		l)
			dhcp_last_ip=$OPTARG
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

# Work directly on the copy of the template
su -c "cp -f 'virtnet_template.xml' 'virtnet.xml'" $SUDO_USER

network_mask=$(ipcalc -4 -m "$first_ip_address/$network_prefix" | cut -d= -f2 )

forward="  <forward dev='%interface%' mode='%netmode%'>\n%nat%\n    <interface dev='%interface%'/>\n  </forward>"
nat="    <nat>\n      <port start='1024' end='65535'/>\n    </nat>"
dhcp="    <dhcp>\n      <range start='%dhcpstart%' end='%dhcpend%'/>\n    </dhcp>"

case $network_mode in
	"route")
		nat=""
		forward=${forward//"%nat%"/$nat}
		forward=${forward//"%netmode%"/$network_mode}
		forward=${forward//"%interface%"/$interface}
		;;
	"nat")
		forward=${forward//"%nat%"/$nat}
		forward=${forward//"%netmode%"/$network_mode}
		forward=${forward//"%interface%"/$interface}
		;;
	"isolated")
		forward=""
		;;
esac

if [[ "$dhcp_first_ip" != "" ]]; then
	dhcp=${dhcp//"%dhcpstart%"/$dhcp_first_ip}
	dhcp=${dhcp//"%dhcpend%"/$dhcp_last_ip}
else 
	dhcp=""
fi

sed -i s/"%networkname%"/"$network_name"/g virtnet.xml
sed -i -e s@"%forward%"@"$forward"@g virtnet.xml
sed -i -e s@"%dhcp%"@"$dhcp"@g virtnet.xml
sed -i s/"%firstip%"/"$first_ip_address"/g virtnet.xml
sed -i s/"%netmask%"/"$network_mask"/g virtnet.xml

virsh net-define virtnet.xml
virsh net-autostart "$network_name"
virsh net-start "$network_name"

if [ $? -ne 0 ]; then
	virsh net-undefine "$network_name"
	print_error "[-] ERROR: Couldn't start network."
	exit 1
fi

exit 0
