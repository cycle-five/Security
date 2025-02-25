#!/bin/bash

# Arch Linux Personal PC Hardening Script
# This script implements security measures for a personal Arch Linux installation
# Must be run as root

if [ "$EUID" -ne 0 ]; then 
    echo "You must run this script as root."
    exit 1
fi

echo "Starting Arch Linux hardening process..."

log_action() {
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] $1" | tee -a /var/log/pc_hardening.log
}

pacman -Syu --noconfirm

sleep 30

echo "Would you like to install basic software? (y/n)"
read answer

if [ "$answer" = "y" ]; || [ "$answer" = "Y" ]; then 
    log_action "Installing basic software"
    pacman -S \
        neovim \
        git \
        curl \
        sudo \
        yubikey-manager \
    else 
        echo "Moving onto Desktop env select"
fi

sleep 2
echo "Are you using KDE?"

if [ "$answer" = "y" ]; || [ "$answer" = "Y" ]; then 
    pacman -S \ 
    log_action "Are you using KDE? NOTE: This is currently tailored to KDE, other desktops will need to manually install theirs"

pacman -S --noconfirm \
    firewalld \
    apparmor \
    keepassxc

systemctl enable --now ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow from 192.168.0.0/24
ufw enable

systemctl enable --now apparmor
aa-enforce /etc/apparmor.d/*

systemctl enable --now audit

cat > /etc/audit/rules.d/audit.rules << EOF
-D
-b 8192
-f 1
-w /var/log/auth.log -p wa -k auth
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers
-w /var/log/sudo.log -p wa -k sudo
-a exit,always -F arch=b64 -S execve -k exec
-a exit,always -F arch=b64 -S mount -k mount
-w /etc/group -p wa -k usergroup
-w /etc/passwd -p wa -k userpass
-w /etc/shadow -p wa -k shadowpass
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/log/tallylog -p wa -k logins
-a always,exit -F arch=b64 -S sethostname -S setdomainname -k network-env
-w /etc/init.d/ -p wa -k init
-w /etc/systemd/ -p wa -k systemd
EOF

cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF

systemctl enable --now fail2ban

sed -i 's/# pam_wheel.so use_uid/pam_wheel.so use_uid/' /etc/pam.d/su
sed -i 's/auth\s*required\s*pam_unix.so/auth required pam_unix.so remember=5/' /etc/pam.d/system-auth

cat >> /etc/fstab << EOF
tmpfs   /tmp         tmpfs   defaults,noexec,nosuid,nodev   0  0
EOF

pacman -S --noconfirm crypto-policies
update-crypto-policies --set DEFAULT:NO-SHA1

if [ -d "/sys/firmware/efi" ]; then
    log_action "Configuring Secure Boot settings"
    pacman -S --noconfirm sbsigntools efitools
fi

mkdir -p /etc/firefox/policies
cat > /etc/firefox/policies/policies.json << EOF
{
  "policies": {
    "DisableFormHistory": true,
    "DisableTelemetry": true,
    "EnableTrackingProtection": {
      "Value": true,
      "Locked": true,
      "Cryptomining": true,
      "Fingerprinting": true
    },
    "ExtensionSettings": {
      "uBlock@raymondhill.net": {
        "installation_mode": "force_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
      }
    },
    "DNSOverHTTPS": {
      "Enabled": true,
      "ProviderURL": "https://dns.quad9.net/dns-query",
      "Locked": true
    }
  }
}
EOF

for profile in /etc/firejail/*.profile; do
    if [ -f "$profile" ]; then
        echo "include /etc/firejail/disable-common.inc" >> "$profile"
        echo "include /etc/firejail/disable-devel.inc" >> "$profile"
    fi
done

rkhunter --update
rkhunter --propupd
cat > /etc/rkhunter.conf.local << EOF
MIRRORS_MODE=1
UPDATE_MIRRORS=1
PKGMGR=PACMAN
EOF

if [ -n "$(grep -i "vendor_id.*GenuineIntel" /proc/cpuinfo)" ]; then
    pacman -S --noconfirm intel-ucode
elif [ -n "$(grep -i "vendor_id.*AuthenticAMD" /proc/cpuinfo)" ]; then
    pacman -S --noconfirm amd-ucode
fi

if [ -f /etc/default/grub ]; then
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=".*"/GRUB_CMDLINE_LINUX_DEFAULT="quiet apparmor=1 security=apparmor audit=1 slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 pti=on randomize_kstack_offset=on vsyscall=none"/' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
fi

pacman -S --noconfirm rsync
mkdir -p /etc/backup-scripts
cat > /etc/backup-scripts/system-backup.sh << EOF
#!/bin/bash
rsync -aAXv --delete --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} / /path/to/backup/
EOF
chmod +x /etc/backup-scripts/system-backup.sh

systemctl enable --now chronyd
systemctl enable --now apparmor
systemctl enable --now auditd
systemctl enable --now fail2ban

systemctl is-active firewalld
systemctl is-active apparmor
systemctl is-active auditd
systemctl is-active fail2ban

arch-audit

echo "Personal PC hardening completed. Please review /var/log/pc_hardening.log for details"
echo "It is recommended to reboot the system to apply all changes"
echo "After reboot, run 'arch-audit' to check for any security advisories"
