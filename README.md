<div align="center">

# 🥧 Pi Backup Toolkit

### Reliable Offline System Backups for Raspberry Pi

A portable, repository-based backup toolkit for Raspberry Pi and ARM Linux systems.
Designed for offline partition imaging, verified backups and controlled restoration.

<p>
  <img src="https://img.shields.io/badge/Platform-Raspberry%20Pi-C51A4A?logo=raspberrypi&logoColor=white" alt="Raspberry Pi">
  <img src="https://img.shields.io/badge/Architecture-ARM64-blue" alt="ARM64">
  <img src="https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white" alt="Bash">
  <img src="https://img.shields.io/badge/Imaging-Partclone-orange" alt="Partclone">
  <img src="https://img.shields.io/badge/Compression-Zstandard-7765E3" alt="Zstandard">
  <img src="https://img.shields.io/badge/Integrity-SHA--256-success" alt="SHA-256">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="MIT License"></a>
</p>

[Features](#-features) ·
[Architecture](#-architecture) ·
[Installation](#-installation) ·
[Configuration](#-configuration) ·
[Usage](#-usage) ·
[Restore](#-restoration) ·
[Safety](#-backup-safety)

</div>

---

## 📖 Overview

Pi Backup Toolkit provides a centralized solution for creating and managing offline system backups of Raspberry Pi devices.

Unlike conventional file-based backups, the toolkit operates outside the running operating system.

The Raspberry Pi boots into a dedicated initramfs environment, allowing its boot and root partitions to be backed up without actively mounted filesystems.

Backup images are compressed, checksummed and stored on a network backup destination.

The project is developed as a portable Git repository. Each installation maintains its own host configurations and SSH credentials outside the shared project code.

## ✨ Features

<table width="837">
<tr>
<td width="261" valign="top">

**🛡️ Offline Backup**

- Dedicated initramfs environment
- Offline boot partition
- Offline root partition
- Partclone imaging

</td>
<td width="576" valign="top">

**🔐 Backup Integrity**

- Zstandard compression
- SHA-256 checksums
- Image verification
- Backup completion markers
- Incomplete backup protection

</td>
</tr>
<tr>
<td width="261" valign="top">

**🌐 Network Storage**

- NFS backup destination
- Network configuration
- Centralized backup storage

</td>
<td width="576" valign="top">

**⚙️ Backup Management**

- Multiple host configurations
- SSH-based remote management
- Backup status inspection
- Retention management
- Controlled restore operations

</td>
</tr>
</table>

## 🏗️ Architecture

The toolkit consists of three main components:

| Component | Responsibility |
|:--|:--|
| `bin/` | Backup launcher, core management, retention and restoration |
| `lib/raspberry-offline/` | Central backup engine and initramfs integration |
| `config/` | Public examples and local host configurations |

### Backup workflow

```text
        Raspberry Pi
             │
             ▼
      Tryboot / Initramfs
             │
             ▼
     Offline Backup Engine
             │
       ┌─────┴─────┐
       ▼           ▼
  Boot Partition  Root Partition
       │           │
       ▼           ▼
    Partclone    Partclone
       │           │
       └─────┬─────┘
             ▼
       Zstandard
       Compression
             │
             ▼
       SHA-256 Checks
             │
             ▼
       NFS Backup Storage
             │
             ▼
      BACKUP_COMPLETE
```

## 📋 Requirements

### Workstation

- Linux workstation
- Bash
- SSH and SCP
- SHA-256 utilities
- Standard GNU/Linux command-line tools

### Raspberry Pi

- Supported ARM64 Linux installation
- SSH access
- Boot configuration supporting the toolkit's tryboot workflow
- Partclone and Zstandard support in the backup environment
- Network access to an NFS backup destination

## 🚀 Installation

Clone the repository:

```bash
git clone git@github.com:topa-LE/pi-backup-toolkit.git
cd pi-backup-toolkit
```

Run the installer:

```bash
./scripts/install.sh
```

The installer checks the required commands and project structure, creates the local workstation configuration and verifies executable permissions.

No personal SSH credentials or host configurations are included in the repository.

## ⚙️ Configuration

### 1. Workstation configuration

The installer creates:

```text
config/local/toolkit.conf
```

Configure your own SSH private key:

```bash
WORKSTATION_SSH_KEY=/path/to/your/ssh/private/key
```

This file is local and excluded from Git.

### 2. Backup host configuration

Create a host configuration based on:

```text
config/hosts/example.conf
```

Each host has its own configuration containing:

- Hostname and IP address
- SSH user
- System disk and partition devices
- NAS server and backup destination
- Remote backup engine location
- Retention settings

Real host configurations are excluded from Git.

### 3. Raspberry Pi backup configuration

The Raspberry Pi uses a separate configuration:

```text
/etc/workstation-backup/host.conf
```

The public template is located at:

```text
lib/raspberry-offline/templates/host.conf.example
```

It defines the storage devices, network interface, backup mount, NFS destination and backup parameters.

## 💻 Usage

The main entry point is `backup-host`.

### List configured hosts

```bash
./bin/backup-host --list
```

### Inspect backup status

```bash
./bin/backup-host --status example-linux-host
```

### Preview a live backup

```bash
./bin/backup-host --preview-live example-linux-host
```

### Start a backup

```bash
./bin/backup-host example-linux-host
```

### Retention dry-run

```bash
./bin/backup-retention --dry-run example-linux-host
```

### Apply retention

```bash
./bin/backup-retention example-linux-host
```

## ♻️ Restoration

The toolkit includes a dedicated restore utility:

```bash
./bin/restore-host example-linux-host
```

The restoration process includes:

- Backup completion verification
- SHA-256 checksum verification
- Target block-device validation
- Mounted-device protection
- Disk capacity validation
- Explicit destructive-operation confirmation
- Partition restoration using Partclone
- Filesystem checks
- UUID and PARTUUID verification

**WARNING:** Restoration overwrites the selected target disk. Always verify the target device and backup before confirming a restore operation.

A successful backup does not automatically prove successful restoration. Full restore validation requires an actual restore and subsequent boot test.

## 🔒 Backup Safety

The toolkit uses several mechanisms to protect backup integrity:

| Protection | Purpose |
|:--|:--|
| `BACKUP_COMPLETE` | Marks a successfully completed backup |
| `SHA256SUMS` | Stores image checksums |
| `.incomplete` | Identifies unfinished backup operations |
| Zstandard verification | Checks compressed backup images |
| UUID / PARTUUID | Validates restored partition identity |
| Confirmation token | Protects destructive restore operations |

Incomplete backups are not treated as valid completed backups.

## 📁 Repository Structure

```text
pi-backup-toolkit/
├── bin/
│   ├── backup-host
│   ├── backup-host-core
│   ├── backup-retention
│   └── restore-host
│
├── config/
│   ├── hosts/
│   │   ├── example.conf
│   │   └── README.md
│   └── local/
│       └── toolkit.conf.example
│
├── lib/
│   └── raspberry-offline/
│       ├── backup-engine.sh
│       ├── METHOD.conf
│       ├── PROVEN.md
│       ├── initramfs-tools/
│       ├── reference/
│       └── templates/
│
├── scripts/
│   └── install.sh
│
├── systemd/
│   └── workstation-backup-diagnostics.service.example
│
├── .gitignore
└── README.md
```

## 🧪 Validation Status

| Component | Status |
|:--|:--|
| Offline backup implementation | Verified on laboratory ARM64 system |
| Partclone imaging | Verified |
| Zstandard compression | Verified |
| SHA-256 verification | Verified |
| NFS backup storage | Verified |
| Completion handling | Verified |
| Restoration implementation | Not yet fully verified |
| Full restore and boot test | Pending |

Validation status is documented in `lib/raspberry-offline/PROVEN.md`.

## 🛠️ Development

The project is maintained as a portable Git repository.

Development, testing and improvements are performed against the repository version.

Machine-specific settings, credentials and validation evidence remain outside the shared source code.

Contributions and improvements should preserve the backup integrity and restoration safety mechanisms.

## 📜 License

This project is licensed under the **MIT License**.

See the complete [MIT License](LICENSE) for details.
---


Made with ❤️ by [topa-LE](https://github.com/topa-LE)
