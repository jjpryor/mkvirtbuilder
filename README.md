# Overview
The goal is to build a VM template of RHEL 7.3 Server using pure libvirt that can
then be consumed by virt-builder to make derivative transient VMs. A pure libvirt
environment offers a suite of tools for virtual machine lifecycle management like
virt-install, virt-manager, virt-viewer, qemu, kvm, qemu-img, and virsh. Or it can
be managed more easily with virt-builder, upvm, and valine.

# Overview of `mkvirtbuilder.sh` script
`mkvirtbuilder.sh` is a bash script wrapper around the process to make a 'golden image VM' as a
template for `virt-builder`, which builds out new VMs images from that template.

This README documents how the entire process from a blank QCOW2 image file and Kickstart file,
to a VM template, all the way to making derivative VMs from the VM template.

# Hardware Requirements for making template VMs
+ virtualization host capable of running VMs
+ If virtualization host is remote, then access via SSH. No need for X11 or GUI.

# Software Requirements for making template VMs
+ tested on RHEL7.3 and Fedora 25
+ Working KVM / Libvirt subsystems
+ Additional RPMs required and available in base OS repo:
  - qemu-img
  - qemu-kvm-tools
  - libguestfs
  - libguestfs-tools
  - libguestfs-tools-c
  - libguestfs-xfs
  - virt-install
  - virt-manager
  - virt-builder

+ Optional tools that are nice to have.
 - [upvm on github.com](https://github.com/ryran/upvm)
 - [valine on github.com](https://github.com/ryran/valine)

# Assumptions
+ At present `mkvirtbuilder.sh` assumes RHEL 7.3 as the desired OS to be installed.
+ There is no Kickstart file-syntax checking performed on the Kickstart file, and is expected that the kickstart file is syntactically correct.
+ There is no QCOW2 inspection performed on the QCOW2 image file, it is expected that the image file is 10GB and is blank.

# Usage
## Edit `do_vars.sh` to input the install repo, then run `mkvirtbuilder.sh` script
`do_vars.sh` will find the repo_url in the kickstart file and the script uses `sed` with regex, so remember to throw a backslash `\\` in front of every forwardslash `/` 
```
vim do_vars.sh
./do_vars.sh
```

## Run `mkvirtbuilder.sh` script
git clone this repo and run `mkvirtbuilder.sh` script
`./mkvirtbuilder.sh Kickstart_file Blank_QCOW2_image_file`

The script `mkvirtbuilder.sh` requires exactly two arguments:
+ A Kickstart automated install file to install RHEL 7.3 Server
+ A newly created blank QCOW2 image file sized at 10GB

It will then launch `virt-install` to install RHEL 7.3 via the Kickstart file.
Once complete it will run `virt-sparsify` on the QCOW2 image file to reclaim empty disk-space,
XZ compresses the image file, and prints out the SHA512 checksum of the XZ file & the size of the file.

The entire process takes between 7 to 12 minutes.

The size and checksum are used to fill-out the `index.fragment`, which is used to populate
a `virt-builer` style `index` file.


## Create a virt-builder `index` and repo file
A virt-builder `index` describes the VM image and tells `virt-builder` how to manipulate the image
as a golden image from which you can make derivative VMs.

For now create a local filesystem place to store the VM template XZ compressed image file and the `index` file. Then copy the
XZ compressed image and the `index` file fragment (renamed to `index`) into that place. Edit a `virt-builder` repo file
which will point to the `index`. Fill in the index file with the SHA512 checksum and the size of the XZ compressed image file.

If the later steps of running virt-builder are successful, then you can copy that VM template XZ compressed image file and the `index` file off to some remote http/https server.
```
[root@localhost mkvirtbuilder.sh]# mkdir /var/lib/libvirt/images/virt-builder-templates
[root@localhost mkvirtbuilder.sh]# cp rhel-7.3-server.qcow2.xz ../virt-builder-templates/
[root@localhost mkvirtbuilder.sh]# cp rhel-7.3-index.fragment ../virt-builder-templates/index
[root@localhost mkvirtbuilder.sh]# vim /etc/xdg/virt-builder/repos.d/local.conf
[root@localhost virt-builder-templates]# cat /etc/xdg/virt-builder/repos.d/local.conf
[local]
uri=file:///var/lib/libvirt/images/virt-builder-templates/index
[root@localhost mkvirtbuilder.sh]# cd ../virt-builder-templates/
[root@localhost virt-builder-templates]# sha512sum rhel-7.3-server.qcow2.xz
cd37b3b559675351f48d91593138e99569ae8ae63d9939006d4eba5fbcf7ac4ad5f659d67bcfcd0b6a62f780213de940eda7f9a052ad53de84c87b6fb35073b6  rhel-7.3-server.qcow2.xz
[root@localhost virt-builder-templates]# stat --printf="%s\n" rhel-7.3-server.qcow2.xz
548788792
```

Then run `virt-builder -l` to have virt-builder list the VM templates it can access.
```
[root@localhost virt-builder-templates]# virt-builder -l
my-rhel-7.3              x86_64     My RHEL 7.3 Server x86-64
fedora-24                aarch64    Fedora® 24 Server (aarch64)
fedora-24                armv7l     Fedora® 24 Server (armv7l)
<trimmed for length>
```


## Test Method 1: virt-builder to build image from template. Then virt-install to create derivative VM.
Due to KVM & Qemu permissions, you must change directory to `/var/lib/libvirt/images/`.
Then run `virt-builder` against our template and create derivative VM image file.
```
[root@localhost virt-builder-templates]# cd /var/lib/libvirt/images/
[root@localhost images]# virt-builder my-rhel-7.3 --hostname actual-rhel-73.example.local \
                         -o actual-rhel-73.qcow2 --format qcow2 --size 50G
[   2.6] Downloading: file:///var/lib/libvirt/images/virt-builder-templates/rhel-7.3-server.qcow2.xz
[   3.8] Planning how to build this image
[   3.8] Uncompressing
[  13.6] Resizing (using virt-resize) to expand the disk to 50.0G
[  50.5] Opening the new disk
[  52.2] Setting a random seed
[  52.2] Setting the hostname: actual-rhel-73.example.local
[  52.2] Setting passwords
virt-builder: Setting random password of root to AnoWNQK6Dv9X4cqR
[  53.2] Finishing off
                   Output file: actual-rhel-73.qcow2
                   Output size: 50.0G
                 Output format: qcow2
            Total usable space: 9.0G
                    Free space: 7.7G (85%)
[root@localhost images]# ls
actual-rhel-73.qcow2  mkvirtbuilder.sh/  virt-builder-templates/
[root@localhost images]# ls -lh actual-rhel-73.qcow2
-rw-r--r--. 1 root root 51G Mar 13 16:38 actual-rhel-73.qcow2
[root@localhost images]# du -h actual-rhel-73.qcow2
1.4G    actual-rhel-73.qcow2
[root@localhost images]#
```
Note that the output file is a QCOW2 sparse file with total size of 50GB but only takes up 1.4GB on disk.

Now use virt-install to run the VM image as a real VM named `actual-rhel-73.example.local`
```
[root@localhost images]# virt-install --connect=qemu:///system \
    --network=bridge:virbr0 \
    --name=actual-rhel-73.example.local \
    --disk /var/lib/libvirt/images/actual-rhel-73.qcow2,size=50,bus=virtio \
    --ram 2048 \
    --vcpus=4 \
    --virt-type kvm \
    --os-variant=rhel7.2 \
    --graphics none \
    --import
```

And it will immediately start up the VM and connect to the console. Use `<CTRL-]>` to escape the console.
```
[  OK  ] Started Command Scheduler.
         Starting Command Scheduler...
[  OK  ] Started Job spooling tools.
         Starting Job spooling tools...
         Starting Wait for Plymouth Boot Screen to Quit...
[  OK  ] Started Login Service.
[   12.952088] ip6_tables: (C) 2000-2006 Netfilter Core Team
[   12.981088] Ebtables v2.0 registered
[   13.003087] IPv6: ADDRCONF(NETDEV_UP): eth0: link is not ready
[   13.151040] nf_conntrack version 0.5.0 (16384 buckets, 65536 max)
[   13.214089] Netfilter messages via NETLINK v0.30.
[   13.216089] ip_set: protocol 6

Red Hat Enterprise Linux Server 7.3 (Maipo)
Kernel 3.10.0-514.el7.x86_64 on an x86_64 (ttyS0)

IPv4/IPv6 addrs (Enter to refresh):
  eth0: 192.168.122.54 or [fe80::5054:ff:fe64:6aff]

actual-rhel-73 login: root
Password:
[root@actual-rhel-73 ~]#
Domain creation completed.
[root@localhost images]#
```


You can now run `virsh list` to see it running.
```
[root@localhost images]# virsh list
 Id    Name                           State
----------------------------------------------------
 18    actual-rhel-73.example.local running

[root@localhost images]#
```


Then stop the running VM (equivalent to pulling the power plug), and remove the VM from virsh
and remove the VM image file.
```
[root@localhost ~]# virsh destroy actual-rhel-73.example.local
Domain actual-rhel73.example.local destroyed

[root@localhost ~]# virsh undefine actual-rhel-73.example.local
Domain actual-rhel73.example.local has been undefined

[root@localhost ~]# rm /var/lib/libvirt/images/actual-rhel73.qcow2
rm: remove regular file ‘/var/lib/libvirt/images/actual-rhel73.qcow2’? y
[root@localhost ~]#
```

## Test Method 2: upvm to build image from template and run derivative VM.

On RHEL7, `upvm` and `valine` need helper packages so enable EPEL repo, then install the release RPM, then install
upvm, valine and the helper packages.

```
[root@localhost images]# yum -y install http://people.redhat.com/rsawhill/rpms/latest-rsawaroha-release.rpm
[root@localhost images]# yum -y install upvm valine python-argcomplete python2-configargparse
```


Run the upvm initial-setup:
```
[root@localhost images]# /usr/share/upvm/initial-setup
```

Create the `actual-rhel-73.example.local` from the `my-rhel73` template:
```
[root@localhost images]# upvm my-rhel-7.3 --hostname actual-rhel-73.example.local \
                         -n actual-rhel73 -m 4096 -c 2 --os-variant=rhel7.2 \
                         --img-size 50G --img-dir /var/lib/libvirt/images
Enter root password for new VM or enter 'random' or 'disabled' or file path : toor
  INFO: Password for root will be set to string 'toor'
Save password choice as default to '~/.config/upvm.conf'? [y]/n :
  INFO: Wrote 'root-password = password:toor' to ~/.config/upvm.conf
  INFO: Unable to determine native format of chosen template
  INFO: Using qcow2 for output format (change with --format=raw)
  INFO: Chosen os-variant ('rhel7.2') was validated by osinfo-query command
  INFO: Initializing libvirt connection to qemu:///session
  INFO: Starting virt-builder
[   1.5] Downloading: file:///var/lib/libvirt/images/virt-builder-templates/rhel-7.3-server.qcow2.xz
[   3.2] Planning how to build this image
[   3.2] Uncompressing
[  12.5] Resizing (using virt-resize) to expand the disk to 50.0G
[  50.4] Opening the new disk
[  52.2] Setting a random seed
[  52.2] Setting the hostname: actual-rhel-73.example.local
[  52.2] Running: /tmp/upvm-ifcfgdhcphostname-SbrPYP.sh
[  52.2] Installing firstboot script: /tmp/upvm-firstboot-sshkeys-cleanup-pe9MkD.sh
[  52.2] Setting passwords
[  53.1] Finishing off
                   Output file: /var/lib/libvirt/images/actual-rhel73.qcow2
                   Output size: 50.0G
                 Output format: qcow2
            Total usable space: 9.0G
                    Free space: 7.7G (85%)
<Trimmed for length>
[  OK  ] Started Command Scheduler.
         Starting Command Scheduler...
[  OK  ] Started Authorization Manager.
         Starting firewalld - dynamic firewall daemon...
[  OK  ] Started Install ABRT coredump hook.
[    3.189716] ip6_tables: (C) 2000-2006 Netfilter Core Team

[    3.211093] Ebtables v2.0 registered
[    3.263097] nf_conntrack version 0.5.0 (16384 buckets, 65536 max)
[    3.412362] IPv6: ADDRCONF(NETDEV_UP): eth0: link is not ready
[    3.486402] Netfilter messages via NETLINK v0.30.
[    3.491096] ip_set: protocol 6

Red Hat Enterprise Linux Server 7.3 (Maipo)
Kernel 3.10.0-514.el7.x86_64 on an x86_64 (ttyS0)

IPv4/IPv6 addrs (Enter to refresh):
  eth0: 192.168.122.160 or [fe80::5054:ff:fe79:cd41]

actual-rhel-73 login: [    9.383416] firstboot.sh[1048]: /usr/lib/virt-sysprep/firstboot.sh start
[    9.392524] firstboot.sh[1048]: Scripts dir: /usr/lib/virt-sysprep/scripts
[    9.420547] firstboot.sh[1048]: === Running 0001--tmp-upvm-firstboot-sshkeys-cleanup-2LNFKE-sh ===
[    9.436088] firstboot.sh[1048]: Installed authorized SSH pubkey(s) for root user
[    9.696223] firstboot.sh[1048]: job 1 at Mon Mar 13 18:01:00 2017
[    9.699387] firstboot.sh[1048]: Finished one-time firstboot script.

Red Hat Enterprise Linux Server 7.3 (Maipo)
Kernel 3.10.0-514.el7.x86_64 on an x86_64 (ttyS0)

IPv4/IPv6 addrs (Enter to refresh):
  eth0: 192.168.122.160 or [fe80::5054:ff:fe79:cd41]

actual-rhel-73 login:
```

You can then SSH into that VM as root:
```
[root@localhost images]# ssh root@192.168.122.160
The authenticity of host '192.168.122.160 (192.168.122.160)' can't be established.
ECDSA key fingerprint is 42:d9:7b:ee:ca:8f:39:c2:3b:a5:fa:9a:b3:18:96:63.
Are you sure you want to continue connecting (yes/no)? yes
Warning: Permanently added '192.168.122.160' (ECDSA) to the list of known hosts.
[root@actual-rhel-73 ~]#
```

And it behaves like a normal RHEL7 system should:
```
[root@actual-rhel-73 ~]# yum -y install httpd
[root@actual-rhel-73 ~]# systemctl enable httpd ; systemctl start httpd
Created symlink from /etc/systemd/system/multi-user.target.wants/httpd.service to
  /usr/lib/systemd/system/httpd.service.
[root@actual-rhel-73 ~]# curl http://localhost:80 | head
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  3985  100  3985    0     0   699k      0 --:--:-- --:--:-- --:--:--  778k
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">

<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
        <head>
                <title>Test Page for the Apache HTTP Server on Red Hat Enterprise Linux</title>
                <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
                <style type="text/css">
                        /*<![CDATA[*/
                        body {
                                background-color: #fff;
[root@actual-rhel-73 ~]#
```


Then stop the running VM (equivalent to pulling the power plug), and remove the VM from libvirt,
and remove the VM image file.
```
[root@localhost ~]# valine actual-rhel73 NUKE
About to UNDEFINE domain actual-rhel73 and DELETE all of its attached storage
THIS OPERATION CANNOT BE UNDONE!
  Continue? [y/n] y
  Forcefully terminating domain
    Waiting for domain to terminate ...
Domain actual-rhel73 has been undefined
Volume 'vda'(/var/lib/libvirt/images/actual-rhel73.qcow2) removed.
[root@localhost ~]#
```
