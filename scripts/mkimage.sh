#!/bin/bash -e
# Transform long options to short ones
for arg in "$@"; do
  shift
  case "$arg" in
    '--no-secureboot') set -- "$@" '-n'   ;;
	*)          	   set -- "$@" "$arg" ;;
  esac
done
# Default behaviour
SECUREBOOT_ON=true;

# Parse input option
while getopts "n" opt; do
  case "$opt" in
    'n') SECUREBOOT_ON=false ;;
    '?')
		echo "ERROR. Script usage $(basename \$0) -n [--no-secureboot]" >&2;
		exit 1
		;;
  esac
done

# At this stage we have all the unsigned binaries/files we need
# We check if we want secureboot or not and then we move accordingly
STAGING_BASE_PATH="staging"
STAGING_EFI_PATH="$STAGING_BASE_PATH/EFI"
SOURCE_DATE_EPOCH=1231006505
SECUREBOOT_DATE_EPOCH=1748476800

mkdir -p staging/EFI/boot
if $SECUREBOOT_ON; then
	# Create bootloader
	grub-mkimage \
        --disable-shim-lock \
        --compression="xz" \
        --format="x86_64-efi" \
        --pubkey="secureboot/signers/ccc.pgp" \
        --output="staging/EFI/boot/bootx64.efi.unsigned" \
        --config="grub-standalone.cfg" \
        --prefix="/boot/grub" \
	    all_video \
	    cat \
	    configfile \
	    crypto \
	    disk \
	    echo \
	    efi_gop \
	    fat \
	    gcry_dsa \
	    gcry_rsa \
	    gcry_sha256 \
	    gcry_sha512 \
	    gzio \
	    help \
	    iso9660 \
	    linux \
	    ls \
	    normal \
	    part_gpt \
	    part_msdos \
	    pgp \
	    search \
	    search_label \
	    squash4 \
	    test \
	    true

	# Sign bootloader and kernel with Yubikey
	# NOTE: key with ID=02 is the `Private key for Digital Signature` one
	# NOTE2: we make use of `faketime` here for reproducibility 'cause digital signatures are based on timestamps
	export PKCS11_MODULE_PATH=/usr/lib/x86_64-linux-gnu/libykcs11.so
	SB_TIMESTAMP=$(TZ=UTC date -d @${SECUREBOOT_DATE_EPOCH} +'%Y-%m-%d %H:%M:%S')

	read -p "Insert Signing Yubikey and press enter..."
	echo "Signing kernel and bootloader, please wait..."

	# Sign
	faketime -f "${SB_TIMESTAMP}" sbsign \
        --engine pkcs11 \
        --key 'pkcs11:id=%02;type=private' \
        --cert secureboot/keys/db.crt \
        --out staging/EFI/boot/bootx64.efi \
        staging/EFI/boot/bootx64.efi.unsigned
	faketime -f "${SB_TIMESTAMP}" sbsign \
        --engine pkcs11 \
        --key 'pkcs11:id=%02;type=private' \
        --cert secureboot/keys/db.crt \
        --out staging/live/vmlinuz \
        staging/live/vmlinuz.unsigned

	# Verify
	sbverify --list staging/EFI/boot/bootx64.efi
	sbverify --list staging/live/vmlinuz

	# Clean unsigned artifacts
	rm staging/live/vmlinuz.unsigned
	rm staging/EFI/boot/bootx64.efi.unsigned

	# Sign grub.cfg, kernel and intird with PGP
	# NOTE: optional, but useful since GRUB can perform PGP verification on boot
	faketime -f "${SB_TIMESTAMP}" gpg --local-user ccc --detach-sign grub-standalone.cfg
	faketime -f "${SB_TIMESTAMP}" gpg --local-user ccc --detach-sign staging/live/vmlinuz
	faketime -f "${SB_TIMESTAMP}" gpg --local-user ccc --detach-sign staging/live/initrd
	faketime -f "${SB_TIMESTAMP}" gpg --local-user ccc --detach-sign staging/boot/grub/grub.cfg

	# Set final ISO name
	ISO_NAME=livedeb
else
	# Create the bootloader
	grub-mkimage \
        --compression="xz" \
        --format="x86_64-efi" \
        --output="staging/EFI/boot/bootx64.efi" \
        --config="grub-standalone.cfg" \
        --prefix="/boot/grub" \
	    all_video \
	    cat \
	    configfile \
	    crypto \
	    disk \
	    echo \
	    efi_gop \
	    fat \
	    gzio \
	    help \
	    iso9660 \
	    linux \
	    ls \
	    normal \
	    part_gpt \
	    part_msdos \
	    search \
	    search_label \
	    squash4 \
	    test \
	    true

	# Here we simply rename the files in the expected convention
	mv staging/live/vmlinuz.unsigned staging/live/vmlinuz

	# Set final ISO name
	ISO_NAME=livedeb-nosb
fi

# Create EFI image
dd if=/dev/zero of="$STAGING_BASE_PATH"/efiboot.img bs=1M count=4
mformat -i "$STAGING_BASE_PATH"/efiboot.img -h 64 -t 32 -s 32 -N 0 ::
mmd -i "$STAGING_BASE_PATH"/efiboot.img ::/EFI
mmd -i "$STAGING_BASE_PATH"/efiboot.img ::/EFI/boot
mmd -i "$STAGING_BASE_PATH"/efiboot.img ::/EFI/HP
mcopy -i "$STAGING_BASE_PATH"/efiboot.img "$STAGING_EFI_PATH"/boot/bootx64.efi ::/EFI/boot/bootx64.efi
mcopy -i "$STAGING_BASE_PATH"/efiboot.img secureboot/keys/PK.cer ::/EFI/PK.cer
mcopy -i "$STAGING_BASE_PATH"/efiboot.img secureboot/keys/KEK.cer ::/EFI/KEK.cer
mcopy -i "$STAGING_BASE_PATH"/efiboot.img secureboot/keys/db.cer  ::/EFI/db.cer
mcopy -i "$STAGING_BASE_PATH"/efiboot.img secureboot/keys/DBX.cer  ::/EFI/DBX.cer
mcopy -i "$STAGING_BASE_PATH"/efiboot.img secureboot/keys/PK.bin ::/EFI/HP/PK.bin
mcopy -i "$STAGING_BASE_PATH"/efiboot.img secureboot/keys/KEK.bin ::/EFI/HP/KEK.bin
mcopy -i "$STAGING_BASE_PATH"/efiboot.img secureboot/keys/db.bin  ::/EFI/HP/db.bin
mcopy -i "$STAGING_BASE_PATH"/efiboot.img secureboot/keys/DBX.bin  ::/EFI/HP/DBX.bin

# Create ISO
find staging -print0 | xargs -0 touch -md "@${SOURCE_DATE_EPOCH}" && \
xorrisofs \
	-iso-level 3 \
	-o output/${ISO_NAME}.iso \
	-full-iso9660-filenames \
	-joliet \
	-rational-rock \
	-sysid LINUX \
	-volid "$(echo CCCDEB${TAG} | cut -c -32)" \
	-eltorito-alt-boot \
		-e efiboot.img \
		-no-emul-boot \
		-isohybrid-gpt-basdat \
	staging/ && \
sha256sum output/${ISO_NAME}.iso && \
chown -R satoshi:satoshi output/
