#!/bin/bash

# This script takes a clean Ubuntu Server 24.04 LTS AMI and installs and configures
# everything needed to deploy a app to it. The resulting state is a secure,
# production-ready instance.

set -euo pipefail

# --- AESTHETICS ---

GREEN='\033[0;32m'
ALIEN='\xF0\x9F\x91\xBD'
NC='\033[0m'

# --- HELPER FUNCTIONS ---

log() {
    echo -e "${GREEN}${ALIEN} $1${NC}"
}

# --- SECURITY FUNCTIONS ---

configure_firewall() {
    log "Configuring the firewall with ufw..."
    sudo apt-get install -y ufw
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ssh
    sudo ufw allow http
    sudo ufw allow https
    echo "y" | sudo ufw enable
}

harden_ssh() {
    log "Hardening SSH configuration..."
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    sudo tee /etc/ssh/sshd_config > /dev/null <<EOF
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
UsePrivilegeSeparation yes
KeyRegenerationInterval 3600
ServerKeyBits 1024
SyslogFacility AUTH
LogLevel INFO
LoginGraceTime 120
PermitRootLogin prohibit-password
StrictModes yes
RSAAuthentication yes
PubkeyAuthentication yes
IgnoreRhosts yes
RhostsRSAAuthentication no
HostbasedAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
PasswordAuthentication no
X11Forwarding no
X11DisplayOffset 10
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
UsePAM yes
MaxAuthTries 6
AllowUsers root user
EOF
    sudo systemctl restart ssh.service
}

setup_fail2ban() {
    log "Installing and configuring fail2ban..."
    sudo apt-get install -y fail2ban
    sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    sudo sed -i 's/bantime  = 10m/bantime  = 1h/' /etc/fail2ban/jail.local
    sudo sed -i 's/findtime  = 10m/findtime  = 30m/' /etc/fail2ban/jail.local
    sudo sed -i 's/maxretry = 5/maxretry = 3/' /etc/fail2ban/jail.local
    sudo systemctl enable fail2ban
    sudo systemctl start fail2ban
}

setup_user_ssh() {
    log "Setting up SSH for user user..."
    
    # Setup for user user
    sudo mkdir -p /home/user/.ssh
    sudo chmod 700 /home/user/.ssh

    # Check if root's authorized_keys exists and copy to user user
    if [ -f /root/.ssh/authorized_keys ]; then
        sudo cp /root/.ssh/authorized_keys /home/user/.ssh/
        sudo chmod 600 /home/user/.ssh/authorized_keys
        sudo chown -R user:user /home/user/.ssh
    else
        log "Warning: /root/.ssh/authorized_keys not found. You may need to set up SSH keys manually."
    fi

    log "NOTE: GitHub SSH key setup required for user user. Please follow the post-installation instructions."
}

# --- MAIN SCRIPT ---

# Update and upgrade packages
log "Updating and upgrading packages..."
sudo apt-get update -y
sudo apt-get upgrade -y

# Install essential packages
log "Installing required packages for a user production environment..."
sudo apt-get install -y git build-essential autoconf jq gnupg2 htop 

# Create user user and add sudo privileges
log "Creating user user..."
sudo adduser --disabled-password --gecos "" user
sudo chmod 755 /home/user
echo 'user ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/user
sudo chmod 0440 /etc/sudoers.d/user

# Install Certbot
log "Installing Certbot..."
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot

# Install additional useful tools
log "Installing additional tools..."
sudo apt-get install -y bat btop lsd

# Set up aliases
log "Setting up aliases for cat, top and ls..."
sudo tee /etc/profile.d/custom_aliases.sh > /dev/null <<EOF
# Custom aliases
alias ls='lsd -lah'
alias cat='batcat'
alias top='btop'
EOF

log "Alias setup complete. Changes will take effect on next login or shell start."

# Configure security
configure_firewall
harden_ssh
setup_fail2ban
setup_user_ssh

# Set hostname
sudo hostnamectl set-hostname ubuntu-user-production

# --- CLEANUP AND FINALIZATION ---

# Clean up
log "Cleaning up..."
sudo apt-get autoremove -y
sudo apt-get clean

# Delete command history
history -c


log "Ubuntu 24.04 LTS machine initial setup completed successfully."
log "IMPORTANT: Please follow the post-installation instructions for setting up the GitHub SSH key."

# --- POST-INSTALLATION INSTRUCTIONS ---

cat << EOF

POST-INSTALLATION INSTRUCTIONS:

1. SSH keys have been set up for the user user using the root's authorized_keys.
   Verify that you can SSH into the server as the user user:
   - ssh user@<your-server-ip>

2. Root login is still allowed with public key authentication for maintenance.
   However, it's recommended to use the user user for regular operations.

3. For GitHub SSH key setup for the user user:
   a. SSH into your server as the user user: ssh user@<your-server-ip>
   b. Generate a new SSH key: ssh-keygen -t ed25519 -C "your_email@users.noreply.github.com"
   c. Add the public key to your GitHub account: cat ~/.ssh/id_ed25519.pub
   d. Test the connection: ssh -T git@github.com

4. If you encounter any issues:
   - Check the SSH configuration: cat /etc/ssh/sshd_config
   - Verify firewall settings: sudo ufw status
   - Check SSH service status: sudo systemctl status ssh

5. Remember, password authentication has been disabled for security reasons. 
   Always use SSH keys to log into the server.

EOF