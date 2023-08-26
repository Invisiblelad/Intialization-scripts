!#/bin/bash

apt-get update
apt-get install docker.io
systemctl start docker

apt-get install curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
apt-get install kubeadm kubelet kubectl
swapoff -a
hostnamectl set-hostname master
kubeadm init --pod-network-cidr=10.244.0.0/16
