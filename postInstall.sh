#!/bin/bash
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}==> Начало настройки...${NC}"

sudo pacman -S --needed --noconfirm telegram-desktop discord steam intel-ucode base-devel git lib32-mangohud mangohud hysteria

mkdir -p ~/.AUR
cd ~/.AUR
if [ ! -d "paru" ]; then
    git clone https://aur.archlinux.org/paru.git
    cd paru
    makepkg -sric --noconfirm
    cd ..
fi

paru -S --noconfirm portproton

echo -e "${GREEN}==> Настройка ZRAM...${NC}"
sudo pacman -S --noconfirm zram-generator
echo 0 | sudo tee /sys/module/zswap/parameters/enabled

sudo bash -c 'cat <<EOF > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF'

if ! grep -q "/dev/zram0" /etc/fstab; then
    sudo bash -c 'echo -e "\n#ZRAM\n/dev/zram0 none swap defaults,pri=100 0 0" >> /etc/fstab'
fi

sudo systemctl daemon-reload
sudo systemctl start systemd-zram-setup@zram0.service

echo -e "${GREEN}==> Установка и включение earlyoom, ananicy, irqbalance...${NC}"
sudo pacman -S --noconfirm earlyoom ananicy-cpp irqbalance
paru -S --noconfirm cachyos-ananicy-rules-git

sudo systemctl enable --now earlyoom
sudo systemctl enable --now ananicy-cpp
sudo systemctl enable --now irqbalance

echo -e "${GREEN}==> Маскировка сервисов GNOME...${NC}"
systemctl --user mask org.gnome.SettingsDaemon.PrintNotifications.service
systemctl --user mask org.gnome.SettingsDaemon.A11ySettings.service
systemctl --user mask org.gnome.SettingsDaemon.Sharing.service
systemctl --user mask org.gnome.SettingsDaemon.Smartcard.service
systemctl --user mask org.gnome.SettingsDaemon.Power.service

sudo mkdir -p /etc/security/limits.d/
echo "@audio - rtprio 98" | sudo tee /etc/security/limits.d/20-rt-audio.conf

echo -e "${GREEN}==> Настройка Sysctl параметров...${NC}"
sudo sysctl -w kernel.sysrq=1
echo "vm.swappiness = 100" | sudo tee /etc/sysctl.d/90-sysctl.conf
echo "vm.page-cluster = 0" | sudo tee /etc/sysctl.d/99-sysctl.conf

if [[ $(cat /sys/kernel/mm/lru_gen/enabled) == "0x0000" ]]; then
    echo "y" | sudo tee /sys/kernel/mm/lru_gen/enabled
fi
sudo mkdir -p /etc/tmpfiles.d/
echo "w! /sys/kernel/mm/lru_gen/min_ttl_ms - - - - 2000" | sudo tee /etc/tmpfiles.d/90-page-trashing.conf

echo "vm.dirty_background_bytes=67108864" | sudo tee /etc/sysctl.d/30-dirty-pages.conf
echo "vm.dirty_bytes=268435456" | sudo tee /etc/sysctl.d/30-dirty-pages.conf
echo "vm.dirty_expire_centisecs=1500" | sudo tee /etc/sysctl.d/30-dirty-pages-expire.conf
echo "vm.dirty_writeback_centisecs=100" | sudo tee /etc/sysctl.d/30-dirty-pages-writeback.conf
echo "vm.vfs_cache_pressure = 50" | sudo tee /etc/sysctl.d/90-vfs-cache.conf

echo "options libahci ignore_sss=1" | sudo tee /etc/modprobe.d/30-ahci-disable-sss.conf

echo 1 | sudo tee /sys/kernel/mm/ksm/run
echo "w! /sys/kernel/mm/ksm/run - - - - 1" | sudo tee /etc/tmpfiles.d/ksm.conf
sudo mkdir -p /etc/systemd/system/user@.service.d/
sudo bash -c 'cat <<EOF > /etc/systemd/system/user@.service.d/10-ksm.conf
[Service]
MemoryKSM=yes
EOF'

echo -e "${GREEN}==> Настройка CPU (Intel P-State)...${NC}"
sudo pacman -S --noconfirm cpupower
echo "passive" | sudo tee /sys/devices/system/cpu/intel_pstate/status
sudo cpupower frequency-set -g performance
sudo systemctl enable --now cpupower

if grep -q "governor=" /etc/default/cpupower; then
    sudo sed -i "s/.*governor=.*/governor='performance'/" /etc/default/cpupower
else
    echo "governor='performance'" | sudo tee -a /etc/default/cpupower
fi

echo "kernel.watchdog = 0" | sudo tee /etc/sysctl.d/30-no-watchdog-timers.conf
echo "blacklist iTCO_wdt" | sudo tee /etc/modprobe.d/30-blacklist-watchdog-timers.conf

echo -e "${GREEN}==> Настройка I/O планировщиков (HDD/SSD/NVMe)...${NC}"
sudo bash -c 'cat <<EOF > /etc/udev/rules.d/90-io-schedulers.rules
# HDD
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"

# SSD (SATA)
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"

# NVMe SSD
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"

# eMMC/SD карты
ACTION=="add|change", KERNEL=="mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
EOF'

echo -e "${GREEN}==> Финальное обновление mkinitcpio и GRUB...${NC}"
sudo mkinitcpio -P
sudo grub-mkconfig -o /boot/grub/grub.cfg

echo -e "${GREEN}==> Все готово! Перезагрузите систему.${NC}"
