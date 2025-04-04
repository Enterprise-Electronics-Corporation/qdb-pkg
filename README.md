# QuestDB Package Builder

This project provides a script to build Debian and RPM packages for [QuestDB](https://questdb.io/), a high-performance time-series database.

## Features
- Automatically fetches the latest QuestDB release.
- Creates systemd service files for easy management.
- Configures system parameters for optimal performance.
- Builds `.deb` and `.rpm` packages using `fpm`.

## Prerequisites
Ensure the following tools are installed on your system:
- `curl`
- `jq`
- `ar` (from `binutils`)
- `rpmbuild` (from `rpm`)
- `ruby`
- `fpm` (Ruby gem)

## Installation
1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd qdb-pkg
   ```
2. Make the script executable:
   ```bash
   chmod +x qdb-pkg.sh
   ```

## Usage
Run the script to build the packages:
```bash
./qdb-pkg.sh
```
The generated `.deb` and `.rpm` packages will be created in the current directory.

## System Configuration
The following parameters are set via sysctl.d configuration to recommended values:
- `fs.file-max`
- `vm.max_map_count`

These changes are applied automatically during installation.

## License
This project is licensed under the Apache-2.0 License.