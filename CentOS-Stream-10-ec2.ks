# Kickstart file to build CentOS-Stream-10 Amazon EC2 image

text
lang en_US.UTF-8
keyboard us
timezone --utc UTC
#RHBZ 1732491 Bump nvme_core io.timeout to avoid AWS nitro instance freeze
bootloader --timeout=1 --location=mbr --append="console=ttyS0,115200n8 console=tty0 net.ifnames=0 rd.blacklist=nouveau nvme_core.io_timeout=4294967295"
auth --enableshadow --passalgo=sha512
#authselect select sssd
selinux --enforcing
firewall --enabled --service=ssh
network --bootproto=dhcp --device=link --activate --onboot=on
services --enabled=sshd,NetworkManager,cloud-init,cloud-init-local,cloud-config,cloud-final,rngd --disabled kdump,rhsmcertd

rootpw --iscrypted nope

%pre --erroronfail
/usr/sbin/parted -s /dev/vda mklabel gpt
%end

part biosboot --fstype=biosboot --size=1 --ondisk vda
part / --size 6144 --fstype ext4 --mkfsoptions "-m bigtime=0,inobtcount=0" --ondisk vda
reboot


# Packages
%packages
@core
kernel
yum-utils
rng-tools
redhat-release
redhat-release-eula

# pull firmware packages out
-aic94xx-firmware
-alsa-firmware
-alsa-lib
-alsa-tools-firmware
-ivtv-firmware
-iwl1000-firmware
-iwl100-firmware
-iwl105-firmware
-iwl135-firmware
-iwl2000-firmware
-iwl2030-firmware
-iwl3160-firmware
-iwl3945-firmware
-iwl4965-firmware
-iwl5000-firmware
-iwl5150-firmware
-iwl6000-firmware
-iwl6000g2a-firmware
-iwl6000g2b-firmware
-iwl6050-firmware
-iwl7260-firmware
-libertas-sd8686-firmware
-libertas-sd8787-firmware
-libertas-usb8388-firmware

# cloud-init does magical things with EC2 metadata, including provisioning
# a user account with ssh keys.
cloud-init

# need this for growpart, because parted doesn't yet support resizepart
# https://bugzilla.redhat.com/show_bug.cgi?id=966993
#cloud-utils

# We need this image to be portable; also, rescue mode isn't useful here.
dracut-config-generic

# We need a bootloader. grub2 because of xfs.
grub2

# Needed initially, but removed below.
firewalld

# cherry-pick a few things from @base
tar
rsync
dhcp-client
NetworkManager

# certs for RHUI
# Disabled for now, RHUI will not be active just yet
# No RHUI for RHEL-10 yet.
#rh-amazon-rhui-client

# Some things from @core we can do without in a minimal install
-biosdevname
-plymouth
-iprutils

# enable rootfs resize on boot
cloud-utils-growpart
gdisk

%end

#
# Add custom post scripts after the base post.
#
%post --erroronfail

# workaround anaconda requirements
passwd -d root
passwd -l root

mkdir /data
# ImageFactory EC2 plugin stuff ends here -- remove once in Brew

# temporary hack to get around a koji bug
# /sbin/chkconfig rh-cloud-firstboot off
# Koji fix applied, Turning firstboot on for testing
/sbin/chkconfig rh-cloud-firstboot on

# setup systemd to boot to the right runlevel
echo -n "Setting default runlevel to multiuser text mode"
rm -f /etc/systemd/system/default.target
ln -s /lib/systemd/system/multi-user.target /etc/systemd/system/default.target
echo .

# this is installed by default but we don't need it in virt
echo "Removing linux-firmware package."
yum -C -y --noplugins remove linux-firmware

# Remove firewalld; it is required to be present for install/image building.
echo "Removing firewalld."
yum -C -y --noplugins remove firewalld --setopt="clean_requirements_on_remove=1"

echo -n "Getty fixes"
# although we want console output going to the serial console, we don't
# actually have the opportunity to login there. FIX.
# we don't really need to auto-spawn _any_ gettys.
sed -i '/^#NAutoVTs=.*/ a\
NAutoVTs=0' /etc/systemd/logind.conf

echo -n "Network fixes"
# initscripts don't like this file to be missing.
cat > /etc/sysconfig/network << EOF
NETWORKING=yes
NOZEROCONF=yes
EOF

# For cloud images, 'eth0' _is_ the predictable device name, since
# we don't want to be tied to specific virtual (!) hardware
rm -f /etc/udev/rules.d/70*
ln -s /dev/null /etc/udev/rules.d/80-net-name-slot.rules

# simple eth0 config, again not hard-coded to the build hardware
cat > /etc/sysconfig/network-scripts/ifcfg-eth0 << EOF
DEVICE="eth0"
BOOTPROTO="dhcp"
ONBOOT="yes"
TYPE="Ethernet"
USERCTL="yes"
PEERDNS="yes"
IPV6INIT="no"
EOF

# generic localhost names
cat > /etc/hosts << EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

EOF
echo .

cat <<EOL > /etc/sysconfig/kernel
# UPDATEDEFAULT specifies if new-kernel-pkg should make
# new kernels the default
UPDATEDEFAULT=yes

# DEFAULTKERNEL specifies the default kernel package type
DEFAULTKERNEL=kernel
EOL

# make sure firstboot doesn't start
echo "RUN_FIRSTBOOT=NO" > /etc/sysconfig/firstboot

# workaround https://bugzilla.redhat.com/show_bug.cgi?id=966888
if ! grep -q growpart /etc/cloud/cloud.cfg; then
  sed -i 's/ - resizefs/ - growpart\n - resizefs/' /etc/cloud/cloud.cfg
fi

# tell cloud-init to create the ec2-user account
sed -i 's/cloud-user/ec2-user/' /etc/cloud/cloud.cfg

# allow sudo powers to ec2-user
echo -e 'ec2-user\tALL=(ALL)\tNOPASSWD: ALL' >> /etc/sudoers

# Disable subscription-manager yum plugins
sed -i 's|^enabled=1|enabled=0|' /etc/yum/pluginconf.d/product-id.conf
sed -i 's|^enabled=1|enabled=0|' /etc/yum/pluginconf.d/subscription-manager.conf

echo "Cleaning old yum repodata."
yum --noplugins clean all
truncate -c -s 0 /var/log/yum.log

echo "Fixing SELinux contexts."
touch /var/log/cron
touch /var/log/boot.log
mkdir -p /var/cache/yum
/usr/sbin/fixfiles -R -a restore

# remove these for ec2 debugging
sed -i -e 's/ rhgb quiet//' /boot/grub/grub.conf

cat > /etc/modprobe.d/blacklist-nouveau.conf << EOL
blacklist nouveau
EOL

# enable resizing on copied AMIs
echo 'install_items+=" sgdisk "' > /etc/dracut.conf.d/sgdisk.conf

echo 'add_drivers+=" xen-netfront xen-blkfront "' > /etc/dracut.conf.d/xen.conf
# Rerun dracut for the installed kernel (not the running kernel):
KERNEL_VERSION=$(rpm -q kernel --qf '%{V}-%{R}.%{arch}\n')
dracut -f /boot/initramfs-$KERNEL_VERSION.img $KERNEL_VERSION

cat /dev/null > /etc/machine-id

cat >> /etc/chrony.conf << EOF

# Amazon Time Sync Service
server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4
EOF

# Anaconda is writing to /etc/resolv.conf from the generating environment.
# The system should start out with an empty file.
# Resolves: ENGCMP-1342
truncate -s 0 /etc/resolv.conf

%end
