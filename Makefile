USB_DISK ?= $(shell realpath /dev/disk/by-path/*usb* | head -n 1)
TAG := livedeb
ISO_FILENAME := output/livedeb.iso
ISO_FILENAME_NOSB := output/livedeb-nosb.iso
UID := $(shell id -u)
GID := $(shell id -g)

# creating a live system roughly by following https://willhaley.com/blog/custom-debian-live-environment/
iso: ${ISO_FILENAME}
iso-nosb: ${ISO_FILENAME_NOSB}

# Creates and ISO by signing files for Secureboot
${ISO_FILENAME}: builder
	@git --version
	docker run \
		--rm \
		--interactive \
		--tty \
		--volume /run/pcscd:/run/pcscd:ro \
		--volume /run/user/${UID}/gnupg/S.gpg-agent:/root/.gnupg/S.gpg-agent:ro \
		--volume ${HOME}/.gnupg:/root/.gnupg:ro \
		--volume ${PWD}/output:/home/satoshi/output \
		--env SOURCE_DATE_EPOCH=$(shell git log -1 --format=%ct) \
		--env TAG="$(shell git log -1 --format=%h)" \
		${TAG}

# Creates and ISO without signing files for Secureboot
${ISO_FILENAME_NOSB}: builder
	@git --version
	docker run \
		--rm \
		--interactive \
		--tty \
		--volume /run/pcscd:/run/pcscd:ro \
		--volume /run/user/${UID}/gnupg/S.gpg-agent:/root/.gnupg/S.gpg-agent:ro \
		--volume ${HOME}/.gnupg:/root/.gnupg:ro \
		--volume ${PWD}/output:/home/satoshi/output \
		--env SOURCE_DATE_EPOCH=$(shell git log -1 --format=%ct) \
		--env TAG="$(shell git log -1 --format=%h)" \
		${TAG} --no-secureboot

sign:
	bash -c "if [ ! -f ${ISO_FILENAME} ]; then make ${ISO_FILENAME} ; fi"
	sha256sum ${ISO_FILENAME} | gpg --clearsign

sign-nosb:
	bash -c "if [ ! -f ${ISO_FILENAME_NOSB} ]; then make ${ISO_FILENAME_NOSB} ; fi"
	sha256sum ${ISO_FILENAME_NOSB} | gpg --clearsign

builder:
	chmod -R go-w resources
	#DOCKER_BUILDKIT=1 \
	docker build \
		--build-arg http_proxy="${http_proxy}" \
		--build-arg https_proxy="${http_proxy}" \
		--build-arg HTTP_PROXY="${http_proxy}" \
		--build-arg HTTPS_PROXY="${http_proxy}" \
		--build-arg UID="${UID}" \
		--build-arg GID="${GID}" \
		--tag ${TAG} .

run:
	echo "Press `Esc` to enter the Boot menu and enroll the certs from EFI directory"
	bash -c "if [ ! -f OVMF_VARS_4M.fd ]; then cp /usr/share/OVMF/OVMF_VARS_4M.fd ./ ; fi"
	bash -c "if [ ! -f ${ISO_FILENAME} ]; then make ${ISO_FILENAME} ; fi"
	qemu-system-x86_64 \
		-enable-kvm \
		-machine q35,smm=on \
		-m 2048 \
		-device virtio-rng-pci,rng=rng0 \
		-object rng-random,filename=/dev/urandom,id=rng0 \
		-global driver=cfi.pflash01,property=secure,value=on \
		-drive if=pflash,format=raw,unit=1,file="OVMF_VARS_4M.fd" \
		-drive if=pflash,format=raw,unit=0,file="/usr/share/OVMF/OVMF_CODE_4M.secboot.fd",readonly=on \
		-boot menu=on \
		-cdrom ${ISO_FILENAME}

run-nosb:
	bash -c "if [ ! -f ${ISO_FILENAME_NOSB} ]; then make ${ISO_FILENAME_NOSB} ; fi"
	qemu-system-x86_64 \
		-enable-kvm \
		-machine q35,smm=on \
		-m 2048 \
		-object rng-random,filename=/dev/urandom,id=rng0 \
		-bios /usr/share/ovmf/OVMF.fd \
		-cdrom ${ISO_FILENAME_NOSB}

run_yubi: iso
	qemu-system-x86_64 -cdrom output/livedeb.iso -m 2048 -bios /usr/share/ovmf/OVMF.fd -M q35 -usb -device usb-host,productid=0x0407,vendorid=0x1050

usb: ${ISO_FILENAME}
	test -b ${USB_DISK}
	@umount ${USB_DISK}* || :
	sudo dd bs=4M of=${USB_DISK} if=${ISO_FILENAME} status=progress
	sync

cd: ${ISO_FILENAME}
	wodim -eject -tao ${ISO_FILENAME}

clear_docker:
	docker rmi ${TAG} || :
	docker system prune -f
