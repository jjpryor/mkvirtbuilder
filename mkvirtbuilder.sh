#!/bin/bash
# This script is a wrapper around the process to make a 'golden image VM' as a
# template for virt-builder, which builds out new VMs images from that template.
BOLD='\033[1;1m'  ; B() { printf "%s" "${BOLD}"; }
RESET='\033[0;0m' ; R() { printf "%s" "${RESET}"; }
prog_name="mkvirtbuilder-template"
show_usage() {
    echo -e "=> ${BOLD}Usage: ${prog_name} Kickstart_file Blank_QCOW2_image_file${RESET}"
    echo "=> ${prog_name} requires exactly two arguments:"
    echo "=>   A Kickstart automated install file to install RHEL 7.3 Server"
    echo "=>   A newly created blank QCOW2 image file sized at 10GB"
    echo "=> ${prog_name} is a wrapper around the process to make a 'golden image VM' as a"
    echo "=> template for virt-builder, which builds out new VMs images from that template."
}
if [[ $# -eq 0 ]] || [[ $# -gt 2  ]];
then
	echo -e "=> ${BOLD}Error${RESET}: not enough or too many arguments."
	show_usage
	exit 1
fi
if [[ -f $1 ]] && [[ "$1" != "" ]];
then
#	echo "First arg $1 exists and is a file." > /dev/null
	Kickstart_file=$1
else
	echo -e "=> ${BOLD}Error${RESET}: first argument must be file that exists"
	show_usage
	exit 1
fi
if [[ -f $2 ]] && [[ "$2" != "" ]];
then
#	echo "Second arg $2 exists and is a file." > /dev/null
	Blank_QCOW2_image_file=$2
else
	echo -e "=> ${BOLD}Error${RESET}: second argument must be Blank_QCOW2_image_file of 10GB"
	echo "=>   To create a QCOW2 file: qemu-img create -f qcow2 Blank_QCOW2_image_file 10G"
	show_usage
	exit 1
fi
# tie the libvirt domain name (VM name) that we are building to the image file
filename=$(basename "${Blank_QCOW2_image_file}")
# this hacks off the .qcow.2 extension
extension="${filename##*.}"
base_filename="${filename%.*}"
#Now name the VM
libvirt_domain="VM-${base_filename}"
if [[ -f "${Blank_QCOW2_image_file}.xz" ]];
then
    echo -e "=> ${BOLD}Error${RESET}: Found existing XZ compressed image file named ${Blank_QCOW2_image_file}.xz in"
    echo "=> present directory. This script will not overwrite it in case it is important."
    exit 1
fi
check_libvirt_domain_exists() {
    virsh list --all | grep -q "${libvirt_domain}"
    libvirt_domain_exists=$?
    if [[ $libvirt_domain_exists -eq 0 ]] ;
    then
        echo -e "=> ${BOLD}Error${RESET}: libvirt domain ${libvirt_domain} already exists and might be running."
        echo "=>   ${prog_name} creates a temporary libvirt domain (a VM) named ${libvirt_domain} and can not overwrite it."
        echo "=>   Run: 'virsh list --all' to see domains and/or 'virsh undefine ${libvirt_domain}' to remove it."
        exit 1
    fi
}
check_libvirt_domain_exists
tree="repo_url"

echo "=> Using defaults of ..."
echo "=>   OS install tree: ${tree}"
echo "=> With command line supplied ..."
echo "=>   Kickstart file: ${Kickstart_file}"
echo "=>   Blank 10GB QCOW2 image file: ${Blank_QCOW2_image_file}"
echo "=> The virt-install task creates a temporary libvirt domain (aka VM) named ${libvirt_domain}"
echo -e "${BOLD}=> Running task virt-install in 10 seconds. Use keys <CTRL-C> now to cancel installation"
echo -e "${BOLD}=>   before it begins. The only way to cancel it after it begins is to use keys"
echo -e "${BOLD}=>   <CTRL-]> to escape out of the virtual console.${RESET}"
echo "=>"
sleep 10


virt-install --connect=qemu:///system \
    --network=bridge:virbr0 \
    --initrd-inject=./"${Kickstart_file}" \
    --extra-args="ks=file:/${Kickstart_file} no_timer_check console=tty0 console=ttyS0,115200 net.ifnames=0 biosdevname=0" \
    --name="${libvirt_domain}" \
    --disk ./"${Blank_QCOW2_image_file}",size=10,bus=virtio \
    --ram 1024 \
    --vcpus=2 \
    --cpu host-model-only \
    --virt-type kvm \
    --location=${tree} \
    --os-variant=rhel7.2 \
    --graphics none \
    --noreboot #--debug
virtinstall_return=$?

if [[ $virtinstall_return -gt 0 ]] ;
then
    echo -e "=> ${BOLD}Error${RESET}: task virt-install did not complete successfully."
    echo "=>   Perhaps a problem with the Kickstart_file, Blank_QCOW2_image_file, or"
    echo "=>   with virt-install and libvirt. Check console output."
    check_libvirt_domain_exists
    exit 1
fi
if [[ $virtinstall_return -eq 0 ]] ;
then
    echo "=> Task virt-install completed and shutdown the libvirt domain ${libvirt_domain}."
    echo "=> Running task virt-sparsify on ${Blank_QCOW2_image_file} to reclaim empty disk-space."
fi
if [ ! -d tmp ]; then
	mkdir tmp
fi

LIBGUESTFS_BACKEND=direct virt-sparsify --compress --tmp ./tmp/ "${Blank_QCOW2_image_file}" "sparsified-${Blank_QCOW2_image_file}"
mv "sparsified-${Blank_QCOW2_image_file}" tmp/"${Blank_QCOW2_image_file}"
echo "=> Compressing sparsified-${Blank_QCOW2_image_file} with XZ to ${Blank_QCOW2_image_file}.xz."
echo "=> This may take a few minutes ..."
xz -T 2 -0 -zv tmp/"${Blank_QCOW2_image_file}"
mv tmp/"${Blank_QCOW2_image_file}.xz" ./
echo "=>"
echo "=> Success."
echo "=> The file ${Blank_QCOW2_image_file}.xz is XZ compressed and is the QCOW2 image VM template"
echo "=> for virt-builder to consume and make new VMs"
echo "=>"
echo -n "=>      Size of ${Blank_QCOW2_image_file}.xz: " ; stat --printf="%s" "${Blank_QCOW2_image_file}.xz" ; echo -e ""
echo -n "=>      SHA512 checksum of ${Blank_QCOW2_image_file}.xz: " ; sha512sum "${Blank_QCOW2_image_file}.xz" | cut -d' ' -f1
echo "=>"
echo "=>"
echo "=> The file ${Blank_QCOW2_image_file} is the resulting VM image file for libvirt"
echo "=> domain ${libvirt_domain} which can be tested to see if the virt-install and"
echo "=> kickstart behaved as intended."
echo "=>       To test, run 'virsh start ${libvirt_domain}', then"
echo "=>       run 'virsh console ${libvirt_domain}'"
echo "=>       Use <CTRL-]> to escape out of the VM console."
echo "=>"
echo "=> If you don't want to test ${Blank_QCOW2_image_file} image file, then we can"
echo "=> undefine (remove) the libvirt domain, via 'virsh undefine ${libvirt_domain}'"
echo "=> and also delete the leftover ${Blank_QCOW2_image_file}"
echo "=>"
echo -e "=> ${BOLD}Undefine libvirt domain ${libvirt_domain}${RESET}"
echo -ne "=> ${BOLD}(y/n): ${RESET}"
read yesno
if [ "$yesno" == "y" ] || [ "$yesno" == "Y" ] ;
then
	echo "=> OK, running: virsh undefine ${libvirt_domain}"
	virsh undefine "${libvirt_domain}"
    echo -e "=> ${BOLD}Delete file ${Blank_QCOW2_image_file}?${RESET}"
    echo -ne "=> ${BOLD}(y/n): ${RESET}"
    read yesno
    if [ "$yesno" == "y" ] || [ "$yesno" == "Y" ] ;
    then
    	echo "=> OK, deleting ${Blank_QCOW2_image_file}"
    	/bin/rm -f "${Blank_QCOW2_image_file}"
    else
    	echo "=> Didn't enter 'Y', so not cleaning up and leaving it alone."
    fi
else
	echo "=> Didn't enter 'Y', so not cleaning up and leaving it alone."
fi
