############################################################
# Dockerfile to build sandbox for executing user code
############################################################

FROM base/archlinux

# update the arch build
RUN pacman -Syyu --noconfirm
RUN pacman -S sudo bc imagemagick graphicsmagick --noconfirm

# install languages
RUN pacman -S dmd ldc dub dtools --noconfirm
RUN pacman -S python python-pillow --noconfirm
RUN pacman -S gcc clang --noconfirm
RUN pacman -S jdk10-openjdk --noconfirm

