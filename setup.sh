#!/bin/bash
# One-time setup for Ubuntu: checks virtualization and installs Docker.
set -e

echo "== Checking CPU virtualization =="
if ! grep -Eqc '(vmx|svm)' /proc/cpuinfo; then
    echo "Your CPU does not report VT-x/AMD-V. Enable 'Virtualization' (Intel VT-x / AMD SVM)"
    echo "in your BIOS/UEFI settings, reboot, and run this again."
    exit 1
fi

if [ ! -e /dev/kvm ]; then
    echo "Loading KVM kernel module..."
    sudo modprobe kvm_intel 2>/dev/null || sudo modprobe kvm_amd 2>/dev/null || true
fi
if [ ! -e /dev/kvm ] && grep -qi microsoft /proc/version; then
    echo "/dev/kvm is missing inside WSL. In Windows, create C:\\Users\\<you>\\.wslconfig containing:"
    echo "    [wsl2]"
    echo "    nestedVirtualization=true"
    echo "then run 'wsl --shutdown' in PowerShell, reopen Ubuntu and run ./setup.sh again."
    echo "(Needs Windows 11 and virtualization enabled in BIOS.)"
    exit 1
fi
if [ ! -e /dev/kvm ]; then
    echo "/dev/kvm still missing. Enable virtualization in BIOS/UEFI and reboot."
    exit 1
fi
echo "KVM OK."

echo "== Checking Docker =="
if ! command -v docker > /dev/null || ! docker compose version > /dev/null 2>&1; then
    echo "Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y docker.io docker-compose-v2 || {
        echo "Falling back to Docker's official install script..."
        curl -fsSL https://get.docker.com | sudo sh
    }
fi
if ! sudo docker info > /dev/null 2>&1; then
    # WSL without systemd has no systemctl; fall back to the service command.
    sudo systemctl enable --now docker 2>/dev/null || sudo service docker start
fi
if ! groups | grep -qw docker; then
    sudo usermod -aG docker "$USER"
    echo "Added $USER to the docker group. Log out and back in (or run 'newgrp docker'),"
    echo "then run: ./phone.sh start"
    exit 0
fi

[ -f .env ] || cp .env.example .env
echo "Setup done. Now run: ./phone.sh start"
