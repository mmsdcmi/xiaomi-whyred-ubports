#!/bin/bash

# Fetches android9 rootfs and generic system image to prepare flashable image from CI-built device tarball
URL='https://system-image.ubports.com'
ROOTFS_URL='https://ci.ubports.com/job/focal-hybris-rootfs-arm64/job/master/lastSuccessfulBuild/artifact/ubuntu-touch-android9plus-rootfs-arm64.tar.gz'
DEVICE_GENERIC_URL='https://ci.ubports.com/job/Archive/job/Device%20Compatibility%20Images/job/halium-generic_arm64/lastSuccessfulBuild/artifact/halium_halium_arm64.tar.xz'
OTA_CHANNEL='20.04/arm64/android9plus/devel'

DEVICE_TARBALL="$1"
OUTPUT="$2"

mkdir -p "$OUTPUT" || true

download_file_and_asc() {
    wget "$1" -P "$2"
    wget "$1.asc" -P "$2"
}

# Downloads master and signing keyrings
download_file_and_asc "${URL}/gpg/image-signing.tar.xz" "$OUTPUT"
download_file_and_asc "${URL}/gpg/image-master.tar.xz" "$OUTPUT"

# Start to generate ubuntu_command file
echo '# Generated by ubports rootfs-builder-debos' > "$OUTPUT/ubuntu_command"

cat << EOF >> "$OUTPUT/ubuntu_command"
format system
load_keyring image-master.tar.xz image-master.tar.xz.asc
load_keyring image-signing.tar.xz image-signing.tar.xz.asc
mount system
EOF

# Download and prepare rootfs
file=$(basename "$ROOTFS_URL")
wget "$ROOTFS_URL" -P "$OUTPUT"
mkdir -p "$OUTPUT/rootfs/system"
cd "$OUTPUT/rootfs"
sudo tar xpzf "../$file" --numeric-owner -C system

# Enable SSH and USB tethering for debugging in devel-flashable builds
echo "start on startup" > system/etc/init/ssh.override
echo "exec /usr/sbin/sshd -D -o PasswordAuthentication=yes -o PermitEmptyPasswords=yes" >> system/etc/init/ssh.override

echo "start on startup" > system/etc/init/usb-tethering.conf
echo "exec /bin/bash /usr/bin/usb-tethering" >> system/etc/init/usb-tethering.conf

sudo XZ_OPT=-1 tar cJf "../rootfs.tar.xz" system
cd -
sudo rm -rf "./$OUTPUT/rootfs"

file="rootfs.tar.xz"
touch "$OUTPUT/$file.asc"
echo "update $file $file.asc" >> "$OUTPUT/ubuntu_command"

# Device-generic tarball (Halium GSI)
file=$(basename "$DEVICE_GENERIC_URL")
wget "$DEVICE_GENERIC_URL" -P "$OUTPUT"
touch "$OUTPUT/$file.asc"
echo "update $file $file.asc" >> "$OUTPUT/ubuntu_command"

# Device tarball
file=$(basename "$DEVICE_TARBALL")
cp "$DEVICE_TARBALL" "$OUTPUT"
touch "$OUTPUT/$file.asc"
echo "update $file $file.asc" >> "$OUTPUT/ubuntu_command"

device=${file%.*} # remove extension from device tarball
device=${device##*_} # remove part before _

# Version tarball
mkdir "$OUTPUT/version"
cd "$OUTPUT/version"
mkdir -p system/etc/system-image
cat << EOF >> system/etc/system-image/channel.ini
[service]
base: system-image.ubports.com
http_port: 80
https_port: 443
channel: $OTA_CHANNEL
device: $device
EOF

mkdir -p system/etc/system-image/config.d
ln -s ../client.ini system/etc/system-image/config.d/00_default.ini
ln -s ../channel.ini system/etc/system-image/config.d/01_channel.ini
tar cvJf "../version.tar.xz" system
cd -
rm -r "$OUTPUT/version"

file="version.tar.xz"
touch "$OUTPUT/$file.asc"
echo "update $file $file.asc" >> "$OUTPUT/ubuntu_command"

# End ubuntu_command
echo 'unmount system' >> "$OUTPUT/ubuntu_command"
