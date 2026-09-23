# Rockchip RK3528 quad core 1-2GB SoC 2xGBe 16GB eMMC
BOARD_NAME="Radxa E20C"
BOARD_VENDOR="radxa"
BOARDFAMILY="rk35xx"
BOOTCONFIG="radxa_e20c_rk3528_defconfig"
BOOT_SOC="rk3528"
BOARD_MAINTAINER="mattx433"
INTRODUCED="2024"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
FULL_DESKTOP="no"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3528-radxa-e20c.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
PACKAGE_LIST_BOARD="mariadb-server mariadb-client cloud-guest-utils gdisk parted"

# The RK35xx bootloader occupies offsets above 8 MiB, so the first partition
# must keep the family default 16 MiB offset.
declare -g FIXED_IMAGE_SIZE=14336
declare -g USE_HOOK_FOR_PARTITION="yes"

function prepare_image_size__radxa_e20c_storage_layout() {
	declare -g USE_HOOK_FOR_PARTITION="yes"
	declare -g FIXED_IMAGE_SIZE=14336

	if [[ ${rootfs_size} -ge 3840 ]]; then
		exit_with_error "E20C rootfs does not fit its 4 GiB system partition" "${rootfs_size} MiB"
	fi
}

function create_partition_table__radxa_e20c_storage_layout() {
	local partition_script_output
	partition_script_output=$(
		cat <<- EOF
			label: gpt
			1 : name="armbi_root", start=16MiB, size=4096MiB, type=${PARTITION_TYPE_UUID_ROOT}
			2 : name="aibox_program", start=4112MiB, size=4096MiB, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
			3 : name="aibox_data", start=8208MiB, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
		EOF
	)

	display_alert "Creating E20C application storage layout" "root=4GiB program=4GiB data=remainder" "info"
	echo "${partition_script_output}" | run_host_command_logged sfdisk "${SDCARD}.raw" ||
		exit_with_error "Unable to create E20C partition layout"
}

function format_partitions__radxa_e20c_storage_layout() {
	local program_device="${LOOP}p2"
	local data_device="${LOOP}p3"
	local program_uuid data_uuid

	check_loop_device "${program_device}"
	check_loop_device "${data_device}"

	display_alert "Creating E20C program filesystem" "${program_device}" "info"
	run_host_command_logged mkfs.ext4 -q -m 0 -O ^orphan_file -L AIBOX_PROGRAM "${program_device}"
	run_host_command_logged tune2fs -o journal_data_writeback "${program_device}"

	display_alert "Creating E20C data filesystem" "${data_device}" "info"
	run_host_command_logged mkfs.ext4 -q -m 0 -O ^orphan_file -L AIBOX_DATA "${data_device}"
	run_host_command_logged tune2fs -o journal_data_writeback "${data_device}"

	run_host_command_logged mkdir -p "${MOUNT}/opt/aibox" "${MOUNT}/userdata" "${MOUNT}/mnt/aibox-media"
	run_host_command_logged mount "${program_device}" "${MOUNT}/opt/aibox"
	run_host_command_logged mount "${data_device}" "${MOUNT}/userdata"

	program_uuid="$(blkid -s UUID -o value "${program_device}")"
	data_uuid="$(blkid -s UUID -o value "${data_device}")"
	[[ -n ${program_uuid} && -n ${data_uuid} ]] || exit_with_error "Unable to read E20C filesystem UUIDs"

	cat <<- EOF >> "${SDCARD}/etc/fstab"
		UUID=${program_uuid} /opt/aibox ext4 defaults,noatime 0 2
		UUID=${data_uuid} /userdata ext4 defaults,noatime 0 2
		LABEL=AIBOX_MEDIA /mnt/aibox-media ext4 nofail,noauto,x-systemd.automount,x-systemd.device-timeout=10s 0 2
	EOF
}

function post_family_tweaks_bsp__enable_leds_radxa-e20c() {
	display_alert "Creating board support LEDs config for $BOARD"
	cat <<- EOF > "${destination}"/etc/armbian-leds.conf
		[/sys/class/leds/lan-led]
		trigger=netdev
		interval=50
		brightness=1
		link=1
		tx=1
		rx=1
		device_name=end1

		[/sys/class/leds/mmc1::]
		trigger=mmc1
		brightness=1

		[/sys/class/leds/sys-led]
		trigger=heartbeat
		brightness=1
		invert=0

		[/sys/class/leds/wan-led]
		trigger=netdev
		interval=50
		brightness=1
		link=1
		tx=1
		rx=1
		device_name=enp1s0
	EOF
}

function post_family_tweaks_bsp__install_radxa_e20c_runtime() {
	display_alert "Installing E20C storage and MariaDB runtime" "$BOARD"
	cp -a "${SRC}/config/boards/radxa-e20c/rootfs/." "${destination}/"
	chmod 0755 "${destination}/usr/libexec/aibox-"*

	local wants_dir="${destination}/etc/systemd/system/multi-user.target.wants"
	mkdir -p "${wants_dir}"
	ln -sfn /lib/systemd/system/aibox-storage-init.service "${wants_dir}/aibox-storage-init.service"
	ln -sfn /lib/systemd/system/aibox-mariadb-bootstrap.service "${wants_dir}/aibox-mariadb-bootstrap.service"
	ln -sfn /lib/systemd/system/mariadb.service "${wants_dir}/mariadb.service"

	mkdir -p "${destination}/DEBIAN"
	cat <<- EOF >> "${destination}/DEBIAN/conffiles"
		/etc/mysql/mariadb.conf.d/90-aibox.cnf
		/etc/systemd/system/mariadb.service.d/10-aibox-storage.conf
		/etc/apparmor.d/local/usr.sbin.mariadbd
		/etc/apparmor.d/local/usr.sbin.mysqld
	EOF
}

function post_customize_image__remove_default_radxa_e20c_mariadb_data() {
	if [[ -d "${SDCARD}/var/lib/mysql" ]]; then
		rm -rf -- "${SDCARD}/var/lib/mysql"
		mkdir -p "${SDCARD}/var/lib/mysql"
	fi
}
