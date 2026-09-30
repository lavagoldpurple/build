#!/usr/bin/env bash
set -Eeuo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap="$root_dir/config/boards/radxa-e20c/rootfs/usr/libexec/aibox-mysql-bootstrap"
install_script="$root_dir/config/boards/radxa-e20c/rootfs/usr/libexec/aibox-mysql-install"
storage_script="$root_dir/config/boards/radxa-e20c/rootfs/usr/libexec/aibox-storage-init"
media_script="$root_dir/config/boards/radxa-e20c/rootfs/usr/libexec/aibox-media-ready"
app_script="$root_dir/config/boards/radxa-e20c/rootfs/usr/libexec/aibox-app-init"
app_service="$root_dir/config/boards/radxa-e20c/rootfs/lib/systemd/system/aibox-app-init.service"
mysql_service="$root_dir/config/boards/radxa-e20c/rootfs/lib/systemd/system/mysql.service"
mysql_wrapper="$root_dir/config/boards/radxa-e20c/rootfs/usr/local/bin/mysql"
mysqladmin_wrapper="$root_dir/config/boards/radxa-e20c/rootfs/usr/local/bin/mysqladmin"
serial_getty_dropin="$root_dir/config/boards/radxa-e20c/rootfs/etc/systemd/system/serial-getty@.service.d/10-aibox-library-isolation.conf"
getty_dropin="$root_dir/config/boards/radxa-e20c/rootfs/etc/systemd/system/getty@.service.d/10-aibox-library-isolation.conf"
board_config="$root_dir/config/boards/radxa-e20c.csc"
workflow="$root_dir/.github/workflows/build-e20c.yml"
boot_script="$root_dir/config/bootscripts/boot-radxa-e20c.cmd"
boot_env="$root_dir/config/bootenv/radxa-e20c.txt"

for script in "$bootstrap" "$install_script" "$storage_script" "$media_script" "$app_script" "$mysql_wrapper" "$mysqladmin_wrapper"; do
    sh -n "$script"
done
[ -f "$app_service" ] || { echo 'AIBox app service is missing' >&2; exit 1; }
[ -f "$mysql_service" ] || { echo 'MySQL service is missing' >&2; exit 1; }
[ -f "$serial_getty_dropin" ] || { echo 'serial getty library isolation drop-in is missing' >&2; exit 1; }
[ -f "$getty_dropin" ] || { echo 'getty library isolation drop-in is missing' >&2; exit 1; }
[ -f "$boot_script" ] || { echo 'E20C boot script is missing' >&2; exit 1; }
[ -s "$boot_env" ] || { echo 'E20C boot environment is missing or empty' >&2; exit 1; }
grep -Fq 'PACKAGE_LIST_BOARD="adduser' "$board_config"
! grep -Eq 'mariadb|aibox-mariadb' "$board_config"
grep -Fq 'LABEL=AIBOX_MEDIA /mnt/aibox-media ext4 nofail,' "$board_config"
! grep -Fq 'LABEL=AIBOX_MEDIA /mnt/aibox-media ext4 nofail,noauto' "$board_config"
grep -Fq 'AIBOX_PACKAGE_URL' "$board_config"
grep -Fq 'AIBOX_PACKAGE_URL' "$workflow"
grep -Fq 'declare -g BOOTSCRIPT="boot-radxa-e20c.cmd:boot.cmd"' "$board_config"
grep -Fq 'declare -g BOOTENV_FILE="radxa-e20c.txt"' "$board_config"
grep -Fq 'setenv fdtfile "rockchip/rk3528-radxa-e20c.dtb"' "$boot_script"
grep -Fq 'WARNING: armbianEnv.txt is empty' "$boot_script"
grep -Fq 'fdtfile=rockchip/rk3528-radxa-e20c.dtb' "$boot_env"
grep -Eq 'Requires=.*aibox-media-ready\.service' "$app_service"
grep -Eq 'Requires=.*aibox-mysql-bootstrap\.service' "$app_service"
grep -Fq 'mysql.service' "$app_script"
grep -Fq 'mysql-runtime.env' "$app_script"
grep -Fq '8.0.37' "$install_script"
grep -Fq 'MYSQL_VERSION_HOME=/opt/aibox/mysql-${MYSQL_VERSION}' "$install_script"
grep -Fq 'extract_dir="$MYSQL_WORK_ROOT/.mysql-extract.$$"' "$install_script"
grep -Fq 'extra_dir="$MYSQL_WORK_ROOT/.mysql-extra.$$"' "$install_script"
grep -Fq 'MYSQL_HOME exists and is not a symlink' "$install_script"
grep -Fq 'libnuma.so.1' "$install_script"
grep -Fq 'LD_LIBRARY_PATH=' "$install_script"
grep -Fq 'Prefer the verified ABI-5 files' "$install_script"
grep -Fq '[ ! -e "$MYSQL_VERSION_HOME/private-lib/libtinfo.so.5" ]' "$install_script"
grep -Fq 'Environment=LD_LIBRARY_PATH=/usr/local/mysql/private-lib' "$mysql_service"
grep -Fq 'chmod 0755 "${destination}/usr/local/bin/mysql"' "$board_config"
grep -Fq 'ExecStartPre=/usr/bin/chown mysql:mysql /run/mysqld' "$mysql_service"
grep -Fq 'ExecStartPre=/usr/bin/rm -f /run/mysqld/mysqld.sock' "$mysql_service"
! grep -Fq 'RuntimeDirectory=' "$mysql_service"
grep -Fq 'MYSQL_LIB_DIR=' "$bootstrap"
grep -Fq 'run_mysql()' "$bootstrap"
grep -Fq 'run_mysqladmin()' "$bootstrap"
grep -Fq 'MYSQL_ROOT_PASSWORD' "$bootstrap"
grep -Fq 'MYSQL_PWD=' "$bootstrap"
grep -Fq 'mysql_native_password' "$bootstrap"
! grep -R -n -E 'auth[_]socket' "$root_dir/config" "$root_dir/tools" >/dev/null
grep -Fq 'LD_LIBRARY_PATH="$MYSQL_HOME/private-lib' "$mysql_wrapper"
grep -Fq 'LD_LIBRARY_PATH="$MYSQL_HOME/private-lib' "$mysqladmin_wrapper"
grep -Fq 'Environment=LD_LIBRARY_PATH=' "$serial_getty_dropin"
grep -Fq 'Environment=LD_PRELOAD=' "$serial_getty_dropin"
grep -Fq 'Environment=LD_LIBRARY_PATH=' "$getty_dropin"
grep -Fq 'Environment=LD_PRELOAD=' "$getty_dropin"
grep -Fq 'MARKER=/userdata/.aibox-mysql-${MYSQL_VERSION}-initialized' "$install_script"
grep -Fq 'rm -rf -- /userdata/aibox' "$install_script"
grep -Fq '/mnt/aibox-media' "$install_script"
grep -Fq 'bind-address=127.0.0.1' "$root_dir/config/boards/radxa-e20c/rootfs/etc/mysql/my.cnf"
grep -Fq 'ExecStart=/usr/local/mysql/bin/mysqld' "$mysql_service"
! grep -Fq 'ExecStop=' "$mysql_service"

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
bin_dir="$temp_dir/bin"
secure_dir="$temp_dir/secure"
mkdir -p "$bin_dir" "$secure_dir"
cat > "$bin_dir/fake-mysql" <<'EOF'
#!/bin/sh
if [ -n "${MYSQL_PWD:-}" ] && [ ! -f "${AIBOX_MYSQL_FIRST_RUN_MARKER:?}" ]; then
    exit 1
fi
sql="$(cat)"
printf '%s\n' "$sql" >> "${AIBOX_MYSQL_SQL_LOG:?}"
case "$sql" in
    *"ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password"*)
        : > "$AIBOX_MYSQL_FIRST_RUN_MARKER"
        ;;
esac
exit 0
EOF
cat > "$bin_dir/fake-mysqladmin" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$bin_dir/fake-mysql" "$bin_dir/fake-mysqladmin"

sql_log="$temp_dir/sql.log"
PATH="$bin_dir:$PATH" \
    AIBOX_MYSQL_CLIENT="$bin_dir/fake-mysql" \
    AIBOX_MYSQL_ADMIN="$bin_dir/fake-mysqladmin" \
    AIBOX_MYSQL_SECURE_DIR="$secure_dir" \
    AIBOX_MYSQL_SQL_LOG="$sql_log" \
    AIBOX_MYSQL_FIRST_RUN_MARKER="$temp_dir/root-password-set" \
    sh "$bootstrap" >/dev/null

runtime_env="$secure_dir/mysql-runtime.env"
[[ -f "$runtime_env" ]] || { echo 'MySQL runtime credentials were not generated' >&2; exit 1; }
password="$(sed -n 's/^MYSQL_APP_PASSWORD=//p' "$runtime_env")"
root_password="$(sed -n 's/^MYSQL_ROOT_PASSWORD=//p' "$runtime_env")"
[[ "${#password}" == 64 ]] || { echo 'generated password is not 64 hex characters' >&2; exit 1; }
[[ "$password" =~ ^[0-9A-Fa-f]+$ ]] || { echo 'generated password is not hexadecimal' >&2; exit 1; }
[[ "${#root_password}" == 64 ]] || { echo 'generated root password is not 64 hex characters' >&2; exit 1; }
[[ "$root_password" =~ ^[0-9A-Fa-f]+$ ]] || { echo 'generated root password is not hexadecimal' >&2; exit 1; }
if [[ "$(uname -s)" != MINGW* && "$(uname -s)" != MSYS* ]]; then
    [[ "$(stat -c '%a' "$runtime_env")" == 600 ]] || { echo 'runtime credentials are not mode 0600' >&2; exit 1; }
fi
grep -Fq 'CREATE DATABASE IF NOT EXISTS' "$sql_log"
grep -Fq "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password" "$sql_log"
grep -Fq 'mysql_native_password' "$sql_log"
grep -Fq "CREATE USER IF NOT EXISTS 'aibox'@'localhost'" "$sql_log"
grep -Fq "CREATE USER IF NOT EXISTS 'aibox'@'127.0.0.1'" "$sql_log"
grep -Fq 'GRANT ALL PRIVILEGES ON `aibox`.*' "$sql_log"

PATH="$bin_dir:$PATH" \
    AIBOX_MYSQL_CLIENT="$bin_dir/fake-mysql" \
    AIBOX_MYSQL_ADMIN="$bin_dir/fake-mysqladmin" \
    AIBOX_MYSQL_SECURE_DIR="$secure_dir" \
    AIBOX_MYSQL_SQL_LOG="$sql_log" \
    AIBOX_MYSQL_FIRST_RUN_MARKER="$temp_dir/root-password-set" \
    sh "$bootstrap" >/dev/null
second_root_password="$(sed -n 's/^MYSQL_ROOT_PASSWORD=//p' "$runtime_env")"
[[ "$second_root_password" == "$root_password" ]] || { echo 'root password changed on repeat bootstrap' >&2; exit 1; }
grep -Fq 'AIBOX_MEDIA is not mounted' "$media_script"
grep -Fq 'media label is not AIBOX_MEDIA' "$media_script"
grep -Fq 'findmnt -rn -t ext4 -M /mnt/aibox-media' "$media_script"
grep -Fq 'findmnt -rn -t ext4 -M /mnt/aibox-media' "$install_script"
grep -Fq 'findmnt -rn -t ext4 -M /mnt/aibox-media' "$app_script"

echo 'PASS E20C MySQL runtime contracts'
