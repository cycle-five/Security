#!/bin/bash

# AlmaLinux 9 Server Hardening Script
# This script implements security best practices and compliance requirements
# Must be run as root
#I will add comments to these from now on so I don't casually forget to install audit, but then try to configure

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

echo "Starting AlmaLinux 9 hardening process..."

# Function to log actions
log_action() {
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] $1" | tee -a /var/log/server_hardening.log
}

# 1. System Updates
log_action "Performing system updates"
dnf update -y
dnf upgrade -y

# 2. Install necessary security packages
log_action "Installing security packages"
dnf install -y dnf-automatic aide rsyslog auditd fail2ban chrony

# 3. Configure automatic updates
log_action "Configuring automatic updates"
cat > /etc/dnf/automatic.conf << EOF
[commands]
upgrade_type = security
random_sleep = 360
download_updates = yes
apply_updates = yes
EOF

systemctl enable --now dnf-automatic.timer

# 4. Password and Authentication Policy
log_action "Configuring password policies"
cat > /etc/security/pwquality.conf << EOF
minlen = 12
dcredit = -1
ucredit = -1
ocredit = -1
lcredit = -1
minclass = 4
maxrepeat = 3
EOF

# Configure PAM
sed -i 's/password    requisite     pam_pwquality.so.*/password    requisite     pam_pwquality.so try_first_pass local_users_only retry=3 authtok_type=/' /etc/pam.d/system-auth

# 5. SSH Hardening
log_action "Hardening SSH configuration"
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
cat > /etc/ssh/sshd_config << EOF
Protocol 2
Port 22
PermitRootLogin no
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

# 6. Configure Firewall
log_action "Configuring firewall"
dnf install -y firewalld
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --remove-service=telnet
firewall-cmd --permanent --remove-service=rsh
firewall-cmd --reload

# 7. File System Security
log_action "Implementing filesystem security"

# Set secure mount options
cat >> /etc/fstab << EOF
# Secure mount options
tmpfs     /dev/shm     tmpfs     defaults,noexec,nosuid,nodev     0     0
EOF

# Set secure permissions on critical files
chmod 600 /etc/shadow
chmod 600 /etc/gshadow
chmod 644 /etc/passwd
chmod 644 /etc/group
chmod 600 /etc/ssh/sshd_config

# 8. Configure System Auditing
log_action "Configuring system auditing"
cat > /etc/audit/rules.d/audit.rules << EOF
# Delete all existing rules
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
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock -p wa -k logins

# Process and File System
-a exit,always -F arch=b64 -S mount -S umount2 -k mount
-a exit,always -F arch=b32 -S mount -S umount -S umount2 -k mount
-a always,exit -F arch=b64 -S unlink -S rmdir -S rename -S renameat -k delete
-a always,exit -F arch=b32 -S unlink -S rmdir -S rename -S renameat -k delete

# Privilege Escalation
-w /bin/su -p x -k priv_esc
-w /usr/bin/sudo -p x -k priv_esc
-w /etc/sudoers -p rw -k priv_esc
EOF

systemctl enable --now auditd

# 9. Configure System Logging
log_action "Configuring system logging"
cat > /etc/rsyslog.conf << EOF
# Log auth messages
auth,authpriv.*                 /var/log/auth.log
# Log all kernel messages
kern.*                          /var/log/kern.log
# Log all system messages
*.info;mail.none;authpriv.none;cron.none    /var/log/messages
# Log all mail messages
mail.*                          /var/log/mail.log
# Log cron messages
cron.*                         /var/log/cron.log
# Log emergency messages
*.emerg                        :omusrmsg:*
EOF

systemctl restart rsyslog

# 10. Configure fail2ban
log_action "Configuring fail2ban"
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

# 11. Disable Unused Services
log_action "Disabling unused services"
services_to_disable=(
    "cups"
    "avahi-daemon"
    "bluetooth"
    "isc-dhcp-server"
    "nfs-server"
    "rpcbind"
)

for service in "${services_to_disable[@]}"; do
    systemctl disable --now "$service" 2>/dev/null || true
done

# 12. Set GRUB password
log_action "Securing GRUB bootloader"
grub2-setpassword

# 13. Configure system-wide crypto policies
log_action "Setting system-wide crypto policies"
update-crypto-policies --set DEFAULT:NO-SHA1

# 14. Enable SELinux
log_action "Ensuring SELinux is enabled"
sed -i 's/SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
setenforce 1

# 15. Set secure umask
log_action "Setting secure umask"
echo "umask 027" >> /etc/profile
echo "umask 027" >> /etc/bashrc

# Final system checks
log_action "Performing final system checks"

# Verify services
systemctl is-active sshd
systemctl is-active firewalld
systemctl is-active auditd
systemctl is-active rsyslog
systemctl is-active fail2ban

echo "Server hardening completed. Please review /var/log/server_hardening.log for details"
echo "It is recommended to reboot the system to apply all changes"