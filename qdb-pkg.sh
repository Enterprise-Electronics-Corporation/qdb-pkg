#!/bin/bash

# Variables
# Repository and package details
REPO="questdb/questdb"  # GitHub repository for QuestDB
PACKAGE_NAME="questdb"  # Name of the package

# Directories for downloading, building, and installing QuestDB
DOWNLOAD_DIR="/tmp/questdb_download"  # Temporary directory for downloads
BUILD_DIR="/tmp/questdb_build"  # Temporary directory for building the package
SCRIPT_DIR="/tmp/questdb_scripts"  # Directory for installation scripts

# Systemd service configuration
SYSTEMD_DIR="/etc/systemd/system"  # Directory for systemd service files
SYSTEMD_SERVICE="$SYSTEMD_DIR/questdb.service"  # Path to the QuestDB systemd service file

# Package dependencies
DEBDEPS="default-jre-headless"  # Dependencies for Debian-based systems
RHELDEPS="java-latest-openjdk-headless"  # Dependencies for RHEL-based systems

# System configuration
FILE_MAX_VALUE=1048576  # Maximum number of open files
MAX_MAP_COUNT_VALUE=1048576  # Maximum number of memory map areas

# Sysctl.d configuration
SYSCTL_CONF="/etc/sysctl.d/10-questdb.conf"  # Path to the sysctl configuration file

# Quest DB configuration
DATA_DIR="/var/lib/questdb"  # Directory for data
INSTALL_PREFIX="/opt/questdb"  # Installation directory

# Add shell options for output directory, help, and version
OUTPUT_DIR="."  # Default output directory

while getopts "o:hv" opt; do
  case $opt in
    o)
      OUTPUT_DIR="$OPTARG"
      ;;
    h)
      echo "Usage: $0 [-o output_directory] [-h] [-v]"
      echo "  -o output_directory  Specify the output directory for built packages (default: current directory)"
      echo "  -h                   Show this help message"
      echo "  -v                   Show script version"
      exit 0
      ;;
    v)
      echo "qdb-pkg.sh version 1.0.0-alpha"
      exit 0
      ;;
    *)
      echo "Invalid option. Use -h for help."
      exit 1
      ;;
  esac
done

# Ensure necessary tools are installed
# Check for curl (required for downloading files)
command -v curl >/dev/null 2>&1 || {
  echo "curl is required but not installed."
  exit 1
}

# Check for jq (required for parsing JSON)
command -v jq >/dev/null 2>&1 || {
  echo "jq is required but not installed."
  exit 1
}

# Check for ar (required for creating Debian packages)
command -v ar >/dev/null 2>&1 || {
  echo "ar is required but not installed."
  exit 1
}

# Check for rpmbuild (required for creating RPM packages)
command -v rpmbuild >/dev/null 2>&1 || {
  echo "rpmbuild is required but not installed."
  exit 1
}

# Check for fpm (required for creating packages)
command -v fpm >/dev/null 2>&1 || {
  echo "fpm is required but not installed."
  exit 1
}

# Fetch the latest release information
# Use GitHub API to get the latest release details
RELEASE_INFO=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")
VERSION=$(echo "$RELEASE_INFO" | jq -r .tag_name)  # Extract the version tag
ASSET_URL=$(echo "$RELEASE_INFO" | jq -r '.assets[] | select(.name | contains("no-jre") and endswith("bin.tar.gz")).browser_download_url')  # Extract the download URL for the binary

# Validate release information
if [[ -z "$VERSION" || -z "$ASSET_URL" ]]; then
  echo "Failed to fetch the latest release information."
  exit 1
fi

# Prepare directories
# Clean up and recreate necessary directories
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
#!/bin/bash
if [ ! -f $SYSCTL_CONF ]; then
  echo "Creating sysctl.d configuration file..."
  echo "fs.file-max = $FILE_MAX_VALUE" > $SYSCTL_CONF
  echo "vm.max_map_count = $MAX_MAP_COUNT_VALUE" >> $SYSCTL_CONF
fi

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

if [ ! -f $SYSCTL_CONF ]; then
  echo "Removing sysctl.d configuration file..."
  rm -f $SYSCTL_CONF
fi
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
  -p "$OUTPUT_DIR" \
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
  -p "$OUTPUT_DIR" \
  -C "$BUILD_DIR" .

echo "Packages created successfully."
