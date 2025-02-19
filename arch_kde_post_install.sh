#!/bin/bash

# Arch Linux KDE Post-Installation Script
# This script sets up and configures an Arch Linux system with KDE Plasma
# Must be run as root

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

echo "Starting Arch Linux KDE post-installation setup..."

# Function to log actions
log_action() {
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] $1" | tee -a /var/log/post_install.log
}

# Update system first
log_action "Updating system"
pacman -Syu --noconfirm

# Install basic system utilities
log_action "Installing basic system utilities"
pacman -S --noconfirm \
    base-devel \
    git \
    neovim \
    curl \
    wget \
    htop \
    neofetch \
    reflector \
    networkmanager \
    network-manager-applet \
    bluez \
    bluez-utils \
    cups \
    xdg-utils \
    xdg-user-dirs

# Install and configure audio
log_action "Setting up audio"
pacman -S --noconfirm \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    pipewire-jack \
    wireplumber

# Install common applications
log_action "Installing common applications"
pacman -S --noconfirm \
    firefox \
    vlc \
    okular \
    gwenview \
    dolphin \
    konsole \
    kate \
    ark \
    kcalc \
    spectacle \
    filelight \
    kdeconnect

# Install development tools
log_action "Installing development tools"
pacman -S --noconfirm \
    visual-studio-code-bin \
    docker \
    docker-compose

# Install fonts
log_action "Installing fonts"
pacman -S --noconfirm \
    ttf-dejavu \
    ttf-liberation \
    noto-fonts \
    noto-fonts-emoji \
    ttf-hack-nerd

# Enable services
log_action "Enabling services"
systemctl enable --now NetworkManager
systemctl enable --now bluetooth
systemctl enable --now cups
systemctl enable --now docker

# Configure pacman
log_action "Configuring pacman"
sed -i 's/#Color/Color/' /etc/pacman.conf
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf

# Install AUR helper (yay)
log_action "Installing yay AUR helper"
if ! command -v yay &> /dev/null; then
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ..
    rm -rf yay
fi

# Install some AUR packages
log_action "Installing AUR packages"
sudo -u $(logname) yay -S --noconfirm \
    google-chrome \
    visual-studio-code-bin \
    spotify

# Configure KDE
log_action "Configuring KDE settings"
# Set dark theme
kwriteconfig5 --file kdeglobals --group General --key ColorScheme BreezeDark
# Enable tap-to-click
kwriteconfig5 --file kcminputrc --group Mouse --key X11LibInputXAccelProfileFlat true

# Create common user directories
log_action "Creating user directories"
sudo -u $(logname) xdg-user-dirs-update

# Final system update
log_action "Performing final system update"
pacman -Syu --noconfirm

echo "Post-installation setup completed!"
echo "Please check /var/log/post_install.log for details"
echo "It is recommended to reboot your system now"
echo ""
echo "After reboot:"
echo "1. Configure your preferred KDE settings"
echo "2. Set up your preferred browser"
echo "3. Configure your development environment"
echo ""
read -p "Would you like to reboot now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    reboot
fi 