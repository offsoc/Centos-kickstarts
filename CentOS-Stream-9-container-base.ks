# See container-base-common.ks for details on how to hack on docker image kickstarts
# This is the standard base image.

%include CentOS-Stream-9-container-common.ks

%packages --excludedocs --instLangs=en --nocore --excludeWeakdeps
# Install yum explicitly instead of dnf to make sure we get the 'yum' command
yum
#subscription-manager
vim-minimal
gdb-gdbserver
findutils
tar
gzip
crypto-policies-scripts
python3-dnf-plugins-core
%end

%post --erroronfail --log=/root/anaconda-post.log
#Mask mount units and getty service so that we don't get login prompt
#https://bugzilla.redhat.com/show_bug.cgi?id=1418327
systemctl mask systemd-logind.service getty.target console-getty.service sys-fs-fuse-connections.mount systemd-remount-fs.service dev-hugepages.mount

# Remove some dnf info
rm -rfv /var/lib/dnf

# Final pruning
rm -rfv /var/cache/* /var/log/* /tmp/*

%end

%post --nochroot --erroronfail --log=/mnt/sysimage/root/anaconda-post-nochroot.log
set -eux

# https://bugzilla.redhat.com/show_bug.cgi?id=1343138
# Fix /run/lock breakage since it's not tmpfs in docker
# This unmounts /run (tmpfs) and then recreates the files
# in the /run directory on the root filesystem of the container
# NOTE: run this in nochroot because "umount" does not exist in chroot
umount /mnt/sysimage/run
# The file that specifies the /run/lock tmpfile is
# /usr/lib/tmpfiles.d/legacy.conf, which is part of the systemd
# rpm that isn't included in this image. We'll create the /run/lock
# file here manually with the settings from legacy.conf
# NOTE: chroot to run "install" because it is not in anaconda env
chroot /mnt/sysimage install -d /run/lock -m 0755 -o root -g root

%end
