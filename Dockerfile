FROM rust:1-bullseye

ENV DEBIAN_FRONTEND=noninteractive
ENV SOURCE_DATE_EPOCH=1231006505

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
	grub-efi-amd64-signed \
	isolinux \
	syslinux-common \
	mtools \
	squashfs-tools \
	xorriso \
	xz-utils \
	python3-pip \
	python3-dev \
	python3-pytest

RUN cargo install --root /usr --git https://github.com/bitcoindevkit/bdk-cli --tag v0.27.1 --features=reserves,electrum

WORKDIR LIVE_BOOT

RUN debootstrap \
	--arch=amd64 \
	--variant=minbase \
	bullseye \
	ROOTFS \
	http://deb.debian.org/debian/

# installing packages in the chroot
RUN chroot ROOTFS apt-get install --no-install-recommends -y \
	bind9-dnsutils \
	bind9-host \
	dosfstools \
	fdisk \
	electrum \
	evince \
	firefox-esr \
	fonts-freefont-ttf \
	keepassxc \
	libykpiv2 \
	linux-image-amd64 \
	live-boot \
	openssh-client \
	usbutils \
	pcscd \
	gpg \
	python3-ecdsa \
	python3-hidapi \
	python3-libusb1 \
	python3-mnemonic \
	python3-pyaes \
	python3-pyqt5 \
	python3-semver \
	python3-trezor \
	python3-typing-extensions \
	systemd-timesyncd \
	udev \
	xfce4 \
	xfce4-terminal \
	mousepad \
	xinit \
	xserver-xorg \
	yubioath-desktop \
	yubikey-manager \
	yubikey-personalization \
	yubikey-personalization-gui \
	yubico-piv-tool

# TODO: add --install-option test
RUN pip3 install --no-warn-script-location --no-deps --root ROOTFS \
	bitbox02 \
	base58 \
	noiseprotocol \
	protobuf==3.20 \
	btchip-python \
	ckcc-protocol \
	keepkey

# setting up udev rules for the hardware wallets in the chroot
ADD https://raw.githubusercontent.com/spesmilo/electrum/master/contrib/udev/20-hw1.rules                ROOTFS/etc/udev/rules.d/
ADD https://raw.githubusercontent.com/spesmilo/electrum/master/contrib/udev/51-coinkite.rules           ROOTFS/etc/udev/rules.d/
ADD https://raw.githubusercontent.com/spesmilo/electrum/master/contrib/udev/51-hid-digitalbitbox.rules  ROOTFS/etc/udev/rules.d/
ADD https://raw.githubusercontent.com/spesmilo/electrum/master/contrib/udev/51-safe-t.rules             ROOTFS/etc/udev/rules.d/
ADD https://raw.githubusercontent.com/spesmilo/electrum/master/contrib/udev/51-trezor.rules             ROOTFS/etc/udev/rules.d/
ADD https://raw.githubusercontent.com/spesmilo/electrum/master/contrib/udev/51-usb-keepkey.rules        ROOTFS/etc/udev/rules.d/
ADD https://raw.githubusercontent.com/spesmilo/electrum/master/contrib/udev/52-hid-digitalbitbox.rules  ROOTFS/etc/udev/rules.d/
ADD https://raw.githubusercontent.com/spesmilo/electrum/master/contrib/udev/53-hid-bitbox02.rules       ROOTFS/etc/udev/rules.d/
ADD https://raw.githubusercontent.com/spesmilo/electrum/master/contrib/udev/54-hid-bitbox02.rules       ROOTFS/etc/udev/rules.d/
ADD https://raw.githubusercontent.com/spesmilo/electrum/master/contrib/udev/55-usb-jade.rules           ROOTFS/etc/udev/rules.d/

# Ethereum tools
ADD https://github.com/ethereum/staking-deposit-cli/releases/download/v2.5.0/staking_deposit-cli-d7b5304-linux-amd64.tar.gz staking_deposit-cli-linux-amd64.tar.gz
RUN tar -C ROOTFS/usr/local/bin --strip-components=2 -zxf staking_deposit-cli-linux-amd64.tar.gz
RUN ls ROOTFS/usr/local/bin/deposit

ADD https://github.com/wealdtech/ethdo/releases/download/v1.28.5/ethdo-1.28.5-linux-amd64.tar.gz ethdo-linux-amd64.tar.gz
RUN tar -C ROOTFS/usr/local/bin -zxf ethdo-linux-amd64.tar.gz
RUN ROOTFS/usr/local/bin/ethdo version

ADD https://gethstore.blob.core.windows.net/builds/geth-alltools-linux-amd64-1.11.5-a38f4108.tar.gz geth-alltools-linux-amd64.tar.gz
RUN tar -C ROOTFS/usr/local/bin --strip-components=1 -zxf geth-alltools-linux-amd64.tar.gz

RUN chroot ROOTFS /usr/bin/busybox --install -s

# installing bdk-cli in the chroot
RUN cp /usr/bin/bdk-cli ROOTFS/usr/bin/

RUN ln -sf /usr/share/zoneinfo/CET ROOTFS/etc/localtime \
 && echo CET > ROOTFS/etc/timezone

RUN mkdir -p ROOTFS/media/usb

RUN ln -sf /run/systemd/resolve/resolv.conf  ROOTFS/etc/resolv.conf \
 && rm -r \
	ROOTFS/etc/machine-id \
	ROOTFS/var/lib/dbus/machine-id \
	ROOTFS/etc/motd \
	ROOTFS/usr/local/share/fonts/.uuid \
	ROOTFS/usr/share/doc/ \
	ROOTFS/usr/share/locale/ \
	ROOTFS/usr/share/man/ \
	ROOTFS/var/cache/* \
	ROOTFS/var/lib/apt/lists/ \
	ROOTFS/var/lib/dpkg/info/ \
	ROOTFS/var/log/*log \
	ROOTFS/var/log/apt/* \
 && find ROOTFS/usr/share       -name .uuid       -type f -delete \
 && find ROOTFS/usr/lib         -name __pycache__ -type d -exec rm -r "{}" + \
 && find ROOTFS/usr/local/lib   -name __pycache__ -type d -exec rm -r "{}" +

COPY resources/skeleton/ ROOTFS/

RUN chroot ROOTFS usermod --expiredate 1 --shell /usr/sbin/nologin --password ! root # lock root account
RUN chroot ROOTFS useradd -G users,lp,disk --create-home -c 'Satoshi Nakamoto' -s /bin/bash satoshi \
 && chroot ROOTFS chown -R satoshi:satoshi /home/satoshi \
 && chroot ROOTFS systemctl enable systemd-timesyncd

RUN mkdir -p staging/live \
 && mksquashfs \
	ROOTFS/ \
	staging/live/filesystem.squashfs \
	-e boot

COPY resources/isolinux.cfg		staging/isolinux/isolinux.cfg
COPY resources/grub.cfg			staging/boot/grub/grub.cfg
COPY resources/grub-early.cfg	.

RUN mkdir -p staging/efi/boot \
 && grub-mkimage \
	--compression="xz" \
	--format="x86_64-efi" \
	--config="grub-early.cfg" \
	--output="staging/efi/boot/bootx64.efi" \
	--prefix="/boot/grub" \
	all_video disk part_gpt part_msdos linux normal configfile search \
	search_label efi_gop fat iso9660 cat echo ls test true help gzio

RUN mv ROOTFS/boot/vmlinuz-*          staging/live/vmlinuz \
 && mv ROOTFS/boot/initrd.img-*       staging/live/initrd \
 && mkdir -p                          staging/boot/grub/x86_64-efi/ \
 && mv /usr/lib/grub/x86_64-efi/*.*   staging/boot/grub/x86_64-efi/

RUN mformat -i staging/boot/grub/efi.img -C -f 1440 -N 0 :: \
 && mcopy   -i staging/boot/grub/efi.img -s staging/efi ::

RUN mkdir -p staging/boot/syslinux/ \
 && mv  /usr/lib/ISOLINUX/isohdpfx.bin \
		/usr/lib/ISOLINUX/isolinux.bin \
		/usr/lib/syslinux/modules/bios/ldlinux.c32 \
		/usr/lib/syslinux/modules/bios/libutil.c32 \
		/usr/lib/syslinux/modules/bios/libcom32.c32 \
		/usr/lib/syslinux/modules/bios/mboot.c32 \
		staging/boot/syslinux/

CMD touch -md "@${SOURCE_DATE_EPOCH}" \
	staging/boot/grub/* \
	staging/boot/grub/ \
	staging/live/initrd \
	staging/live/filesystem.squashfs \
	staging/efi/boot/bootx64.efi \
	staging/efi/boot/ \
	staging/* \
	staging \
 && xorrisofs \
	-quiet \
	-output /output/debian-live.iso \
	-full-iso9660-filenames \
	-joliet \
	-rational-rock \
	-sysid LINUX \
	-volid "$(echo DEB${TAG} | cut -c -32)" \
	-isohybrid-mbr staging/boot/syslinux/isohdpfx.bin \
		-eltorito-boot boot/syslinux/isolinux.bin \
		-eltorito-catalog boot/syslinux/boot.cat \
		-no-emul-boot \
		-boot-load-size 4 \
		-boot-info-table \
	-eltorito-alt-boot \
		-e boot/grub/efi.img \
		-no-emul-boot \
		-isohybrid-gpt-basdat \
	staging/ \
 && sha256sum /output/debian-live.iso
