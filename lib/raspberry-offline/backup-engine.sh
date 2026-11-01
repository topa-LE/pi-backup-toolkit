#!/bin/sh
#
# Workstation Toolkit
# Offline Raspberry/Linux Backup Engine
#

set -eu
set -o pipefail

PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

CONF="/etc/workstation-backup/host.conf"

MOUNTED=0
BACKUP_DIR=""
FINAL_DIR=""
LOGFILE=""

# WORKSTATION_EARLY_DIAGNOSTICS_V1
DIAG_BUFFER="/run/workstation-backup-early.log"

# WORKSTATION_REMOTE_DIAGNOSTICS_V1
DIAG_SERVER=""
DIAG_PORT="5514"
DIAG_NETWORK_READY=0

remote_diag()
{
    [ "$DIAG_NETWORK_READY" -eq 1 ] || return 0
    [ -n "$DIAG_SERVER" ] || return 0

    printf "%s\n" "$*" |
        /bin/busybox nc -w 2 "$DIAG_SERVER" "$DIAG_PORT" \
        >/dev/null 2>&1 || true
}

log()
{
    LINE="[workstation-backup] $*"

    echo "$LINE"

    if [ "$DIAG_NETWORK_READY" -eq 0 ] && [ -d /run ]; then
        printf "%s\n" "$LINE" >> "$DIAG_BUFFER" 2>/dev/null || true
    fi

    remote_diag "$LINE"

    # WORKSTATION_KMSG_LOGGING
    if [ -w /dev/kmsg ]; then
        printf '<6>%s\n' "$LINE" > /dev/kmsg
    fi

    if [ -n "${LOGFILE:-}" ]; then
        printf '%s\n' "$LINE" >> "$LOGFILE" 2>/dev/null || true
    fi
}

die()
{
    log "ERROR: $*"
    exit 1
}

cleanup()
{
    RC=$?

    if [ "$MOUNTED" -eq 1 ]; then
        log "Unmounting NFS share ..."

        /bin/busybox sync || true

        /bin/busybox timeout 20 \
            /bin/busybox umount "$BACKUP_MOUNT" \
            >/dev/null 2>&1 || \
        /bin/busybox umount -l "$BACKUP_MOUNT" \
            >/dev/null 2>&1 || true

        MOUNTED=0
    fi

    exit "$RC"
}

trap cleanup EXIT HUP INT TERM

require_file()
{
    [ -r "$1" ] || die "File missing: $1"
}

require_exec()
{
    [ -x "$1" ] || die "Executable missing: $1"
}

require_block()
{
    [ -b "$1" ] || die "Block device missing: $1"
}

device_is_mounted()
{
    DEVICE="$1"

    /bin/busybox grep -q \
        "^${DEVICE} " \
        /proc/mounts 2>/dev/null
}

load_config()
{
    require_file "$CONF"

    . "$CONF"

    : "${HOSTNAME:?HOSTNAME missing}"
    : "${IP_ADDRESS:?IP_ADDRESS missing}"

    : "${ROOT_DEVICE:?ROOT_DEVICE missing}"
    : "${BOOT_PARTITION:?BOOT_PARTITION missing}"
    : "${ROOT_PARTITION:?ROOT_PARTITION missing}"

    : "${NETWORK_INTERFACE:?NETWORK_INTERFACE missing}"
    : "${NETWORK_MODE:?NETWORK_MODE missing}"

    : "${BACKUP_MOUNT:?BACKUP_MOUNT missing}"
    : "${BACKUP_TARGET:?BACKUP_TARGET missing}"
    : "${NFS_VERSION:?NFS_VERSION missing}"

    : "${RETENTION:?RETENTION missing}"
}

# WORKSTATION_WAIT_FOR_BLOCK_DEVICES
wait_for_block_devices()
{
    log "Waiting for system disk ..."

    WAIT=0

    while [ "$WAIT" -lt 60 ]; do
        if [ -b "$ROOT_DEVICE" ] && \
           [ -b "$BOOT_PARTITION" ] && \
           [ -b "$ROOT_PARTITION" ]
        then
            log "System disk fully available."
            return 0
        fi

        WAIT=$((WAIT + 1))
        /bin/busybox sleep 1
    done

    die "Block devices not fully available after 60 seconds: ${ROOT_DEVICE} ${BOOT_PARTITION} ${ROOT_PARTITION}"
}

validate_environment()
{
    # WORKSTATION_PARTCLONE_LOGDIR
    # Partclone expects /var/log/partclone.log.
    /bin/busybox mkdir -p /var/log

    log "Checking offline backup environment ..."

    require_block "$ROOT_DEVICE"
    require_block "$BOOT_PARTITION"
    require_block "$ROOT_PARTITION"

    require_exec /usr/sbin/partclone.ext4
    require_exec /usr/sbin/partclone.vfat
    require_exec /usr/bin/zstd
    require_exec /usr/sbin/sfdisk
    require_exec /usr/sbin/blkid
    require_exec /usr/bin/sha256sum
    require_exec /usr/bin/ipconfig
    require_exec /usr/sbin/mount.nfs
    require_exec /bin/busybox

    if device_is_mounted "$BOOT_PARTITION"; then
        die "$BOOT_PARTITION is mounted"
    fi

    if device_is_mounted "$ROOT_PARTITION"; then
        die "$ROOT_PARTITION is mounted"
    fi

    log "OK: Boot and root partitions are offline."
}

configure_network()
{
    WAIT=0

    while [ ! -e "/sys/class/net/${NETWORK_INTERFACE}" ]; do
        WAIT=$((WAIT + 1))

        if [ "$WAIT" -ge 15 ]; then
            die "Network interface ${NETWORK_INTERFACE} not found after 15 seconds"
        fi

        /bin/busybox sleep 1
    done

    log "Configuring ${NETWORK_INTERFACE} ..."

    case "$NETWORK_MODE" in
        dhcp)
            /bin/busybox timeout 45 \
                /usr/bin/ipconfig \
                    -t 30 \
                    -c dhcp \
                    "$NETWORK_INTERFACE" \
                || die "DHCP on ${NETWORK_INTERFACE} failed"
            ;;

        *)
            die "NETWORK_MODE not supported: ${NETWORK_MODE}"
            ;;
    esac

    DIAG_NETWORK_READY=1

    if [ -s "$DIAG_BUFFER" ]; then
        while IFS= read -r DIAG_LINE; do
            remote_diag "$DIAG_LINE"
        done < "$DIAG_BUFFER"
        rm -f "$DIAG_BUFFER"
    fi
    log "Network available."
}

mount_backup_target()
{
    log "Mounte ${BACKUP_TARGET} ..."

    /bin/busybox mkdir -p "$BACKUP_MOUNT"

    /bin/busybox timeout 30 \
        /usr/sbin/mount.nfs \
            -n \
            -o "rw,hard,vers=${NFS_VERSION},proto=tcp,timeo=600,retrans=2" \
            "$BACKUP_TARGET" \
            "$BACKUP_MOUNT" \
        || die "NFS-Mount failed"

    if ! /bin/busybox grep -q \
        " ${BACKUP_MOUNT} " \
        /proc/mounts
    then
        die "NFS mount missing in /proc/mounts"
    fi

    MOUNTED=1

    log "NFS mounted successfully."
}

get_backup_id()
{
    BACKUP_ID=""

    for ARG in $(cat /proc/cmdline); do
        case "$ARG" in
            workstation_backup_id=*)
                BACKUP_ID="${ARG#workstation_backup_id=}"
                ;;
        esac
    done

    if [ -z "$BACKUP_ID" ]; then
        BACKUP_ID="$(date +%Y%m%d-%H%M%S)"
    fi

    case "$BACKUP_ID" in
        *[!0-9A-Za-z._-]*)
            die "Invalid BACKUP_ID: ${BACKUP_ID}"
            ;;
    esac
}

create_backup_directory()
{
    get_backup_id

    FINAL_DIR="${BACKUP_MOUNT}/backup-${BACKUP_ID}"
    BACKUP_DIR="${FINAL_DIR}.incomplete"

    if [ -e "$FINAL_DIR" ] || [ -e "$BACKUP_DIR" ]; then
        die "Backup destination already exists: backup-${BACKUP_ID}"
    fi

    /bin/busybox mkdir -p "$BACKUP_DIR"

    LOGFILE="${BACKUP_DIR}/backup.log"

    {
        echo "STATUS=INCOMPLETE"
        echo "BACKUP_ID=${BACKUP_ID}"
        echo "HOSTNAME=${HOSTNAME}"
    } > "${BACKUP_DIR}/INCOMPLETE"

    log "Working directory: ${BACKUP_DIR}"
}

save_metadata()
{
    log "Saving disk metadata ..."

    /usr/sbin/sfdisk --dump "$ROOT_DEVICE" \
        > "${BACKUP_DIR}/disk.sfdisk"

    /usr/sbin/sfdisk --json "$ROOT_DEVICE" \
        > "${BACKUP_DIR}/disk.json"

    /usr/sbin/blkid \
        > "${BACKUP_DIR}/blkid.txt"

    # WORKSTATION_DISK_HEADER_V1
    #
    # Backs up the complete raw data region from the beginning of the
    # system disk up to the start of partition 1.
    # This includes the MBR, disk signature, and the
    # pre-partition region not captured by Partclone.
    #
    FIRST_PARTITION_START_SECTOR="$(
        /bin/busybox awk -F'[=,]' '
            /start=/ {
                value=$2
                gsub(/[[:space:]]/, "", value)
                print value
                exit
            }
        ' "${BACKUP_DIR}/disk.sfdisk"
    )"

    DISK_SECTOR_SIZE="$(
        /bin/busybox awk -F':' '
            /^sector-size:/ {
                value=$2
                gsub(/[[:space:]]/, "", value)
                print value
                exit
            }
        ' "${BACKUP_DIR}/disk.sfdisk"
    )"

    case "$FIRST_PARTITION_START_SECTOR" in
        ""|*[!0-9]*)
            die "Could not determine the first partition start sector"
            ;;
    esac

    case "$DISK_SECTOR_SIZE" in
        ""|*[!0-9]*)
            die "Could not determine sector size"
            ;;
    esac

    if [ "$FIRST_PARTITION_START_SECTOR" -le 0 ]; then
        die "Invalid start sector: ${FIRST_PARTITION_START_SECTOR}"
    fi

    if [ "$DISK_SECTOR_SIZE" -le 0 ]; then
        die "Invalid sector size: ${DISK_SECTOR_SIZE}"
    fi

    DISK_HEADER_BYTES=$(( FIRST_PARTITION_START_SECTOR * DISK_SECTOR_SIZE ))

    log "Sichere Disk-Vorspann: ${FIRST_PARTITION_START_SECTOR} Sektoren / ${DISK_HEADER_BYTES} Bytes ..."

    /bin/busybox dd \
        if="$ROOT_DEVICE" \
        of="${BACKUP_DIR}/disk-header.bin" \
        bs="$DISK_SECTOR_SIZE" \
        count="$FIRST_PARTITION_START_SECTOR" \
        || die "Could not back up disk header"

    ACTUAL_DISK_HEADER_BYTES="$(
        /bin/busybox wc -c "${BACKUP_DIR}/disk-header.bin" |
        /bin/busybox awk '{print $1}'
    )"

    if [ "$ACTUAL_DISK_HEADER_BYTES" -ne "$DISK_HEADER_BYTES" ]; then
        die "disk-header.bin has an unexpected size: ${ACTUAL_DISK_HEADER_BYTES} statt ${DISK_HEADER_BYTES} Bytes"
    fi

    log "Disk header backed up successfully."

    /bin/busybox cp \
        "$CONF" \
        "${BACKUP_DIR}/host.conf"

    {
        echo "FORMAT_VERSION=1"
        echo "HOSTNAME=${HOSTNAME}"
        echo "IP_ADDRESS=${IP_ADDRESS}"
        echo "ROOT_DEVICE=${ROOT_DEVICE}"
        echo "BOOT_PARTITION=${BOOT_PARTITION}"
        echo "ROOT_PARTITION=${ROOT_PARTITION}"
        echo "BACKUP_ID=${BACKUP_ID}"
        echo "NFS_VERSION=${NFS_VERSION}"
        echo "RETENTION=${RETENTION}"
    } > "${BACKUP_DIR}/manifest.txt"

    log "Disk metadata saved."
}

backup_boot_partition()
{
    log "Backing up boot partition ${BOOT_PARTITION} ..."

    /usr/sbin/partclone.vfat \
        -c \
        -s "$BOOT_PARTITION" \
        -o - \
        2>"${BACKUP_DIR}/partclone-boot.log" \
    | /usr/bin/zstd \
        -3 \
        -o "${BACKUP_DIR}/boot.partclone.zst" \
        2>"${BACKUP_DIR}/zstd-boot.log"

    log "Boot partition backed up."
}

backup_root_partition()
{
    log "Backing up root partition ${ROOT_PARTITION} ..."

    /usr/sbin/partclone.ext4 \
        -c \
        -s "$ROOT_PARTITION" \
        -o - \
        2>"${BACKUP_DIR}/partclone-root.log" \
    | /usr/bin/zstd \
        -3 \
        -o "${BACKUP_DIR}/root.partclone.zst" \
        2>"${BACKUP_DIR}/zstd-root.log"

    log "Root partition backed up."
}

test_compressed_images()
{
    log "Verifying zstd images ..."

    /usr/bin/zstd \
        -t \
        "${BACKUP_DIR}/boot.partclone.zst" \
        "${BACKUP_DIR}/root.partclone.zst" \
        > "${BACKUP_DIR}/zstd-test.log" 2>&1

    log "zstd verification successful."
}

create_and_verify_checksums()
{
    log "Generating SHA-256 checksums ..."

    (
        cd "$BACKUP_DIR"

        /usr/bin/sha256sum \
            disk.sfdisk \
            disk.json \
            disk-header.bin \
            blkid.txt \
            host.conf \
            manifest.txt \
            boot.partclone.zst \
            root.partclone.zst \
            > SHA256SUMS

        /usr/bin/sha256sum \
            -c SHA256SUMS \
            > checksum-verify.log 2>&1
    )

    log "SHA-256 verification successful."
}

finalize_backup()
{
    log "Finalisiere Backup ..."

    /bin/busybox sync

    /bin/busybox rm -f \
        "${BACKUP_DIR}/INCOMPLETE"

    {
        echo "STATUS=COMPLETE"
        echo "BACKUP_ID=${BACKUP_ID}"
        echo "HOSTNAME=${HOSTNAME}"
    } > "${BACKUP_DIR}/BACKUP_COMPLETE"

    /bin/busybox sync

    LOGFILE=""

    /bin/busybox mv \
        "$BACKUP_DIR" \
        "$FINAL_DIR"

    BACKUP_DIR="$FINAL_DIR"

    /bin/busybox sync

    log "BACKUP SUCCESSFUL: ${FINAL_DIR}"
}

backup_engine()
{
    load_config
    configure_network
    wait_for_block_devices
    validate_environment
    mount_backup_target
    create_backup_directory
    save_metadata
    backup_boot_partition
    backup_root_partition
    test_compressed_images
    create_and_verify_checksums
    finalize_backup

    #
    # RETENTION is intentionally not executed here.
    #
    log "Retention=${RETENTION} configured but not yet enabled."
}

#
# IMPORTANT:
# Still disabled.
#
# The initramfs runner calls backup_engine only when an
# explicit backup mode has been selected.
#
# backup_engine


#
# WORKSTATION_EXPLICIT_RUN_GATE
#
# The engine may only be invoked using an explicit "run" command
# for execution.
#
case "${1:-}" in
    run)
        backup_engine
        ;;

    "")
        # Direct invocation without parameters intentionally does nothing.
        ;;

    *)
        echo "[workstation-backup] ERROR: Unknown invocation mode: $1" >&2
        exit 64
        ;;
esac

exit 0
