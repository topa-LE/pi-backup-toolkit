# Raspberry Offline Backup – Proven Method

## Method

    raspberry-offline-partclone

## Validation status

The backup implementation has been successfully validated on a physical
ARM64 Raspberry Pi laboratory system.

Verified functionality:

- dedicated early-boot/initramfs backup environment
- boot filesystem offline during imaging
- root filesystem offline during imaging
- Partclone filesystem imaging
- zstd compression
- NFS backup destination
- filesystem and partition metadata capture
- SHA-256 validation
- incomplete-to-complete transaction model
- automatic return to the normal operating system

## Current validation level

    BACKUP_STATUS=VERIFIED
    RESTORE_STATUS=NOT_YET_VERIFIED

A successful backup alone does not prove restore capability.
The method remains RESTORE_STATUS=NOT_YET_VERIFIED until an actual
restore onto another storage device has been completed and boot-tested.

## Local validation evidence

Machine-specific validation evidence is intentionally NOT repository
content.

This includes:

- real IP addresses
- real hostnames
- NAS addresses and paths
- filesystem UUIDs and PARTUUIDs
- boot configuration
- image checksums
- generated initramfs images
- real host configurations

Local validation snapshots are stored outside repository scope below:

    a local reference directory outside the repository

## Repository rule

The reusable implementation must never depend on the laboratory
reference host.

Host-specific values are supplied through local configuration.
