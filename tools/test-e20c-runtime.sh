#!/usr/bin/env bash
set -Eeuo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap="$root_dir/config/boards/radxa-e20c/rootfs/usr/libexec/aibox-mariadb-bootstrap"
init_script="$root_dir/config/boards/radxa-e20c/rootfs/usr/libexec/aibox-mariadb-init"
storage_script="$root_dir/config/boards/radxa-e20c/rootfs/usr/libexec/aibox-storage-init"
media_script="$root_dir/config/boards/radxa-e20c/rootfs/usr/libexec/aibox-media-ready"

for script in "$bootstrap" "$init_script" "$storage_script" "$media_script"; do
    sh -n "$script"
done

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
bin_dir="$temp_dir/bin"
secure_dir="$temp_dir/secure"
mkdir -p "$bin_dir" "$secure_dir"
cat > "$bin_dir/fake-mariadb" <<'EOF'
#!/bin/sh
cat >> "${AIBOX_MARIADB_SQL_LOG:?}"
exit 0
EOF
cat > "$bin_dir/fake-mariadb-admin" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$bin_dir/fake-mariadb" "$bin_dir/fake-mariadb-admin"
cat > "$secure_dir/mariadb-runtime.env" <<'EOF'
MYSQL_APP_DATABASE=aibox
MYSQL_APP_USER=aibox
MYSQL_APP_PASSWORD=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
EOF
chmod 0600 "$secure_dir/mariadb-runtime.env"

sql_log="$temp_dir/sql.log"
PATH="$bin_dir:$PATH" \
    AIBOX_MARIADB_CLIENT=fake-mariadb \
    AIBOX_MARIADB_ADMIN=fake-mariadb-admin \
    AIBOX_MARIADB_SECURE_DIR="$secure_dir" \
    AIBOX_MARIADB_SQL_LOG="$sql_log" \
    sh "$bootstrap" >/dev/null

if [[ "$(uname -s)" != MINGW* && "$(uname -s)" != MSYS* ]]; then
    [[ "$(stat -c '%a' "$secure_dir/mariadb-runtime.env")" == 600 ]] || {
        echo 'runtime credentials are not mode 0600' >&2
        exit 1
    }
fi
grep -Fq 'CREATE DATABASE IF NOT EXISTS' "$sql_log"
grep -Fq "CREATE USER IF NOT EXISTS 'aibox'@'localhost'" "$sql_log"
grep -Fq "CREATE USER IF NOT EXISTS 'aibox'@'127.0.0.1'" "$sql_log"
grep -Fq 'GRANT ALL PRIVILEGES ON `aibox`.*' "$sql_log"
grep -Fq 'existing data directory retained' "$init_script"
grep -Fq 'data directory is non-empty but not initialized' "$init_script"
grep -Fq 'media filesystem is not ext4' "$media_script"
grep -Fq 'media label is not AIBOX_MEDIA' "$media_script"

echo 'PASS E20C runtime contracts'
