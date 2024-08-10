#!/bin/bash

prompt_for_input() {
    local prompt_message=$1
    local input_var
    read -p "$prompt_message" input_var
    echo $input_var
}

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

D_PARTITION_NUMBER=$(prompt_for_input "Enter the partition number for the D: drive (e.g., if D: is /dev/sda2, enter '2'): ")

USB_DISK=$(prompt_for_input "Enter the USB drive name (e.g., /dev/sdb): ")
USB_PARTITION_NUMBER=$(prompt_for_input "Enter the partition number for the USB drive (e.g., if USB is /dev/sdb1, enter '1'): ")

ROOT_PASSWORD=$(prompt_for_input "Enter the root password for the Kali Linux installation: ")

DISK_PARTITION="/dev/sda$D_PARTITION_NUMBER"
USB_PARTITION="$USB_DISK$USB_PARTITION_NUMBER"

MOUNT_POINT="/mnt/disk"
INSTALL_DIR="$MOUNT_POINT/test_dir"
USB_MOUNT="/mnt/usb"
USB_BOOT="$USB_MOUNT/boot"
GRUB_CFG="$USB_BOOT/grub/grub.cfg"
CHECK_SCRIPT="$USB_BOOT/boot/check_and_boot.sh"

echo "Starting Kali Linux installation to $INSTALL_DIR"

mkdir -p $MOUNT_POINT
mount $DISK_PARTITION $MOUNT_POINT

if [ ! -d "$INSTALL_DIR" ]; then
    mkdir -p $INSTALL_DIR
fi

echo "Only files in $INSTALL_DIR will be modified. No other files on the D: drive will be affected."

if ! command -v debootstrap &> /dev/null
then
    echo "Installing debootstrap..."
    apt-get update
    apt-get install -y debootstrap
fi

echo "Bootstrapping Kali Linux base system..."
debootstrap --arch=amd64 kali-rolling $INSTALL_DIR http://http.kali.org/kali

mount --bind /dev $INSTALL_DIR/dev
mount --bind /sys $INSTALL_DIR/sys
mount --bind /proc $INSTALL_DIR/proc

echo "Chrooting into the new system to finalize installation..."
chroot $INSTALL_DIR /bin/bash <<EOF

echo "root:$ROOT_PASSWORD" | chpasswd

apt-get update
apt-get install -y kali-linux-core kali-linux-default

grub-install --target=i386-pc --boot-directory=/boot $USB_DISK
update-grub

exit
EOF

echo "Unmounting filesystems..."
umount $INSTALL_DIR/dev
umount $INSTALL_DIR/sys
umount $INSTALL_DIR/proc
umount $MOUNT_POINT

echo "Setting up USB for booting..."

mkdir -p $USB_MOUNT
mount $USB_PARTITION $USB_MOUNT

USB_DRIVE_INDEX=$(lsblk -o NAME,TYPE | grep -E '^sd.+' | grep -n 'disk' | awk -F: '{print $1}')
USB_PART_INDEX=$(lsblk -o NAME,TYPE | grep -E '^sd.+' | grep -n 'part' | awk -F: '{print $1}')
if [ -z "$USB_DRIVE_INDEX" ] || [ -z "$USB_PART_INDEX" ]; then
  echo "Error: Could not determine USB drive and partition indices."
  exit 1
fi

ROOT_SETTING="(hd${USB_DRIVE_INDEX},${USB_PART_INDEX})"

mkdir -p $USB_BOOT/boot
cat <<EOF > $CHECK_SCRIPT
#!/bin/bash

MOUNT_POINT="/mnt/disk"
CHECK_DIR="\$MOUNT_POINT/test_dir"

if [ "\$(ls -A \$CHECK_DIR)" ]; then
  echo "Directory \$CHECK_DIR is not empty. Booting into Kali Linux."
  exec /boot/grub/grub.cfg
else
  echo "Directory \$CHECK_DIR is empty. Booting into the default OS."
  exit 1
fi
EOF

chmod +x $CHECK_SCRIPT

cat <<EOF > $GRUB_CFG
set timeout=10
set default=0

menuentry "Check and Boot Kali Linux" {
    insmod ext2
    insmod linux
    set root='$ROOT_SETTING'
    linux /boot/check_and_boot.sh
}
EOF

grub-install --target=i386-pc --boot-directory=$USB_BOOT $USB_DISK

umount $USB_MOUNT

echo "Installation complete. You can now reboot your system."

read -p "Do you want to reboot now? (y/n): " REBOOT
if [ "$REBOOT" = "y" ]; then
  reboot
else
  echo "You can reboot later to test the installation."
fi