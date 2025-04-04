#!/bin/bash

# Variables
REPO="questdb/questdb"
PACKAGE_NAME="questdb"
DOWNLOAD_DIR="/tmp/questdb_download"
BUILD_DIR="/tmp/questdb_build"
SCRIPT_DIR="/tmp/questdb_scripts"
INSTALL_PREFIX="/opt/questdb"
DATA_DIR="/var/lib/questdb"
SYSTEMD_DIR="/etc/systemd/system"
SYSTEMD_SERVICE="$SYSTEMD_DIR/questdb.service"
DEBDEPS="default-jre-headless"
RHELDEPS="java-latest-openjdk-headless"
FILE_MAX_VALUE=1048576
MAX_MAP_COUNT_VALUE=1048576

# Ensure necessary tools are installed
command -v curl >/dev/null 2>&1 || {
  echo "curl is required but not installed."
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "jq is required but not installed."
  exit 1
}
# package binutils
command -v ar >/dev/null 2>&1 || {
  echo "ar is required but not installed."
  exit 1
}
# package rpm
command -v rpmbuild >/dev/null 2>&1 || {
  echo "rpmbuild is required but not installed."
  exit 1
}
# ruby gem
command -v fpm >/dev/null 2>&1 || {
  echo "fpm is required but not installed."
  exit 1
}

# Fetch the latest release information
RELEASE_INFO=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")
VERSION=$(echo "$RELEASE_INFO" | jq -r .tag_name)
ASSET_URL=$(echo "$RELEASE_INFO" | jq -r '.assets[] | select(.name | contains("no-jre") and endswith("bin.tar.gz")).browser_download_url')

if [[ -z "$VERSION" || -z "$ASSET_URL" ]]; then
  echo "Failed to fetch the latest release information."
  exit 1
fi

# Prepare directories
rm -rf "$DOWNLOAD_DIR" "$SCRIPT_DIR" "$BUILD_DIR"
mkdir -p "$DOWNLOAD_DIR" "$SCRIPT_DIR" "$BUILD_DIR$INSTALL_PREFIX" "$BUILD_DIR$DATA_DIR" "$BUILD_DIR$SYSTEMD_DIR"

# Download and extract QuestDB
curl -L "$ASSET_URL" -o "$DOWNLOAD_DIR/questdb.tar.gz"
tar -xzf "$DOWNLOAD_DIR/questdb.tar.gz" -C "$BUILD_DIR$INSTALL_PREFIX" --strip-components=1

# Create systemd service file
cat <<EOF >"$BUILD_DIR$SYSTEMD_SERVICE"
[Unit]
Description=QuestDB
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=2
LimitNOFILE=$FILE_MAX_VALUE
ExecStart=/usr/bin/java \\
  --add-exports java.base/jdk.internal.math=io.questdb \\
  -p $INSTALL_PREFIX/questdb.jar \\
  -m io.questdb/io.questdb.ServerMain \\
  -DQuestDB-Runtime-66535 \\
  -ea -Dnoebug \\
  -XX:+UnlockExperimentalVMOptions \\
  -XX:+AlwaysPreTouch \\
  -XX:+UseParallelOldGC \\
  -d $DATA_DIR
ExecReload=/bin/kill -s HUP \$MAINPID
ProtectSystem=full
StandardError=syslog
SyslogIdentifier=questdb

[Install]
WantedBy=multi-user.target
EOF

# Create before-installation script
cat <<EOF >"$SCRIPT_DIR/beforeinstall.sh"
# Update system parameters
echo "Updating system parameters..."
if grep -q "^fs.file-max" /etc/sysctl.conf; then
  sed -i "s/^fs.file-max.*/fs.file-max = $FILE_MAX_VALUE/" /etc/sysctl.conf
else
  echo "fs.file-max = $FILE_MAX_VALUE" >>/etc/sysctl.conf
fi

if grep -q "^vm.max_map_count" /etc/sysctl.conf; then
  sed -i "s/^vm.max_map_count.*/vm.max_map_count = $MAX_MAP_COUNT_VALUE/" /etc/sysctl.conf
else
  echo "vm.max_map_count = $MAX_MAP_COUNT_VALUE" >>/etc/sysctl.conf
fi

# Apply the changes
sysctl -p
EOF
chmod +x "$SCRIPT_DIR/beforeinstall.sh"

# Create after-installation script
cat <<EOF >"$SCRIPT_DIR/afterinstall.sh"
#!/bin/bash
echo "Enabling and starting QuestDB service..."
systemctl daemon-reload
systemctl enable questdb
systemctl start questdb
EOF
chmod +x "$SCRIPT_DIR/afterinstall.sh"

# Create before-remove script
cat <<EOF >"$SCRIPT_DIR/beforeremove.sh"
#!/bin/bash
echo "Disabling and stopping QuestDB service..."
systemctl daemon-reload
systemctl disable questdb
systemctl stop questdb
EOF
chmod +x "$SCRIPT_DIR/beforeremove.sh"

# Create after-remove script
cat <<EOF >"$SCRIPT_DIR/afterremove.sh"
#!/bin/bash
echo "Reloading systemd daemon..."
systemctl daemon-reload
EOF
chmod +x "$SCRIPT_DIR/afterremove.sh"

# Use FPM to create Debian and RPM packages
fpm -s dir -t deb \
  -n "$PACKAGE_NAME" \
  -v "${VERSION#v}" \
  --description "QuestDB: High-performance time-series database" \
  --url "https://questdb.io/" \
  --maintainer "Kyle Owen <kyle.owen@eecweathertech.com>" \
  --license "Apache-2.0" \
  --depends "$DEBDEPS" \
  --before-install "$SCRIPT_DIR/beforeinstall.sh" \
  --after-install "$SCRIPT_DIR/afterinstall.sh" \
  --before-remove "$SCRIPT_DIR/beforeremove.sh" \
  --after-remove "$SCRIPT_DIR/afterremove.sh" \
  -C "$BUILD_DIR" .

fpm -s dir -t rpm \
  -n "$PACKAGE_NAME" \
  -v "${VERSION#v}" \
  --description "QuestDB: High-performance time-series database" \
  --url "https://questdb.io/" \
  --maintainer "Kyle Owen <kyle.owen@eecweathertech.com>" \
  --license "Apache-2.0" \
  --depends "$RHELDEPS" \
  --before-install "$SCRIPT_DIR/beforeinstall.sh" \
  --after-install "$SCRIPT_DIR/afterinstall.sh" \
  --before-remove "$SCRIPT_DIR/beforeremove.sh" \
  --after-remove "$SCRIPT_DIR/afterremove.sh" \
  -C "$BUILD_DIR" .

echo "Packages created successfully."
