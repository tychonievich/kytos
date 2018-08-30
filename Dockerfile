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
RUN pacman -S gcc clang libpng --noconfirm
RUN pacman -S jdk10-openjdk --noconfirm
RUN pacman -S mono gtk-sharp-2 pkgconf --noconfirm
RUN pacman -S rust --noconfirm

# image libraries for package managers
# RUN cargo install image
# RUN cargo install png
RUN cd /tmp; dub fetch imageformats --cache=system; dub build imageformats

# install testing helpers
RUN pacman -S junit expect --noconfirm
