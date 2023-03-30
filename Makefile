USB_DISK ?= $(shell realpath /dev/disk/by-path/*usb* | head -n 1)

# creating a live system roughly by following https://willhaley.com/blog/custom-debian-live-environment/
iso: builder
	docker run --rm \
		-v ${PWD}/output:/output \
		--env SOURCE_DATE_EPOCH=$(shell git log -1 --format=%cd --date=unix) \
		--env TAG="$(shell git describe --long --always --dirty)" \
		live_builder_debian

builder:
	chmod -R g-w resources
	DOCKER_BUILDKIT=1 docker build \
		--build-arg http_proxy \
		--build-arg https_proxy \
		-t live_builder_debian .

run: iso
	qemu-system-x86_64 -cdrom output/debian-live.iso -m 2048 -bios /usr/share/ovmf/OVMF.fd

usb: iso
	test -b ${USB_DISK}
	@umount ${USB_DISK}* || :
	sudo dd bs=4M of=${USB_DISK} if=output/debian-live.iso status=progress
	sync

cd: iso
	wodim -eject -tao output/debian-live.iso

clear_docker:
	docker rmi live_builder_debian
	docker system prune -f
