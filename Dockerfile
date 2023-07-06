FROM rust:1-bookworm as builder

ENV DEBIAN_FRONTEND=noninteractive
ENV SOURCE_DATE_EPOCH=1231006505

# installing packages in the container
RUN apt-get update


FROM builder AS downloads
# udev rules for the hardware wallets
RUN wget -q -P /etc/udev/rules.d \
	https://raw.githubusercontent.com/spesmilo/electrum/4.4.5/contrib/udev/20-hw1.rules \
	https://raw.githubusercontent.com/spesmilo/electrum/4.4.5/contrib/udev/51-coinkite.rules \
	https://raw.githubusercontent.com/spesmilo/electrum/4.4.5/contrib/udev/51-hid-digitalbitbox.rules \
	https://raw.githubusercontent.com/spesmilo/electrum/4.4.5/contrib/udev/51-safe-t.rules \
	https://raw.githubusercontent.com/spesmilo/electrum/4.4.5/contrib/udev/51-trezor.rules \
	https://raw.githubusercontent.com/spesmilo/electrum/4.4.5/contrib/udev/51-usb-keepkey.rules \
	https://raw.githubusercontent.com/spesmilo/electrum/4.4.5/contrib/udev/52-hid-digitalbitbox.rules \
	https://raw.githubusercontent.com/spesmilo/electrum/4.4.5/contrib/udev/53-hid-bitbox02.rules \
	https://raw.githubusercontent.com/spesmilo/electrum/4.4.5/contrib/udev/54-hid-bitbox02.rules \
	https://raw.githubusercontent.com/spesmilo/electrum/4.4.5/contrib/udev/55-usb-jade.rules
# Ethereum tools
RUN wget -q -O - https://gethstore.blob.core.windows.net/builds/geth-alltools-linux-amd64-1.12.0-e501b3b0.tar.gz \
  | tar -C /usr/local/bin --strip-components=1 -zx
RUN geth --version
RUN wget -q -O - https://github.com/wealdtech/ethdo/releases/download/v1.28.5/ethdo-1.28.5-linux-amd64.tar.gz \
  | tar -C /usr/local/bin -zx
RUN ethdo version
RUN wget -q -O - https://github.com/ethereum/staking-deposit-cli/releases/download/v2.5.0/staking_deposit-cli-d7b5304-linux-amd64.tar.gz \
  | tar -C /usr/local/bin --strip-components=2 -zx
RUN LC_ALL=C.UTF-8 deposit --help > /dev/null


FROM builder as cargo-install
RUN cargo install --locked --root /usr/local --git https://github.com/bitcoindevkit/bdk-cli \
	--tag v0.27.1 --features=reserves,electrum
RUN cargo install --locked --root /usr/local --git https://github.com/weareseba/electrum2descriptors \
	--branch feature/rust-1.69 


FROM builder
RUN apt-get install -y --no-install-recommends \
	build-essential \
	coreutils \
	debootstrap \
	fakechroot \
	grub-efi-amd64-bin \
	libsystemd-shared \
	mtools \
	python3-dev \
	python3-pip \
	python3-pytest \
	isolinux \
	squashfs-tools \
	syslinux-common \
	xorriso \
	xz-utils

WORKDIR LIVE_BOOT

RUN fakechroot debootstrap \
	--arch=amd64 \
	--include=linux-image-amd64,live-boot \
	--exclude=\
apt-utils,\
cron-daemon-common,\
cron,\
debconf-i18n,\
ifupdown,\
iproute2,\
iputils-ping,\
isc-dhcp-client,\
isc-dhcp-common,\
logrotate,\
nano,\
nftables,\
sensible-utils \
	--variant=fakechroot \
	bookworm \
	ROOTFS \
	http://deb.debian.org/debian/

# installing packages in the chroot
RUN fakechroot chroot ROOTFS apt-get install -y --no-install-recommends \
	dosfstools \
	electrum \
	evince \
	fdisk \
	firefox-esr \
	fonts-freefont-ttf \
	fonts-noto-mono \
	gpg \
	keepassxc \
	libykpiv2 \
	mousepad \
	openssh-client \
	p7zip-full \
	pcscd \
	python3-ecdsa \
	python3-hidapi \
	python3-libusb1 \
	python3-mnemonic \
	python3-pyaes \
	python3-pyqt5 \
	python3-semver \
	python3-trezor \
	python3-typing-extensions \
	systemd-resolved \
	systemd-timesyncd \
	thunar-archive-plugin \
	xarchiver \
	usbutils \
	xfce4 \
	xfce4-terminal \
	xinit \
	xserver-xorg \
	yubico-piv-tool \
	yubikey-manager \
	yubikey-personalization \
	yubioath-desktop

RUN fakechroot chroot ROOTFS /usr/bin/busybox --install -s

# TODO: add --install-option test
RUN pip3 install --no-warn-script-location --no-deps --root ROOTFS \
	bitbox02 \
	base58 \
	noiseprotocol \
	protobuf==3.20 \
	btchip-python \
	ckcc-protocol \
	keepkey

# set a timezone
RUN ln -sf /usr/share/zoneinfo/CET  ROOTFS/etc/localtime \
 && echo CET >                      ROOTFS/etc/timezone

# make directory for mounting USB sticks (defined in fstab)
RUN mkdir -p ROOTFS/media/usb

COPY resources/skeleton/ ROOTFS/

RUN fakechroot chroot ROOTFS usermod --expiredate 1 --shell /usr/sbin/nologin --password ! root # lock root account
RUN fakechroot chroot ROOTFS useradd -G users,lp,disk,adm,dialout -c 'Satoshi Nakamoto' -s /bin/bash satoshi \
 && fakechroot chroot ROOTFS chown -R satoshi:satoshi /home/satoshi
# copy downloaded files
COPY --from=downloads /etc/udev/rules.d ROOTFS/etc/udev/rules.d
COPY --from=downloads /usr/local/bin    ROOTFS/usr/local/bin

# copy binaries built with cargo to the chroot
COPY --from=cargo-install /usr/local/bin/bdk-cli              ROOTFS/usr/local/bin/
COPY --from=cargo-install /usr/local/bin/electrum2descriptors ROOTFS/usr/local/bin/

# remove not necessary components
RUN rm -r \
		ROOTFS/etc/.resolv.conf.systemd-resolved.bak \
		ROOTFS/etc/*- \
		ROOTFS/etc/motd \
		ROOTFS/usr/local/man \
		ROOTFS/usr/local/share/man \
		ROOTFS/usr/share/doc \
		ROOTFS/usr/share/locale \
		ROOTFS/usr/share/man \
		ROOTFS/var/cache/* \
		ROOTFS/var/lib/apt/lists \
		ROOTFS/var/lib/dpkg/info \
 && find ROOTFS -name '[a-z]*[.-]old' -delete

# remove not reproducibile files
RUN rm -r \
		ROOTFS/var/lib/dbus/machine-id \
		ROOTFS/var/log/* \
 && find ROOTFS/usr/lib       -name __pycache__ -type d -depth -exec rm -rf {} \; \
 && find ROOTFS/usr/local/lib -name __pycache__ -type d -depth -exec rm -rf {} \;

RUN mkdir -p staging/live
RUN fakechroot chroot ROOTFS \
	tar c --no-xattrs --no-same-owner \
	--exclude=/boot \
	--exclude=/dev/* \
	--exclude=/proc/* \
	--exclude=/sys/* \
	--sort=name / \
	| mksquashfs - \
	staging/live/filesystem.squashfs \
	-tar -exit-on-error

COPY resources/isolinux.cfg		staging/isolinux/isolinux.cfg
COPY resources/grub.cfg			staging/boot/grub/grub.cfg
COPY resources/grub-early.cfg	.

RUN mkdir -p staging/EFI/boot \
 && grub-mkimage \
	--compression="xz" \
	--format="x86_64-efi" \
	--config="grub-early.cfg" \
	--output="staging/EFI/boot/bootx64.efi" \
	--prefix="/boot/grub" \
	all_video disk part_gpt part_msdos linux normal configfile search \
	search_label efi_gop fat iso9660 cat echo ls test true help gzio

RUN mv ROOTFS/boot/vmlinuz-*          staging/live/vmlinuz \
 && mv ROOTFS/boot/initrd.img-*       staging/live/initrd \
 && mkdir -p                          staging/boot/grub/x86_64-efi/ \
 && mv /usr/lib/grub/x86_64-efi/*.*   staging/boot/grub/x86_64-efi/

RUN mformat -i staging/efiboot.img -C -f 1440 -N 0 :: \
 && mcopy   -i staging/efiboot.img -s staging/EFI ::

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
	staging/boot/syslinux/ \
	staging/live/initrd \
	staging/live/filesystem.squashfs \
	staging/EFI/boot/bootx64.efi \
	staging/EFI/boot/ \
	staging/* \
	staging \
 && xorrisofs \
	-iso-level 3 \
	-o /output/livedeb.iso \
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
		-e efiboot.img \
		-no-emul-boot \
		-isohybrid-gpt-basdat \
	staging/ \
 && sha256sum /output/livedeb.iso
