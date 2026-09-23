#!/usr/bin/env bash
set -Eeuo pipefail

image=${1:?usage: validate-e20c-image.sh <image.img>}
[[ -f "$image" ]] || { echo "missing image: $image" >&2; exit 1; }
[[ ${EUID} -eq 0 ]] || { echo 'run this validator as root' >&2; exit 1; }

loop=''
root_mount=''
program_mount=''
data_mount=''
cleanup() {
    set +e
    [[ -n "$root_mount" ]] && umount -R "$root_mount" 2>/dev/null || true
    [[ -n "$program_mount" ]] && umount -R "$program_mount" 2>/dev/null || true
    [[ -n "$data_mount" ]] && umount -R "$data_mount" 2>/dev/null || true
    [[ -n "$loop" ]] && losetup -d "$loop" 2>/dev/null || true
    [[ -n "${temp_dir:-}" ]] && rm -rf "$temp_dir"
}
trap cleanup EXIT

loop="$(losetup --find --show --partscan "$image")"
mapfile -t partitions < <(lsblk -lnpo NAME "$loop" | tail -n +2)
[[ ${#partitions[@]} -eq 3 ]] || { echo "expected three image partitions, got ${#partitions[@]}" >&2; exit 1; }

declare -A expected_labels=(
    [1]=armbi_root
    [2]=AIBOX_PROGRAM
    [3]=AIBOX_DATA
)
for number in 1 2 3; do
    device="${loop}p${number}"
    [[ -b "$device" ]] || { echo "missing partition: $device" >&2; exit 1; }
    label="$(blkid -s LABEL -o value "$device")"
    [[ "$label" == "${expected_labels[$number]}" ]] || {
        echo "unexpected label on $device: $label" >&2
        exit 1
    }
    [[ "$(blkid -s TYPE -o value "$device")" == ext4 ]] || {
        echo "unexpected filesystem on $device" >&2
        exit 1
    }
done

dump="$(sfdisk -d "$loop")"
grep -q 'start= *32768' <<<"$dump" || { echo 'root partition does not start at 16 MiB' >&2; exit 1; }
grep -q 'size= *8388608' <<<"$dump" || { echo 'root partition is not 4 GiB' >&2; exit 1; }
grep -q 'start= *8421376' <<<"$dump" || { echo 'program partition does not start after root' >&2; exit 1; }

temp_dir="$(mktemp -d)"
root_mount="$temp_dir/root"
program_mount="$temp_dir/program"
data_mount="$temp_dir/data"
mkdir -p "$root_mount"
mkdir -p "$program_mount" "$data_mount"
mount -o ro "${loop}p1" "$root_mount"
mount -o ro "${loop}p2" "$program_mount"
mount -o ro "${loop}p3" "$data_mount"

grep -Fq ' /opt/aibox ext4 ' "$root_mount/etc/fstab" || { echo 'program fstab entry missing' >&2; exit 1; }
grep -Fq ' /userdata ext4 ' "$root_mount/etc/fstab" || { echo 'data fstab entry missing' >&2; exit 1; }
grep -Fq 'LABEL=AIBOX_MEDIA /mnt/aibox-media ext4' "$root_mount/etc/fstab" || { echo 'media fstab entry missing' >&2; exit 1; }
[[ -f "$root_mount/etc/mysql/my.cnf" ]] || { echo 'MySQL config missing' >&2; exit 1; }
grep -Fq 'datadir=/userdata/aibox/database/mysql' "$root_mount/etc/mysql/my.cnf" || { echo 'MySQL datadir mismatch' >&2; exit 1; }
grep -Fq 'bind-address=127.0.0.1' "$root_mount/etc/mysql/my.cnf" || { echo 'MySQL bind address mismatch' >&2; exit 1; }
grep -Fq 'log-error=/userdata/aibox/logs/mysql/error.log' "$root_mount/etc/mysql/my.cnf" || { echo 'MySQL log path mismatch' >&2; exit 1; }
[[ ! -d "$root_mount/etc/mysql/mariadb.conf.d" ]] || { echo 'MariaDB configuration remains in image' >&2; exit 1; }
[[ -f "$root_mount/lib/systemd/system/aibox-storage-init.service" ]] || { echo 'storage service missing' >&2; exit 1; }
[[ -f "$root_mount/lib/systemd/system/aibox-mysql-install.service" ]] || { echo 'MySQL install service missing' >&2; exit 1; }
[[ -f "$root_mount/lib/systemd/system/aibox-mysql-bootstrap.service" ]] || { echo 'MySQL bootstrap service missing' >&2; exit 1; }
[[ -f "$root_mount/lib/systemd/system/mysql.service" ]] || { echo 'MySQL service missing' >&2; exit 1; }
mysql_payload="$(find "$program_mount/opt/aibox/factory" -type f -name 'mysql-8.0.37-linux-glibc2.17-aarch64.tar.xz' -print -quit)"
mysql_extra="$(find "$program_mount/opt/aibox/factory" -type f -name 'aibox-mysql-extra.tar.gz' -print -quit)"
libaio_payload="$(find "$program_mount/opt/aibox/factory" -type f -name 'libaio1_*_arm64.deb' -print -quit)"
manifest="$(find "$program_mount/opt/aibox/factory" -maxdepth 2 -type f -name manifest.json -print -quit)"
[[ -n "$mysql_payload" ]] || { echo 'MySQL 8.0.37 payload missing from program partition' >&2; exit 1; }
[[ -n "$mysql_extra" ]] || { echo 'MySQL compatibility payload missing from program partition' >&2; exit 1; }
[[ -n "$libaio_payload" ]] || { echo 'ARM64 libaio payload missing from program partition' >&2; exit 1; }
[[ -n "$manifest" ]] && grep -Fq '"database_version": "8.0.37"' "$manifest" || { echo 'firmware manifest is not MySQL 8.0.37' >&2; exit 1; }

umount "$root_mount"
root_mount=''
umount "$program_mount"
program_mount=''
umount "$data_mount"
data_mount=''
echo "PASS E20C image layout: $image"
