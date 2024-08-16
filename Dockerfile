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


FROM builder
RUN apt-get install -y --no-install-recommends \
	build-essential \
	coreutils \
	grub-efi-amd64-bin \
	libsystemd-shared \
	mmdebstrap \
	mtools \
	python3-dev \
	python3-pip \
	python3-pytest \
	squashfs-tools \
	squashfs-tools-ng \
	xorriso \
	xz-utils


RUN mkdir -p staging/live \
 && mkdir -p staging/boot/grub/x86_64-efi \
 && mkdir -p staging/boot/syslinux/

COPY resources/skeleton/ resources/skeleton

# copy binaries built with cargo to the chroot
COPY --from=cargo-install /usr/local/bin/bdk-cli              /usr/local/bin/
COPY --from=cargo-install /usr/local/bin/electrum2descriptors /usr/local/bin/


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
		dhcping,\
		dosfstools,\
		electrum,\
		evince,\
		fdisk,\
		firefox-esr,\
		fonts-freefont-ttf,\
		fonts-noto-mono,\
		gpa,\
		gpg,\
		grub-efi-amd64-bin,\
		iptraf-ng,\
		isolinux,\
		keepassxc,\
		libykpiv2,\
		libnss-resolve,\
		linux-image-amd64,\
		live-boot,\
		mousepad,\
		openssh-client,\
		p7zip-full,\
		pcscd,\
		python3-ecdsa,\
		python3-hidapi,\
		python3-libusb1,\
		python3-mnemonic,\
		python3-pyaes,\
		python3-pyqt5,\
		python3-semver,\
		python3-trezor,\
		python3-typing-extensions,\
		rsync,\
		scdaemon,\
		syslinux-common,\
		systemd-resolved,\
		systemd-timesyncd,\
		thunar-archive-plugin,\
		usbutils,\
		vim,\
		wireshark,\
		wireshark-common,\
		xarchiver,\
		xfce4,\
		xfce4-terminal,\
		xinit,\
		xserver-xorg,\
		yubico-piv-tool,\
		yubikey-manager,\
		yubikey-personalization,\
		yubioath-desktop' \
	--customize-hook='chroot "$1" usermod --expiredate 1 --shell /usr/sbin/nologin --password ! root' \
	--customize-hook='chroot "$1" useradd -G users,lp,disk,adm,dialout -c "Satoshi Nakamoto" --home-dir /home/satoshi --create-home -s /bin/bash satoshi' \
	--customize-hook='chroot "$1" chmod 4755 /sbin/dhcping' \
	--customize-hook='chroot "$1" chmod 4755 /sbin/iptraf' \
	--customize-hook='chroot "$1" chmod 4755 /sbin/iptraf-ng' \
	--customize-hook='sync-in resources/skeleton/ /' \
	--customize-hook='sync-in /usr/local/bin/ /usr/local/bin/' \
	--customize-hook='chroot "$1" chown -R satoshi:satoshi /home/satoshi' \
	--customize-hook='pip3 install --no-cache-dir --no-warn-script-location --no-deps --root "$1" \
		bitbox02 \
		base58 \
		noiseprotocol \
		protobuf==3.20 \
		btchip-python \
		ckcc-protocol \
		keepkey' \
	--customize-hook='chroot "$1" /usr/bin/busybox --install -s' \
	--customize-hook='chroot "$1" systemctl enable systemd-networkd' \
	--customize-hook="download /vmlinuz staging/live/vmlinuz" \
	--customize-hook="download /initrd.img staging/live/initrd" \
	--customize-hook='set -e; for f in 20-hw1.rules 51-coinkite.rules 51-hid-digitalbitbox.rules 51-safe-t.rules 51-trezor.rules 51-usb-keepkey.rules 52-hid-digitalbitbox.rules 53-hid-bitbox02.rules 54-hid-bitbox02.rules 55-usb-jade.rules; do \
		wget -q -P "$1/etc/udev/rules.d" "https://raw.githubusercontent.com/spesmilo/electrum/4.4.5/contrib/udev/$f"; done' \
	--customize-hook='wget -q -O - https://gethstore.blob.core.windows.net/builds/geth-alltools-linux-amd64-1.13.11-8f7eb9cc.tar.gz | tar -C "$1/usr/local/bin" --strip-components=1 -zx' \
	--customize-hook='wget -q -O - https://github.com/wealdtech/ethdo/releases/download/v1.35.2/ethdo-1.35.2-linux-amd64.tar.gz | tar -C "$1/usr/local/bin" -zx' \
	--customize-hook='wget -q -O - https://github.com/ethereum/staking-deposit-cli/releases/download/v2.7.0/staking_deposit-cli-fdab65d-linux-amd64.tar.gz  | tar -C "$1/usr/local/bin" --strip-components=2 -zx' \
	--customize-hook='ln -sf /usr/share/zoneinfo/CET  "$1/etc/localtime"' \
	--customize-hook='mkdir -p "$1/media/usb"' \
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
	bookworm staging/live/filesystem.squashfs

COPY resources/isolinux.cfg     staging/isolinux/isolinux.cfg
COPY resources/grub.cfg         staging/boot/grub/grub.cfg
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

RUN mformat -i staging/efiboot.img -C -f 1440 -N 0 :: \
 && mcopy   -i staging/efiboot.img -s staging/EFI ::

CMD find staging -print0 | xargs -0 touch -md "@${SOURCE_DATE_EPOCH}" \
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
