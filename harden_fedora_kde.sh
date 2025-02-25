#!/bin/bash

# Fedora KDE Personal PC Hardening Script
# This script implements security measures for a personal Fedora KDE installation
# Must be run as root

if [ "$EUID" -ne 0 ]; then 
    echo "You must run this script as root."
    exit 1
fi

echo "Starting Fedora KDE hardening process..."

log_action() {
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] $1" | tee -a /var/log/kde_hardening.log
}

log_action "Performing system updates"
dnf upgrade --refresh -y
dnf autoremove -y

# 2. Install security packages
log_action "Installing security packages"
dnf install -y \
    firewalld \
    dnf-automatic \
    audit \
    chrony \
    clamav \
    clamav-update \
    

log_action "Configuring automatic updates"
cat > /etc/dnf/automatic.conf << EOF
[commands]
upgrade_type = security
random_sleep = 360
download_updates = yes
apply_updates = yes
EOF

systemctl enable --now dnf-automatic.timer

log_action "Configuring DNF settings"
    cat >> /etc/dnf/dnf.conf << EOF
    fastestmirror=true
    max_parallel_downloads=10
    deltarpm=true
EOF

log_action "Configuring firewall"
systemctl enable --now firewalld
firewall-cmd --set-default-zone=FedoraWorkstation
firewall-cmd --permanent --zone=FedoraWorkstation --remove-service=ssh 
firewall-cmd --reload


# 7. Configure SELinux
log_action "Configuring SELinux"
# Ensure SELinux is enforcing
sed -i 's/SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
setenforce 1

# 8. Configure system auditing
log_action "Configuring system auditing"
cat > /etc/audit/rules.d/audit.rules << EOF
# Remove any existing rules
-D

# Buffer Size
-b 8192

# Failure Mode
-f 1

# System Access, Authentication and Authorization
-w /var/log/auth.log -p wa -k auth
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# Login/Logout
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins

# System Calls
-a exit,always -F arch=b64 -S execve -k exec
EOF

systemctl enable --now auditd

log_action "Configuring KDE security settings"

mkdir -p /etc/xdg/kdeglobals.d
    cat > /etc/xdg/kdeglobals.d/kde-security.conf << EOF
    [KDE]
    LockOnResume=true

    [General]
    AutomaticLockTime=10

    [Passwords]
    ShowPassword=false

    [Clipboard]
    PreventEmptyClipboard=true
    IgnoreSelection=false
EOF

log_action "Configuring KWallet"
    mkdir -p /etc/xdg/kwalletrc.d
    cat > /etc/xdg/kwalletrc.d/kde-security.conf << EOF
    [Wallet]
    Enabled=true
    First Use=false
    Use One Wallet=true
EOF

log_action "Implementing filesystem security"
cat >> /etc/fstab << EOF
# Secure mount options for /tmp
tmpfs   /tmp         tmpfs   defaults,noexec,nosuid,nodev   0  0
EOF

log_action "Configuring USBGuard"
usbguard generate-policy > /etc/usbguard/rules.conf
systemctl enable --now usbguard

# (Firefox)
log_action "Configuring Firefox security policies"
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

log_action "Configuring ClamAV"
systemctl enable --now clamav-freshclam
systemctl enable --now clamav-daemon

cat > /etc/cron.weekly/clamscan << EOF
#!/bin/bash
clamscan -r /home --log=/var/log/clamav/weekly.log
EOF
chmod +x /etc/cron.weekly/clamscan



log_action "Securing GRUB configuration"
if [ -f /etc/default/grub ]; then
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=".*"/GRUB_CMDLINE_LINUX_DEFAULT="quiet audit=1 selinux=1 enforcing=1 slab_nomerge=Y init_on_alloc=1 init_on_free=1"/' /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg
fi


# 18. Enable essential services
log_action "Enabling essential services"
    systemctl enable --now chronyd
    systemctl enable --now auditd
    systemctl enable --now fail2ban
    systemctl enable --now firewalld

log_action "Performing final system checks"


    systemctl is-active firewalld
    systemctl is-active auditd
    systemctl is-active usbguard


    sestatus

echo "Fedora KDE hardening completed. Please review /var/log/kde_hardening.log for details"
echo "It is recommended to reboot the system to apply all changes"
echo "After reboot, configure KDE Wallet and review application-specific Firejail profiles"
echo "Would you like to reboot the system? (y/n)"
read answer
if [ "$answer" = "y" ]; then
    reboot
fi
