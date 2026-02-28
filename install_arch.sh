#!/bin/bash
lsblk -d -n -o NAME,SIZE,MODEL | nl
echo "--------------------------------------------------"
read -p "Введите имя системного диска (например, sda или nvme0n1): " DISK_NAME
DISK="/dev/$DISK_NAME"

echo "Разметка диска $DISK..."
sgdisk -Z $DISK
sgdisk -n 1:0:+512M -t 1:ef00 $DISK
sgdisk -n 2:0:+1G   -t 2:8300 $DISK
sgdisk -n 3:0:0     -t 3:8300 $DISK

PART_EFI="${DISK}1"
PART_BOOT="${DISK}2"
PART_ROOT="${DISK}3"

if [[ $DISK == *nvme* ]]; then
    PART_EFI="${DISK}p1"
    PART_BOOT="${DISK}p2"
    PART_ROOT="${DISK}p3"
fi

echo "Настройка шифрования..."
KEY_FILE="/root/usb/root.key"
cryptsetup luksFormat --type luks2 $PART_ROOT $KEY_FILE
cryptsetup open --key-file $KEY_FILE $PART_ROOT cryptroot

mkfs.vfat -F32 $PART_EFI
mkfs.ext4 $PART_BOOT
mkfs.ext4 /dev/mapper/cryptroot

mount /dev/mapper/cryptroot /mnt
mkdir /mnt/boot/
mount $PART_BOOT /mnt/boot
mkdir /mnt/boot/EFI
mount $PART_EFI /mnt/boot/EFI

pacstrap -i /mnt base base-devel linux linux-firmware nano lvm2 grub efibootmgr os-prober git wget unzip fish dhcpcd networkmanager gnome gnome-shell gdm mesa vulkan-radeon vulkan-mesa-layers opencl-mesa pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber libfprint firefox kvantum lrzip unrar unace p7zip squashfs-tools file-roller gvfs gvfs-mtp ntfs-3g ttf-liberation piper llvm clang lld mold openmp cpupower

genfstab -U /mnt >> /mnt/etc/fstab

ROOT_UUID=$(blkid -s UUID -o value $PART_ROOT)
cp $KEY_FILE /mnt/root.key

# В CHROOT
cat <<EOF > /mnt/chroot_script.sh
#!/bin/bash
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "archlinux" > /etc/hostname
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf

sed -i 's/^MODULES=(.*)/MODULES=(vfat)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=(.*)/HOOKS=(base udev microcode autodetect modconf kms keyboard keymap encrypt lvm2 sd-vconsole block filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -p linux

sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="loglevel=7 pci=pcie_bus_perf preempt=full threadirqs nowatchdog pcie_aspm=off"|' /etc/default/grub
sed -i 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX="cryptdevice=UUID=$ROOT_UUID:cryptroot cryptkey=UUID=A5BA-02CC:vfat:/root.key"|' /etc/default/grub
sed -i 's/#GRUB_ENABLE_CRYPTODISK="y"/GRUB_ENABLE_CRYPTODISK="y"/' /etc/default/grub
sed -i 's/#GRUB_DISABLE_OS_PROBER="false"/GRUB_DISABLE_OS_PROBER="false"/' /etc/default/grub

grub-install $DISK
grub-mkconfig -o /boot/grub/grub.cfg

echo "Пароль для root:"
passwd
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
useradd -m -g users -G wheel -s /usr/bin/fish boatswain
echo "Пароль для boatswain:"
passwd boatswain

mkdir -p /etc/keys
mv /root.key /etc/keys/root.key
chmod 600 /etc/keys/root.key
chown root:root /etc/keys/root.key

cat <<EOT >> /etc/crypttab
music UUID=677ec033-bed5-4995-aec1-b6b63c8f3b69 /etc/keys/root.key none
documents UUID=28b8ca68-c14b-49e9-94e6-f406c28b00a8 /etc/keys/root.key none
downloads UUID=2b4e7604-f1e4-4da6-b26d-d122b4a9f353 /etc/keys/root.key none
videos UUID=d6f62c18-f786-4cce-9248-0382442ce119 /etc/keys/root.key none
EOT

mkdir -p /home/boatswain/{.games,Music,Videos,Documents,Downloads}
cat <<EOT >> /etc/fstab
UUID=e60be826-08e1-4823-a8af-f2bad9e88e38 /home/boatswain/.games btrfs rw,relatime,compress=zstd:3,ssd_spread,commit=600 0 0
UUID=6aad7868-8b2f-4afa-a299-12c6bd5d1f6c /home/boatswain/Music ext4 rw,noatime,commit=100 0 2
UUID=9ad47dd5-fe32-40e4-9c9b-532ed46217cc /home/boatswain/Videos ext4 rw,noatime,commit=100 0 2
UUID=98caa631-7ad6-4eb4-b534-cf2142dda652 /home/boatswain/Documents ext4 rw,noatime,commit=100 0 2
UUID=24a08870-27b4-4616-8b35-3646e9435bd5 /home/boatswain/Downloads ext4 rw,noatime,commit=100 0 2
EOT
chown -R boatswain:users /home/boatswain/

systemctl enable dhcpcd NetworkManager gdm
echo "set -g fish_greeting" >> /etc/fish/config.fish

echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
pacman -Syy --noconfirm
pacman -S --noconfirm lib32-vulkan-radeon

cd /home/boatswain
sudo -u boatswain git clone https://github.com/Sprusrroot/files_for_system_dots
sudo -u boatswain mkdir -p /home/boatswain/.config /home/boatswain/.local/bin
sudo -u boatswain cp -r files_for_system_dots/pipewire /home/boatswain/.config/
sudo -u boatswain cp files_for_system_dots/dot.makepkg-clang.conf /home/boatswain/.makepkg-clang.conf
sudo -u boatswain cp files_for_system_dots/dot.makepkg.conf /home/boatswain/.makepkg.conf
sudo -u boatswain cp files_for_system_dots/shutdown_on_pause.sh /home/boatswain/.local/bin/
echo 'set -gx PATH \$HOME/.local/bin \$PATH' >> /home/boatswain/.config/fish/config.fish

sudo -u boatswain git clone https://github.com/somepaulo/MoreWaita
cd MoreWaita && chmod +x install.sh && ./install.sh
cd ..

sudo -u boatswain dbus-launch systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service

EOF

chmod +x /mnt/chroot_script.sh
arch-chroot /mnt ./chroot_script.sh
rm /mnt/chroot_script.sh

echo "Установка завершена! Перезагрузитесь."
