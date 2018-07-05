#!/bin/bash

if docker 2>/dev/null
then
    echo "Docker found"
else
    echo "Please install docker first; e.g."
    echo "   pacman -S docker"
    echo "   apt-get install -y docker.io"
    echo "   yum install -y docker-io"
fi
systemctl start docker

echo "Creating docker image"
docker build -t 'sandbox_machine' - < Dockerfile
echo "Retrieving installed docker images"
docker images
