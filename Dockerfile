FROM rust:1-bookworm as builder

ENV DEBIAN_FRONTEND=noninteractive
ENV SOURCE_DATE_EPOCH=1231006505

RUN apt-get update \
 && apt-get upgrade -y


FROM builder as cargo-install
RUN cargo install --locked --root /usr/local --git https://github.com/bitcoindevkit/bdk-cli \
	--tag v0.27.1 --features=reserves,electrum
RUN cargo install --locked --root /usr/local --git https://github.com/weareseba/electrum2descriptors \
	--branch feature/rust-1.69


FROM debian:trixie-slim
ENV SOURCE_DATE_EPOCH=1231006505
ENV VERITY_SALT=08a0beacc11acabe72fa687107a743ed0680cfa985eac4386b6143ad93a563fc
ENV VERITY_UUID=12345678-1234-1234-1234-123456789abc
RUN apt-get update \
 && apt-get -y dist-upgrade \
 && apt-get install -y --no-install-recommends \
	autoconf \
	automake \
	bash \
	build-essential \
	coreutils \
	cpio \
	cryptsetup-bin \
	dkms \
	efitools \
	e2tools \
	e2fsprogs \
	faketime \
	gawk \
	gnupg \
	grub-efi-amd64 \
	initramfs-tools \
	libccid \
	libcryptsetup-dev \
	libengine-pkcs11-openssl \
	libsystemd-shared \
	libtool \
	locales \
	mmdebstrap \
	mtools \
	opensc-pkcs11 \
	openssl \
	pkg-config \
	python3-dev \
	python3-pip \
	python3-pytest \
	sbsigntool \
	squashfs-tools \
	squashfs-tools-ng \
	wget \
	xorriso \
	xz-utils \
	ykcs11 \
	yubico-piv-tool \
	yubikey-manager \
	zstd

# Create user
ARG UID
ARG GID
RUN groupadd -g ${GID} satoshi && \
	useradd -m -r -u ${UID} -g ${GID} -G users,lp,disk,adm,dialout -c "Satoshi Nakamoto" -s /bin/bash satoshi
WORKDIR /home/satoshi

# Copy res and useful files
COPY resources/skeleton/ resources/skeleton

# copy binaries built with cargo to the chroot
COPY --from=cargo-install /usr/local/bin/bdk-cli              /usr/local/bin/
COPY --from=cargo-install /usr/local/bin/electrum2descriptors /usr/local/bin/

# Set the locale
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Create staging folders
RUN mkdir -p staging/live && \
	mkdir -p staging/boot/grub/x86_64-efi && \
	mkdir -p staging/boot/syslinux/

# Create Live OS filesystem
RUN mmdebstrap \
	--variant=apt \
	--dpkgopt='path-exclude=/usr/share/man/*' \
	--dpkgopt='path-exclude=/usr/share/locale/*' \
	--dpkgopt='path-include=/usr/share/locale/locale.alias' \
	--dpkgopt='path-exclude=/usr/share/doc/*' \
	--dpkgopt='path-include=/usr/share/doc/*/copyright' \
	--dpkgopt='path-include=/usr/share/doc/*/changelog.Debian.*' \
	--include='\
		busybox,\
		curl,\
		cryptsetup-bin,\
		dosfstools,\
		efitools,\
		electrum,\
		evince,\
		fdisk,\
		firefox-esr,\
		fonts-freefont-ttf,\
		fonts-noto-mono,\
		gpg,\
		grub-efi-amd64-bin,\
		isolinux,\
		jq,\
		keepassxc,\
		libgl1,\
		libglib2.0-0,\
		libnss-resolve,\
		libpcsclite1,\
		libykpiv2,\
		libnss-resolve,\
		lightdm,\
		linux-image-amd64,\
		live-boot,\
		nodm,\
		mokutil,\
		mousepad,\
		mtools,\
		net-tools,\
		network-manager,\
		openssh-client,\
		p7zip-full,\
		pcscd,\
		python3-btchip,\
		python3-ecdsa,\
		python3-hidapi,\
		python3-mnemonic,\
		python3-pyaes,\
		python3-pyqt5,\
		python3-semver,\
		python3-trezor,\
		python3-typing-extensions,\
		python3-usb,\
		python3-usb1,\
		rsync,\
		scdaemon,\
		syslinux-common,\
		systemd-cryptsetup,\
		systemd-repart,\
		systemd-resolved,\
		systemd-timesyncd,\
		systemd-sysv,\
		thunar-archive-plugin,\
		uuid-runtime,\
		usbutils,\
		vim,\
		wget,\
		xarchiver,\
		xclip,\
		xfce4,\
		xfce4-terminal,\
		xinit,\
		xserver-xorg,\
		yubico-piv-tool,\
		yubikey-manager,\
		yubikey-personalization,\
		yubioath-desktop' \
	--customize-hook='chroot "$1" usermod --expiredate 1 --shell /usr/sbin/nologin --password ! root' \
	--customize-hook='chroot "$1" useradd -G users,lp,disk,adm,dialout,video,tty -c "Satoshi Nakamoto" --home-dir /home/satoshi --create-home -s /bin/bash satoshi' \
	--customize-hook='sync-in resources/skeleton/ /' \
	--customize-hook='sync-in /usr/local/bin/ /usr/local/bin/' \
	--customize-hook='chroot "$1" chown -R satoshi:satoshi /home/satoshi' \
	--customize-hook='pip3 install --no-cache-dir --no-warn-script-location --root "$1" \
		bitbox02==6.3.0 \
		base58 \
		jade-client==1.0.32 \
		noiseprotocol \
		protobuf==3.20 \
		ledger-bitcoin==0.2.2 \
		ledgercomm==1.2.1 \
		ckcc-protocol==0.7.7 \
		keepkey' \
	--customize-hook='chroot "$1" /usr/bin/busybox --install -s' \
	--customize-hook='chroot "$1" systemctl enable NetworkManager' \
	--customize-hook='chroot "$1" systemctl set-default graphical.target' \
	--customize-hook="download /vmlinuz staging/live/vmlinuz.unsigned" \
	--customize-hook="download /initrd.img staging/live/initrd" \
	--customize-hook='set -e; mkdir -p "$1/etc/udev/rules.d"; for f in 20-hw1.rules 51-coinkite.rules 51-hid-digitalbitbox.rules 51-safe-t.rules 51-trezor.rules 51-usb-keepkey.rules 52-hid-digitalbitbox.rules 53-hid-bitbox02.rules 54-hid-bitbox02.rules 55-usb-jade.rules; do \
		wget -q -P "$1/etc/udev/rules.d" "https://raw.githubusercontent.com/spesmilo/electrum/4.5.8/contrib/udev/$f"; done' \
	--customize-hook='wget -q -O - https://gethstore.blob.core.windows.net/builds/geth-alltools-linux-amd64-1.13.11-8f7eb9cc.tar.gz | tar -C "$1/usr/local/bin" --strip-components=1 -zx' \
	--customize-hook='wget -q -O - https://github.com/wealdtech/ethdo/releases/download/v1.35.2/ethdo-1.35.2-linux-amd64.tar.gz | tar -C "$1/usr/local/bin" -zx' \
	--customize-hook='wget -q -O - https://github.com/ethereum/staking-deposit-cli/releases/download/v2.7.0/staking_deposit-cli-fdab65d-linux-amd64.tar.gz  | tar -C "$1/usr/local/bin" --strip-components=2 -zx' \
	--customize-hook='ln -sf /usr/share/zoneinfo/CET  "$1/etc/localtime"' \
	--customize-hook='mkdir -p "$1/media/usb-rw"' \
	--customize-hook='mkdir -p "$1/media/usb-ro"' \
	--customize-hook='echo CET > "$1/etc/timezone"' \
	--customize-hook='sync-out /usr/lib/grub/x86_64-efi/ staging/boot/grub/x86_64-efi/' \
	--customize-hook='copy-out /usr/lib/ISOLINUX/isohdpfx.bin staging/boot/syslinux/' \
	--customize-hook='copy-out /usr/lib/ISOLINUX/isolinux.bin staging/boot/syslinux/' \
	--customize-hook='copy-out /usr/lib/syslinux/modules/bios/ldlinux.c32 staging/boot/syslinux/' \
	--customize-hook='copy-out /usr/lib/syslinux/modules/bios/libutil.c32 staging/boot/syslinux/' \
	--customize-hook='copy-out /usr/lib/syslinux/modules/bios/libcom32.c32 staging/boot/syslinux/' \
	--customize-hook='copy-out /usr/lib/syslinux/modules/bios/mboot.c32 staging/boot/syslinux/' \
	--customize-hook='rm -r "$1/etc/.resolv.conf.systemd-resolved.bak"' \
	--customize-hook='rm -r "$1/etc/"*-' \
	--customize-hook='rm -r "$1/etc/motd"' \
	--customize-hook='rm -r "$1/usr/local/man"' \
	--customize-hook='rm -r "$1/usr/local/share/man"' \
	--customize-hook='rm -r "$1/var/cache/"*' \
	--customize-hook='rm -r "$1/var/log/"*' \
	--customize-hook='rm -r "$1/var/lib/apt/lists"' \
	--customize-hook='rm -r "$1/var/lib/dpkg/info"' \
	--customize-hook='rm -rf "$1/tmp"' \
	--customize-hook='find "$1" -name "[a-z]*[.-]old" -delete' \
	--customize-hook='find "$1/usr/lib" -name __pycache__ -type d -depth -exec rm -rf {} \;' \
	--customize-hook='find "$1/usr/local/lib" -name __pycache__ -type d -depth -exec rm -rf {} \;' \
	trixie staging/live/filesystem.squashfs

# Copy secureboot and GRUB files
# https://wiki.debian.org/SecureBoot/VirtualMachine
# https://github.com/salrashid123/secure_boot
# https://superuser.com/questions/1660806/how-to-install-a-windows-guest-in-qemu-kvm-with-secure-boot-enabled
RUN mkdir -p secureboot
ADD secureboot/ secureboot/
COPY resources/grub.cfg staging/boot/grub/grub.cfg
COPY resources/grub-standalone.cfg .

# Create verity partition
RUN veritysetup format \
	--uuid=${VERITY_UUID} \
	--salt=${VERITY_SALT} \
	--root-hash-file=staging/live/filesystem.squashfs.roothash \
	staging/live/filesystem.squashfs staging/live/filesystem.squashfs.verity
RUN veritysetup verify \
	--root-hash-file=staging/live/filesystem.squashfs.roothash \
	staging/live/filesystem.squashfs staging/live/filesystem.squashfs.verity

# Patch initrd for missing system libraries for dm-verity (dlopen)
# - libcryptsetup.so
# - libuuid.so.1
# - libjson-c.so.5
RUN mkdir initrd-patched && \
	unmkinitramfs -v staging/live/initrd initrd-patched
RUN cp /usr/lib/x86_64-linux-gnu/libcryptsetup.so.12 initrd-patched/usr/lib/x86_64-linux-gnu/ && \
	cp /usr/lib/x86_64-linux-gnu/libuuid.so.1 initrd-patched/usr/lib/x86_64-linux-gnu/ && \
	cp /usr/lib/x86_64-linux-gnu/libjson-c.so.5 initrd-patched/usr/lib/x86_64-linux-gnu/
# NOTE: having different locales set can lead to different final checksums of the ISO (Docker takes locale from host's settings)
RUN cd initrd-patched && \
	find . -print0 | xargs -0 touch -md "@0" && \
	find . | sort -V | cpio -o -H newc --reproducible --device-independent --owner root:root > ../initrd.patched.img && \
	mv ../initrd.patched.img ../staging/live/initrd

# TODO
# Add M$ keys to DBX (https://github.com/microsoft/secureboot_objects.git)

# Copy script for creating the image
COPY scripts/mkimage.sh .
RUN chmod +x mkimage.sh

ENTRYPOINT ["./mkimage.sh"]
