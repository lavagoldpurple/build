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
board_config="$root_dir/config/boards/radxa-e20c.csc"
workflow="$root_dir/.github/workflows/build-e20c.yml"

for script in "$bootstrap" "$install_script" "$storage_script" "$media_script" "$app_script"; do
    sh -n "$script"
done
[ -f "$app_service" ] || { echo 'AIBox app service is missing' >&2; exit 1; }
[ -f "$mysql_service" ] || { echo 'MySQL service is missing' >&2; exit 1; }
grep -Fq 'PACKAGE_LIST_BOARD="adduser' "$board_config"
! grep -Eq 'mariadb|aibox-mariadb' "$board_config"
grep -Fq 'LABEL=AIBOX_MEDIA /mnt/aibox-media ext4 nofail,' "$board_config"
! grep -Fq 'LABEL=AIBOX_MEDIA /mnt/aibox-media ext4 nofail,noauto' "$board_config"
grep -Fq 'AIBOX_PACKAGE_URL' "$board_config"
grep -Fq 'AIBOX_PACKAGE_URL' "$workflow"
grep -Eq 'Requires=.*aibox-media-ready\.service' "$app_service"
grep -Eq 'Requires=.*aibox-mysql-bootstrap\.service' "$app_service"
grep -Fq 'mysql.service' "$app_script"
grep -Fq 'mysql-runtime.env' "$app_script"
grep -Fq '8.0.37' "$install_script"
grep -Fq 'MARKER=/userdata/.aibox-mysql-${MYSQL_VERSION}-initialized' "$install_script"
grep -Fq 'rm -rf -- /userdata/aibox' "$install_script"
grep -Fq '/mnt/aibox-media' "$install_script"
grep -Fq 'bind-address=127.0.0.1' "$root_dir/config/boards/radxa-e20c/rootfs/etc/mysql/my.cnf"
grep -Fq 'ExecStart=/usr/local/mysql/bin/mysqld' "$mysql_service"

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
bin_dir="$temp_dir/bin"
secure_dir="$temp_dir/secure"
mkdir -p "$bin_dir" "$secure_dir"
cat > "$bin_dir/fake-mysql" <<'EOF'
#!/bin/sh
cat >> "${AIBOX_MYSQL_SQL_LOG:?}"
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
    sh "$bootstrap" >/dev/null

runtime_env="$secure_dir/mysql-runtime.env"
[[ -f "$runtime_env" ]] || { echo 'MySQL runtime credentials were not generated' >&2; exit 1; }
password="$(sed -n 's/^MYSQL_APP_PASSWORD=//p' "$runtime_env")"
[[ "${#password}" == 64 ]] || { echo 'generated password is not 64 hex characters' >&2; exit 1; }
[[ "$password" =~ ^[0-9A-Fa-f]+$ ]] || { echo 'generated password is not hexadecimal' >&2; exit 1; }
if [[ "$(uname -s)" != MINGW* && "$(uname -s)" != MSYS* ]]; then
    [[ "$(stat -c '%a' "$runtime_env")" == 600 ]] || { echo 'runtime credentials are not mode 0600' >&2; exit 1; }
fi
grep -Fq 'CREATE DATABASE IF NOT EXISTS' "$sql_log"
grep -Fq "CREATE USER IF NOT EXISTS 'aibox'@'localhost'" "$sql_log"
grep -Fq "CREATE USER IF NOT EXISTS 'aibox'@'127.0.0.1'" "$sql_log"
grep -Fq 'GRANT ALL PRIVILEGES ON `aibox`.*' "$sql_log"
grep -Fq 'media filesystem is not ext4' "$media_script"
grep -Fq 'media label is not AIBOX_MEDIA' "$media_script"

echo 'PASS E20C MySQL runtime contracts'
