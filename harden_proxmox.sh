#!/bin/bash

# Proxmox VE Server Hardening Script
# This script implements security measures for Proxmox Virtual Environment
# Must be run as root on Proxmox VE node

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

# Check if running on Proxmox
if [ ! -f "/etc/pve/pve.version" ]; then
    echo "This script must be run on a Proxmox VE system"
    exit 1
fi

echo "Starting Proxmox VE hardening process..."

# Function to log actions
log_action() {
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] $1" | tee -a /var/log/proxmox_hardening.log
}

# 1. System Updates
log_action "Performing system updates"
apt update
apt upgrade -y
apt dist-upgrade -y

# 2. Install security packages
log_action "Installing security packages"
apt install -y \
    fail2ban \
    rkhunter \
    aide \
    auditd \
    chrony \
    iptables-persistent \
    needrestart \
    unattended-upgrades \
    apt-listchanges \
    lynis \
    apparmor \
    apparmor-profiles \
    apparmor-utils \
    snort \
    acct

# 3. Configure automatic updates
log_action "Configuring automatic updates"
cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}:\${distro_codename}-updates";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::MailReport "on-change";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

# 4. Configure Proxmox Security Settings
log_action "Configuring Proxmox security settings"

# Disable subscription repository if enterprise subscription is not available
sed -i 's/^deb/# deb/g' /etc/apt/sources.list.d/pve-enterprise.list

# Add no-subscription repository
if ! grep -q "deb http://download.proxmox.com/debian/pve" /etc/apt/sources.list; then
    echo "deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription" >> /etc/apt/sources.list
fi

# Configure Proxmox web interface to use HTTPS only
sed -i 's/^#\?ssl_protocols.*/ssl_protocols TLSv1.2 TLSv1.3;/' /etc/nginx/nginx.conf
sed -i 's/^#\?ssl_prefer_server_ciphers.*/ssl_prefer_server_ciphers on;/' /etc/nginx/nginx.conf
sed -i 's/^#\?ssl_ciphers.*/ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;/' /etc/nginx/nginx.conf

# 5. Configure system auditing
log_action "Configuring system auditing"
cat > /etc/audit/rules.d/audit.rules << EOF
# Remove any existing rules
-D

# Buffer Size
-b 8192

# Failure Mode
-f 1

# Date and Time
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time-change
-a always,exit -F arch=b64 -S clock_settime -k time-change
-a always,exit -F arch=b32 -S clock_settime -k time-change

# User and Group
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k identity

# Login Events
-w /var/log/faillog -p wa -k logins
-w /var/run/faillock -p wa -k logins

# Process and File System
-a exit,always -F arch=b64 -S mount -S umount2 -k mount
-a exit,always -F arch=b32 -S mount -S umount -S umount2 -k mount
-a always,exit -F arch=b64 -S unlink -S rmdir -S rename -S renameat -k delete
-a always,exit -F arch=b32 -S unlink -S rmdir -S rename -S renameat -k delete

# Proxmox specific
-w /etc/pve -p wa -k proxmox_config
-w /var/lib/pve-cluster -p wa -k proxmox_cluster
-w /var/lib/pve-storage -p wa -k proxmox_storage
EOF

systemctl enable --now auditd

# 6. Configure fail2ban
log_action "Configuring fail2ban"
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3

[proxmox]
enabled = true
port = https,http,8006
filter = proxmox
logpath = /var/log/daemon.log
maxretry = 3
EOF

# Create Proxmox filter for fail2ban
cat > /etc/fail2ban/filter.d/proxmox.conf << EOF
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
EOF

systemctl enable --now fail2ban

# 7. Configure firewall
log_action "Configuring firewall"

# Create basic firewall rules
cat > /etc/pve/firewall/cluster.fw << EOF
[OPTIONS]
enable: 1
log_level_in: nolog
log_level_out: nolog
tcp_flags_log_level: nolog
smurf_log_level: nolog

[RULES]
GROUP ssh IN -i + -p tcp -dport 22
GROUP web IN -i + -p tcp -dport 8006
GROUP web IN -i + -p tcp -dport 443
GROUP web IN -i + -p tcp -dport 80
EOF

# Enable firewall
pvesh create /cluster/firewall/groups/ssh
pvesh create /cluster/firewall/groups/web
pve-firewall compile

# 8. Configure secure mount options
log_action "Implementing filesystem security"
cat >> /etc/fstab << EOF
# Secure mount options
tmpfs     /dev/shm     tmpfs     defaults,noexec,nosuid,nodev     0     0
EOF

# 9. Configure AppArmor
log_action "Configuring AppArmor"
systemctl enable --now apparmor
aa-enforce /etc/apparmor.d/*

# 10. Configure system-wide crypto policies
log_action "Setting system-wide crypto policies"
update-crypto-policies --set DEFAULT:NO-SHA1

# 11. Secure SSH configuration
log_action "Hardening SSH configuration"
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
cat > /etc/ssh/sshd_config << EOF
Protocol 2
Port 22
PermitRootLogin prohibit-password
MaxAuthTries 3
PermitEmptyPasswords no
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
IgnoreRhosts yes
HostbasedAuthentication no
PermitUserEnvironment no
ClientAliveInterval 300
ClientAliveCountMax 0
LoginGraceTime 60
X11Forwarding no
Banner /etc/issue.net
EOF

systemctl restart sshd

# 12. Configure VM Security
log_action "Configuring VM security settings"

# Set default VM security settings
cat > /etc/pve/qemu-server/defaults.conf << EOF
memory: 512
balloon: 1
onboot: 0
protection: 1
keyboard: en-us
cpu: host
vga: std
EOF

# 13. Enable accounting
log_action "Enabling system accounting"
systemctl enable --now acct

# 14. Configure AIDE
log_action "Configuring AIDE"
aideinit
mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# Create daily AIDE check
cat > /etc/cron.daily/aide-check << EOF
#!/bin/bash
/usr/bin/aide --check > /var/log/aide/aide.log 2>&1
EOF
chmod +x /etc/cron.daily/aide-check

# 15. Configure Snort IDS
log_action "Configuring Snort IDS"
# Basic Snort configuration - should be customized based on network
cat > /etc/snort/snort.conf << EOF
# Network configuration
ipvar HOME_NET [192.168.0.0/16,10.0.0.0/8]
ipvar EXTERNAL_NET !$HOME_NET

# Rule sets
include $RULE_PATH/local.rules
include $RULE_PATH/emerging-threats.rules
EOF

systemctl enable --now snort

# 16. Enable essential services
log_action "Enabling essential services"
systemctl enable --now chronyd
systemctl enable --now auditd
systemctl enable --now fail2ban
systemctl enable --now apparmor

# Final system checks
log_action "Performing final system checks"

# Check services
systemctl is-active pve-firewall
systemctl is-active auditd
systemctl is-active fail2ban
systemctl is-active apparmor
systemctl is-active snort

# Run security audit
lynis audit system --quick

echo "Proxmox VE hardening completed. Please review /var/log/proxmox_hardening.log for details"
echo "It is recommended to reboot the system to apply all changes"
echo "After reboot, verify all VMs start correctly and check cluster status if applicable"