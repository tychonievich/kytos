############################################################
# Dockerfile to build sandbox for executing user code
############################################################

FROM archlinux

# update the arch build
RUN pacman -Scc
RUN pacman -Syyuu --noconfirm
RUN pacman -S --needed sudo bc imagemagick graphicsmagick ffmpeg --noconfirm
RUN pacman -S --needed unzip --noconfirm


# install languages
RUN pacman -S --needed dmd ldc dub dtools --noconfirm
RUN pacman -S --needed python python-pillow python-numpy python-scipy --noconfirm
RUN pacman -S --needed gcc clang libpng --noconfirm
RUN pacman -S --needed jdk-openjdk --noconfirm
RUN pacman -S --needed mono gtk-sharp-2 pkgconf --noconfirm
RUN pacman -S --needed rust --noconfirm
RUN pacman -S --needed go --noconfirm
RUN pacman -S --needed kotlin --noconfirm
RUN pacman -S --needed dart --noconfirm
RUN pacman -S --needed make --noconfirm
RUN pacman -S --needed ghc cabal-install --noconfirm
RUN pacman -S --needed npm typescript --noconfirm
RUN pacman -S --needed lua luajit --noconfirm
RUN pacman -S --needed openmp --noconfirm

# image libraries for package managers
# RUN cargo install image
# RUN cargo install png
RUN cd /tmp; dub fetch imageformats --cache=system; dub build imageformats; dub build -b release imageformats; chmod -R 777 /var/lib/dub/packages/
RUN cd /tmp; npm install --global jimp @types/node typescript

# install testing helpers
RUN pacman -S --needed junit expect --noconfirm
