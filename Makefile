USB_DISK ?= $(shell realpath /dev/disk/by-path/*usb* | head -n 1)
TAG := livedeb

# creating a live system roughly by following https://willhaley.com/blog/custom-debian-live-environment/
iso: builder
	docker run --rm \
		--volume ${PWD}/output:/output \
		--env SOURCE_DATE_EPOCH=$(shell git log -1 --format=%ct) \
		--env TAG="$(shell git describe --long --always --dirty)" \
		${TAG}

sign: iso
	sha256sum output/livedeb.iso | gpg --clearsign

builder:
	chmod -R go-w resources
	#DOCKER_BUILDKIT=1 \
	docker build \
		--build-arg http_proxy="${http_proxy}" \
		--build-arg https_proxy="${http_proxy}" \
		--build-arg HTTP_PROXY="${http_proxy}" \
		--build-arg HTTPS_PROXY="${http_proxy}" \
		--tag ${TAG} .

run: iso
	qemu-system-x86_64 -cdrom output/livedeb.iso -m 2048 -bios /usr/share/ovmf/OVMF.fd

run_yubi: iso
	qemu-system-x86_64 -cdrom output/livedeb.iso -m 2048 -bios /usr/share/ovmf/OVMF.fd -M q35 -usb -device usb-host,productid=0x0407,vendorid=0x1050

usb: iso
	test -b ${USB_DISK}
	@umount ${USB_DISK}* || :
	sudo dd bs=4M of=${USB_DISK} if=output/livedeb.iso status=progress
	sync

cd: iso
	wodim -eject -tao output/livedeb.iso

clear_docker:
	docker rmi ${TAG}
	docker system prune -f
