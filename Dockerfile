FROM debian:11.3

ENV DEBIAN_FRONTEND=noninteractive
ENV SOURCE_DATE_EPOCH=1231006505
ENV http_proxy=$http_proxy
ENV https_proxy=$http_proxy
ENV HTTP_PROXY=$http_proxy
ENV HTTPS_PROXY=$http_proxy

# installing packages in the container
RUN apt-get update
RUN apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cpio \
        curl \
        coreutils \
        debootstrap \
        grub-efi-amd64-bin \
        mtools \
        squashfs-tools \
        xorriso \
        xz-utils

RUN sh -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
RUN /root/.cargo/bin/cargo install --root /usr --git https://github.com/bitcoindevkit/bdk-cli --tag v0.5.0 --features=reserves,electrum

RUN mkdir -p /LIVE_BOOT \
 && debootstrap \
        --arch=amd64 \
        --variant=minbase \
        bullseye \
        /LIVE_BOOT/chroot \
        http://ftp.ch.debian.org/debian/

# installing packages in the chroot
RUN chroot /LIVE_BOOT/chroot sh -c "apt-get update && \
	apt-get install --no-install-recommends -y \
        build-essential \
        dosfstools \
        electrum \
        evince \
        fdisk \
        firefox-esr \
        fonts-freefont-ttf \
        keepassxc \
        mtools \
        libgl1 \
        libglib2.0-0 \
        libpython3-dev \
        libykpiv2 \
        linux-image-amd64 \
        live-boot \
        openssh-client \
        pcscd \
        python3 \
        python3-btchip \
        python3-cryptography \
        python3-dev \
        python3-future \
        python3-gnupg \
        python3-lxml \
        python3-pip \
        python3-pycryptodome \
        python3-pyqt5 \
        python3-pytest \
        python3-pytest-cov \
        python3-setuptools \
        python3-trezor \
        python3-wheel \
        python3-yubikey-manager \
        systemd-timesyncd \
        udev \
        vim \
        xfce4 \
        xfce4-terminal \
        mousepad \
        xinit \
        xserver-xorg-core \
        xserver-xorg \
	yubioath-desktop \
	yubikey-manager \
	yubikey-personalization \
	yubikey-personalization-gui \
	yubico-piv-tool \
    && pip3 install --upgrade pip \
    && pip3 install wheel \
    && pip3 install --upgrade keepkey \
    && pip3 install --upgrade btchip-python \
    && pip3 install --upgrade ckcc-protocol \
    && pip3 install --upgrade bitbox02 \	
    && pip3 install protobuf==3.20 \	
    "
RUN chroot /LIVE_BOOT/chroot /usr/bin/busybox --install -s

# setting up udev rules for the hardware wallets in the chroot
RUN chroot /LIVE_BOOT/chroot sh -c "wget -q -O - https://raw.githubusercontent.com/LedgerHQ/udev-rules/master/add_udev_rules.sh | bash || true"
RUN chroot /LIVE_BOOT/chroot sh -c "curl -OL https://raw.githubusercontent.com/keepkey/udev-rules/master/51-usb-keepkey.rules \
    && mv 51-usb-keepkey.rules /usr/lib/udev/rules.d \
    && udevadm control --reload-rules || true"

# installing bdk-cli in the chroot
RUN cp /usr/bin/bdk-cli  /LIVE_BOOT/chroot/usr/bin/bdk-cli

RUN ln -sf /usr/share/zoneinfo/CET /LIVE_BOOT/chroot/etc/localtime \
 && echo CET > /LIVE_BOOT/chroot/etc/timezone \
 && mkdir -p /LIVE_BOOT/chroot/media/usb

RUN chroot /LIVE_BOOT/chroot apt-get autoremove -y \
        build-essential \
        libpython3-dev \
 && chroot /LIVE_BOOT/chroot apt-get clean \
 && ln -sf /run/systemd/resolve/resolv.conf  /LIVE_BOOT/chroot/etc/resolv.conf \
 && rm -rf \
        /LIVE_BOOT/chroot/etc/machine-id \
        /LIVE_BOOT/chroot/var/lib/dbus/machine-id \
        /LIVE_BOOT/chroot/etc/motd \
        /LIVE_BOOT/chroot/tmp/* \
        /LIVE_BOOT/chroot/usr/local/share/fonts/.uuid \
        /LIVE_BOOT/chroot/usr/share/doc/ \
        /LIVE_BOOT/chroot/usr/share/locale/ \
        /LIVE_BOOT/chroot/usr/share/man/ \
        /LIVE_BOOT/chroot/var/cache/* \
        /LIVE_BOOT/chroot/var/lib/apt/lists/ \
        /LIVE_BOOT/chroot/var/lib/dpkg/info/ \
        /LIVE_BOOT/chroot/var/log/*log \
        /LIVE_BOOT/chroot/var/log/apt/* \
        /LIVE_BOOT/chroot/root/.gnupg/random_seed \
        /LIVE_BOOT/chroot/root/.gnupg/pubring.kbx \
        /LIVE_BOOT/chroot/root/.cache/pip \
 && sh -c "find /LIVE_BOOT/chroot/usr/share/fonts -name .uuid       -type f -depth -exec rm -rf {} \;" \
 && sh -c "find /LIVE_BOOT/chroot/usr/lib         -name __pycache__ -type d -depth -exec rm -rf {} \;" \
 && sh -c "find /LIVE_BOOT/chroot/usr/local/lib   -name __pycache__ -type d -depth -exec rm -rf {} \;"

WORKDIR /
COPY resources/skeleton/                        /LIVE_BOOT/chroot/

RUN chroot /LIVE_BOOT/chroot usermod --expiredate 1 --shell /usr/sbin/nologin --password ! root # lock root account
RUN chroot /LIVE_BOOT/chroot useradd -G users,lp,disk --create-home -c 'Satoshi Nakamoto' -s /bin/bash satoshi \
 && chroot /LIVE_BOOT/chroot chown -R satoshi:satoshi /home/satoshi \
 && chroot /LIVE_BOOT/chroot systemctl enable systemd-timesyncd

RUN mkdir -p /LIVE_BOOT/staging/live \
 && mksquashfs \
        /LIVE_BOOT/chroot \
        /LIVE_BOOT/staging/live/filesystem.squashfs \
        -e boot

COPY resources/grub.cfg                 /LIVE_BOOT/staging/boot/grub/grub.cfg
COPY resources/grub-standalone.cfg      /LIVE_BOOT/

RUN mkdir -p /LIVE_BOOT/staging/EFI/boot \
 && grub-mkimage \
        --compression="xz" \
        --format="x86_64-efi" \
        --output="/LIVE_BOOT/staging/EFI/boot/bootx64.efi" \
        --config="/LIVE_BOOT/grub-standalone.cfg" \
        --prefix="/boot/grub" \
        all_video disk part_gpt part_msdos linux normal configfile search \
        search_label efi_gop fat iso9660 cat echo ls test true help gzio

RUN touch /LIVE_BOOT/staging/DEBIAN_CUSTOM \
 && mv /LIVE_BOOT/chroot/boot/vmlinuz-*          /LIVE_BOOT/staging/live/vmlinuz \
 && mv /LIVE_BOOT/chroot/boot/initrd.img-*       /LIVE_BOOT/staging/live/initrd \
 && mkdir -p                                    /LIVE_BOOT/staging/boot/grub/x86_64-efi/ \
 && mv /usr/lib/grub/x86_64-efi/*.*             /LIVE_BOOT/staging/boot/grub/x86_64-efi/

RUN mformat -i /LIVE_BOOT/staging/efiboot.img -C -f 1440 -N 0 :: \
 && mcopy   -i /LIVE_BOOT/staging/efiboot.img -s /LIVE_BOOT/staging/EFI ::

CMD touch -md "@${SOURCE_DATE_EPOCH}" \
        /LIVE_BOOT/staging/boot/grub/* \
        /LIVE_BOOT/staging/boot/grub/ \
        /LIVE_BOOT/staging/live/initrd \
        /LIVE_BOOT/staging/live/filesystem.squashfs \
        /LIVE_BOOT/staging/EFI/boot/bootx64.efi \
        /LIVE_BOOT/staging/EFI/boot/ \
        /LIVE_BOOT/staging/* \
        /LIVE_BOOT/staging \
 && xorrisofs \
        -iso-level 3 \
        -o "output/debian-live.iso" \
        -full-iso9660-filenames \
        -joliet \
        -rational-rock \
        -sysid LINUX \
        -volid "$(echo DEB${TAG} | cut -c -32)" \
        -eltorito-alt-boot \
                -e efiboot.img \
                -no-emul-boot \
                -isohybrid-gpt-basdat \
        /LIVE_BOOT/staging \
 && sha256sum output/debian-live.iso
