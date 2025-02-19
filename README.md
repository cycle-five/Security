# Security Hardening Guide

## Server Hardening Scripts

### AlmaLinux 9 Server Hardening
See `harden_almalinux9.sh` for server-specific hardening measures.

### Proxmox VE Server Hardening

The `harden_proxmox.sh` script implements comprehensive security measures for Proxmox Virtual Environment while maintaining hypervisor functionality.

#### Features

1. **System Security**
   - System updates and package management
   - AppArmor configuration
   - Automatic security updates
   - AIDE file integrity monitoring
   - System auditing

2. **Proxmox-Specific Security**
   - Web interface hardening
   - Cluster security
   - VM security defaults
   - Storage security
   - Backup protection

3. **Network Security**
   - Proxmox firewall configuration
   - Fail2ban implementation
   - Snort IDS integration
   - Network isolation
   - SSH hardening

4. **Virtualization Security**
   - VM resource limits
   - VM isolation
   - Storage security
   - Network segregation
   - Protection flags

5. **Monitoring and Logging**
   - System accounting
   - Audit logging
   - AIDE integrity checking
   - Snort IDS monitoring
   - Service monitoring

#### Prerequisites

- Proxmox VE installation
- Root access
- Working internet connection
- Basic understanding of virtualization security

#### Usage

1. Make the script executable:
   ```bash
   chmod +x harden_proxmox.sh
   ```

2. Run the script as root:
   ```bash
   sudo ./harden_proxmox.sh
   ```

3. Review the logs at `/var/log/proxmox_hardening.log`

4. Reboot the system:
   ```bash
   sudo reboot
   ```

#### Important Notes

- **Backup**: Create a full backup of your Proxmox configuration and VMs before running this script
- **Cluster**: If running in a cluster, apply to each node separately
- **VMs**: All VMs will need to be stopped during the hardening process
- **Network**: Some network connectivity may be temporarily disrupted
- **Custom Settings**: Review firewall rules and security settings for your specific needs

#### Security Features

##### Proxmox Security
- Web interface HTTPS enforcement
- Cluster communication security
- VM resource protection
- Storage security measures
- Backup integrity

##### System Protection
- AppArmor enforcement
- AIDE file integrity
- System audit capabilities
- Automatic updates
- Service hardening

##### Network Security
- Proxmox firewall rules
- Network intrusion detection
- SSH hardening
- Network isolation
- Fail2ban protection

#### Troubleshooting

1. Check system logs:
   ```bash
   journalctl -xe
   ```

2. Review security logs:
   ```bash
   cat /var/log/proxmox_hardening.log
   ```

3. Check service status:
   ```bash
   systemctl status pve-firewall
   systemctl status auditd
   systemctl status snort
   ```

4. Verify security features:
   ```bash
   pvefw status  # Proxmox firewall
   aa-status     # AppArmor status
   aide --check  # File integrity
   ```

#### Post-Installation

After installation:

1. Review and customize firewall rules
2. Configure Snort IDS rules for your environment
3. Set up regular AIDE checks
4. Configure backup retention policies
5. Regular maintenance:
   - Monitor system logs
   - Check IDS alerts
   - Verify VM integrity
   - Update security policies

#### Support

For issues or questions:
1. Check the Proxmox documentation
2. Review system logs
3. Check the Proxmox forum
4. Verify security configurations

## Desktop Hardening Scripts

### Arch Linux Personal PC Hardening
See `harden_arch_personal.sh` for Arch Linux desktop hardening measures.

### Fedora KDE Personal PC Hardening
See `harden_fedora_kde.sh` for Fedora KDE desktop hardening measures.