#!/bin/bash

set -e  

# Update and install prerequisites
apt-get update -y
apt-get install -y docker.io curl apt-transport-https gnupg lsb-release

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

# Set hostname
hostnamectl set-hostname master

# Initialize the Kubernetes control plane
kubeadm init --pod-network-cidr=10.244.0.0/16

# Set up kubectl for the root user
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Install Flannel CNI plugin
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
