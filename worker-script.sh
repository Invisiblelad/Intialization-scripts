#!/bin/bash

set -e  

# Update and install prerequisites
apt-get update -y
apt-get install -y docker.io curl apt-transport-https gnupg lsb-release

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Add Kubernetes apt repository
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list

# Install kubelet, kubeadm, kubectl
apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Disable swap
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

hostnamectl set-hostname worker
