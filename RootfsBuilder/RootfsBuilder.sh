#!/bin/bash

# Base Vars
WorkDir=$(realpath $(pwd))
ConfigFile=${WorkDir}/settings.conf
[ -f ${ConfigFile} ] || (echo "Error: Cannot find 'settings.conf' in the current folder." && return 1)

SquashfsFile=
VDisk=
RootDir=
CacheDir=
ProfilesDir=
ExtPackageDir=
RootfsBasePackage=

PreReplaceFiles=
PostReplaceFiles=

Packages=
PackagesExtra=
PackagesUnInstall=

TimeZone=
AptUrl=
Encoding=
Language=
Locales=
BootloaderID=
AccountUsername=
AccountPassword=

# Echo Color Settings
C_CLR="\\e[0m"
C_HL="\\e[1m"
C_RED="${C_HL}\\e[31m"
C_GEN="${C_HL}\\e[32m"
C_YEL="${C_HL}\\e[33m"
C_BLU="${C_HL}\\e[36m"
C_OK="${C_GEN}OK${C_CLR}"
C_FL="${C_RED}FAILED${C_CLR}"
C_WARN="${C_YEL}WARNNING${C_CLR}"
C_ERROR="${C_RED}ERROR${C_CLR}"

Script=$0
ScriptDir="$(cd "$(dirname "$0")" && pwd)"

CheckPrivilege() {
    if [ $UID -ne 0 ]; then
        echo -e  "Please run this script with \033[1m\033[31mroot\033[0m privileges."
        return 1
    else
        return 0
    fi
}

CheckBuildEnvironment() {
    Utils="blkid lsblk losetup parted mkfs.ext4 mkfs.fat mksquashfs"

    for Util in ${Utils}; do
        if ! which ${Util} >/dev/null 2>&1; then
            echo -e "Please install [${C_RED}${Util}${C_CLR}] first"
            return 1
        fi
    done

    return 0
}

# USAGE: ConfGetSections <ConfFile>
ConfGetSections() {
    [ $# -eq 1 ] || (echo -e "Usage: ConfGetSections <ConfFile>" && return 1)

    local ConfFile=$1
    sed -n "/\[*\]/{s/\[//;s/\]///^;.*$/d;/^#.*$/d;p}" ${ConfFile}
}

# USAGE: ConfGetKeys <ConfFile> <Section>
ConfGetKeys() {
    [ $# -eq 2 ] || (echo -e "Usage: ConfGetKeys <ConfFile> <Section>" && return 1)

    local ConfFile=$1
    local Section=$2

    sed -n "/\[${Section}\]/,/\[.*\]/{/^\[.*\]/d;/^[ ]*$/d;/^;.*$/d;/^#.*$/d;p}" ${ConfFile} | awk -F '=' '{print $1}'
}

# USAGE: ConfGetValues <ConfFile> <Section>
ConfGetValues() {
    [ $# -eq 2 ] || (echo -e "Usage: ConfGetValues <ConfFile> <Section>" && return 1)

    local ConfFile=$1
    local Section=$2

    sed -n "/\[${Section}\]/,/\[.*\]/{/^\[.*\]/d;/^[ ]*$/d;/^;.*$/d;/^#.*$/d;p}" ${ConfFile} | awk -F '=' '{print $2}'
}

# USAGE: ConfGetValue <ConfFile> <Section> <Key>
ConfGetValue() {
    [ $# -eq 3 ] || (echo -e "Usage: ConfGetValue <ConfFile> <Section> <Key>" && return 1)

    local ConfFile=$1
    local Section=$2
    local Key=$3

    sed -n "/\[${Section}\]/,/\[.*\]/{/^\[.*\]/d;/^[ ]*$/d;s/;.*$//;s/^[| ]*${Key}[| ]*=[| ]*\(.*\)[| ]*/\1/p}" ${ConfFile}
}

# USAGE: ConfSetValue <ConfFile> <Section> <Key> <Value>
ConfSetValue() {
    [ $# -eq 4 ] || (echo -e "Usage: ConfGetValue <ConfFile> <Section> <Key>" && return 1)

    local ConfFile=$1
    local Section=$2
    local Key=$3
    local Value=$4

    sed -i "/^\[${Section}\]/,/^\[/ {/^\[${Section}\]/b;/^\[/b;s/^${Key}*=.*/${Key}=${Value}/g;}" ${ConfFile}
}

# Usage: IsVirtualDiskLoaded <VirtualDisk>
IsVirtualDiskLoaded() {
    [ $# -eq 1 ] || (echo -e "Usage: IsVirtualDiskLoaded <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -e ${VirtualDisk} ] || return 1

    if [ -n "$(losetup --associated ${VirtualDisk})" ]; then
        return 0
    else
        return 1
    fi
}

# Usage: GetVirtualDiskLoadedDevice <VirtualDisk>
GetVirtualDiskLoadedDevice() {
    [ $# -eq 1 ] || (echo -e "Usage: GetVirtualDiskLoadedDevice <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -e ${VirtualDisk} ] || return 1

    if IsVirtualDiskLoaded ${VirtualDisk}; then
        losetup --associated ${VirtualDisk} | awk -F: '{print $1}'
    else
        return 1
    fi
}

# Usage: LoadVirtualDisk <VirtualDisk>
LoadVirtualDisk() {
    [ $# -eq 1 ] || (echo -e "Usage: LoadVirtualDisk <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -e ${VirtualDisk} ] || return 1

    local Device=$(GetVirtualDiskLoadedDevice ${VirtualDisk})
    if [ $? -eq 0 ] && [ -z "${Device}" ]; then
        printf "LOADING: ${C_HL}$(basename ${VirtualDisk})${C_CLR}"
        Device=$(losetup --partscan --find --show ${VirtualDisk})
        if [ $? -eq 0 ] && [ -n "${Device}" ] && [ -e "${Device}" ]; then
            printf " [${C_OK}]\n"
            echo -e " ${C_HL}$(basename ${VirtualDisk})${C_CLR} --> ${C_YEL}${Device}${C_CLR}"
        else
            printf " [${C_FL}]\n" && return 1
        fi
    fi
}

# Usage: CreateVirtualDisk <VirtualDisk>
CreateVirtualDisk() {
    [ $# -eq 1 ] || (echo -e "Usage: CreateVirtualDisk <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -e ${VirtualDisk} ] && (echo -e "VirtualDisk file ${VirtualDisk} exists!" && return 1)

    dd if=/dev/zero of=${VirtualDisk} bs=4M count=0 seek=1024 status=none || return 1

    return 0
}

# Usage: CreatePartitions <Disk>
CreatePartitions() {
    [ $# -eq 1 ] || (echo -e "Usage: CreatePartitions <Disk>" && return 1)

    local Disk=$1
    [ -e ${Disk} ] || (echo -e "Disk file ${Disk} not exists!" && return 1)

    parted -s ${Disk} mklabel gpt                     || return 1
    # parted -s ${Disk} mkpart ESP fat32 1M 100M        || return 1
    # parted -s ${Disk} mkpart STBINFO ext4 100M 200M   || return 1
    # parted -s ${Disk} mkpart RECOVERY ext4 200M 800M  || return 1
    # parted -s ${Disk} mkpart ROOT ext4 800M 3000M     || return 1
    # parted -s ${Disk} mkpart SYSCONF ext4 3000M 3100M || return 1
    # parted -s ${Disk} mkpart USERDATA ext4 3100M 100% || return 1
    parted -s ${Disk} mkpart ESP fat32 1M 500M        || return 1
    parted -s ${Disk} mkpart ROOT ext4 500M 3000M     || return 1
    parted -s ${Disk} mkpart USERDATA ext4 3000M 100% || return 1
    parted -s ${Disk} set 1 boot on                   || return 1
    parted -s ${Disk} set 1 esp on                    || return 1

    return 0
}

# Usage: GetDiskType <Disk>
GetDiskType() {
    [ $# -eq 1 ] || (echo -e "Usage: GetDiskType <Disk>" && return 1)

    local Disk=$1
    [ -e ${Disk} ] || return 1

    if lsblk ${Disk} >/dev/null 2>&1; then
        local DiskType=$(lsblk -n -o TYPE -d ${Disk})
        [ $? -eq 0 ] || return 1
    else
        return 1
    fi

    echo ${DiskType}

    return 0
}

# Usage: IsVirtualDisk <Disk>
IsVirtualDisk() {
    [ $# -eq 1 ] || (echo -e "Usage: IsVirtualDisk <Disk>" && return 1)

    local Disk=$1
    [ -e ${Disk} ] || return 1

    local folder=$(echo ${Disk} | cut -d '/' -f 2)
    if [ $? -eq 0 ] && [ x"${folder}" = x"dev" ]; then
        local DiskType=$(GetDiskType ${Disk})
        if [ $? -eq 0 ] && [ x"${DiskType}" = x"disk" ]; then
            return 1
        else
            return 0
        fi
    else
        if blkid ${Disk} >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    fi
}

# Usage: GetDiskPartitions <Disk>
GetDiskPartitions() {
    [ $# -eq 1 ] || (echo -e "Usage: GetDiskPartitions <Disk>" && return 1)

    local Disk=$1
    [ -e ${Disk} ] || return 1

    local Devices=""
    local Partitions=""

    if lsblk ${Disk} >/dev/null 2>&1; then
        Device=${Disk}
    else
        Device=$(GetVirtualDiskLoadedDevice ${Disk})
    fi

    Partitions=$(lsblk ${Device} -p -r -n | awk '/part/{print $1}')
    [ $? -eq 0 ] && [ -n "${Partitions}" ] || return 1

    echo -e ${Partitions}
}

# Usage: GetDiskPartInfo <Info> <Device>
GetDiskPartInfo() {
    [ $# -eq 2 ] || (echo -e "Usage: GetPartitionType <Info> <Device>" && return 1)

    local Info=$1
    local Device=$2
    local expr=""
    [ -e ${Device} ] || return 1

    case ${Info} in
        Type|TYPE|T)
            expr="TYPE"
            ;;
        Label|LABEL|L)
            expr="PARTLABEL"
            ;;
        Uuid|UUID|U)
            expr="UUID"
            ;;
        PartUUID|PARTUUID|PU)
            expr="PARTUUID"
            ;;
        *)
            return 1
            ;;
    esac

    local PartInfo=$(blkid -s ${expr} -o value  ${Device})
    [ $? -eq 0 ] && [ -n "${PartInfo}" ] || return 1

    echo ${PartInfo}
}

# Usage: GetDiskPartDevice <Disk> <Info> <String>
GetDiskPartDevice() {
    [ $# -eq 3 ] || (echo -e "Usage: GetDiskPartDevice <Disk> <Info> <String>" && return 1)

    local Disk=$1
    local Info=$2
    local String=$3
    local expr=""
    [ -n ${String} ] || return 1

    local Partitions=$(GetDiskPartitions ${Disk})
    [ $? -eq 0 ] && [ -n "${Partitions}" ] || return 1

    for Partition in ${Partitions}; do
        local PartInfo=$(GetDiskPartInfo ${Info} ${Partition})
        [ $? -eq 0 ] || return 1

        if [ x"${PartInfo}" = x"${String}" ]; then
            #echo ${Partition##*[a-zA-Z]}
            echo ${Partition}
            return 0
        fi
    done

    return 1
}

# Usage: FormatPartitions <VirtualDisk>
FormatPartitions() {
    [ $# -eq 1 ] || (echo -e "Usage: FormatPartitions <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -e ${VirtualDisk} ] || return 1

    if ! IsVirtualDiskLoaded ${VirtualDisk}; then
        echo -e "VirtualDisk[${C_HL}${VirtualDisk}${C_CLR}] does not loaded."
        return 1
    fi

    local Partitions=$(GetDiskPartitions ${VirtualDisk})
    [ $? -eq 0 ] && [ -n "${Partitions}" ] || return 1

    for Partition in ${Partitions}; do
        local PartType=$(GetDiskPartInfo Type ${Partition})
        if [ $? -eq 0 ] && [ -n "${PartType}" ]; then
            case ${PartType} in
                ext4)
                    fstype="ext4"
                    opts="-q -F"
                    ;;
                vfat)
                    fstype="vfat"
                    opts="-a"
                    ;;
                *)
                    echo -e "FORMAT_ERROR: Unkown filesystem type: ${PartType}"
                    return 1
                    ;;
            esac
        else
            local PartLabel=$(GetDiskPartInfo Label ${Partition})
            # [ -n "${PartLabel}" ] || (echo -e "FORMAT_ERROR: Get Partition Information failed" && return 1)
            if [ $? -eq 0 ] && [ -z "${PartLabel}" ]; then
                echo -e "FORMAT_ERROR: Get Partition Information failed"
                return 1
            else
                case ${PartLabel} in
                    ESP)
                        fstype="vfat"
                        opts="-a"
                        ;;
                    STBINFO|RECOVERY|ROOT|CONFIG|SYSCONF|DATA|USERDATA)
                        fstype="ext4"
                        opts="-q -F"
                        ;;
                    *)
                        echo -e "FORMAT_ERROR: Unkown partition label: ${PartLabel}"
                        return 1
                        ;;
                esac
            fi
        fi
        printf "FORMAT: Partition[${C_YEL}${Partition}${C_CLR}] --> [${C_BLU}${fstype}${C_CLR}] ..."
        if ! mkfs.${fstype} ${opts} ${Partition} > /dev/null 2>&1; then
            printf " [${C_FL}]\n" && return 1
        else
            printf " [${C_OK}]\n"
        fi
    done

    sync

    return 0
}

# Usage: IsTargetMounted <Target>
IsTargetMounted() {
    [ $# -eq 1 ] || (echo -e "Usage: IsTargetMounted <Target>" && return 1)

    local Target=$1

    if [ -d "${Target}" ]; then
        return $(mountpoint -q "${Target}")
    elif [ -f "${Target}" ] || [ -L "${Target}" ] || echo ${Target} | grep -q '^/dev'; then
        return $(mount | /bin/grep -q ${Target})
    else
        return 1
    fi
}

# Usage: GetTargetMountPoint <Device>
GetTargetMountPoint() {
    [ $# -eq 1 ] || (echo -e "Usage: GetTargetMountPoint <Device>" && return 1)

    local Device=$1
    [ -e ${Device} ] || return 1

    IsTargetMounted ${Device} || return 1
    local MountedDir=$(lsblk -n -o MOUNTPOINT ${Device})
    [ $? -eq 0 ] && [ -n "${MountedDir}" ] || return 1

    echo ${MountedDir}
}

# Usage: IsVirtualDiskMounted <VirtualDisk>
IsVirtualDiskMounted() {
    [ $# -eq 1 ] || (echo -e "Usage: IsVirtualDiskMounted <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -e ${VirtualDisk} ] || return 1

    IsVirtualDiskLoaded ${VirtualDisk} || return 1

    local loopdev=$(GetVirtualDiskLoadedDevice ${VirtualDisk})
    [ $? -eq 0 ] && [ -n "${loopdev}" ] || return 1

    if mount | /bin/grep -q "$(basename ${loopdev}p)"; then
        return 0
    fi
    return 1
}

# Usage: ShowVirtualDiskMountedInfo <VirtualDisk>
ShowVirtualDiskMountedInfo() {
    [ $# -eq 1 ] || (echo -e "Usage: IsVirtualDiskMounted <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -e ${VirtualDisk} ] || return 1

    IsVirtualDiskLoaded ${VirtualDisk} || return 0
    IsVirtualDiskMounted ${VirtualDisk} || return 0

    local loopdev=$(GetVirtualDiskLoadedDevice ${VirtualDisk})
    [ $? -eq 0 ] && [ -n "${loopdev}" ] || return 1

    local mdev_last=''
    echo -e "LOADED: ${C_HL}$(basename ${VirtualDisk})${C_CLR} ${C_YEL}${loopdev}${C_CLR}"
    mount | /bin/grep "$(basename ${loopdev}p)" | while read line; do
        local mdev=$(echo ${line} | awk '{print $1}')
        local mdir=$(echo ${line} | awk '{print $3}')
        mdir=${mdir#*${WorkDir}/}
        [ x"${mdev_last}" = x"${mdev}" ] || echo -e "MOUNTED: ${C_YEL}${mdev}${C_CLR} --> ${C_BLU}${mdir#*${WorkDir}/}${C_CLR}"
        mdev_last=${mdev}
    done
}

# Usage: GetVirtualDiskMountedParts <VirtualDisk>
GetVirtualDiskMountedParts() {
    [ $# -eq 1 ] || (echo -e "Usage: GetVirtualDiskMountedParts <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -e ${VirtualDisk} ] || return 1

    local loopdev=$(GetVirtualDiskLoadedDevice ${VirtualDisk})
    [ -n "${loopdev}" ] || return 1

    local MountedParts=$(mount | /bin/grep "$(basename ${loopdev}p)" | awk '{print $1}')
    [ -n "${MountedParts}" ] || return 1

    echo ${MountedParts}
}

# Usage: GetVirtualDiskMountedRoot <VirtualDisk>
GetVirtualDiskMountedRoot() {
    [ $# -eq 1 ] || (echo -e "Usage: GetVirtualDiskMountedRoot <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -e ${VirtualDisk} ] || return 1

    IsVirtualDiskMounted ${VirtualDisk} || return 1

    local Partitions=$(GetDiskPartitions ${VirtualDisk})
    [ $? -eq 0 ] && [ -n "${Partitions}" ] || return 1

    for Partition in ${Partitions}; do
        local PartLabel=$(GetDiskPartInfo Label ${Partition})
        if [ $? -eq 0 ] && [ x"${PartLabel}" = x"ROOT" ]; then
            IsTargetMounted ${Partition} || return 1
            local MountDir=$(mount | /bin/grep ${Partition} | /bin/grep $(realpath ${WorkDir}) | awk '{print $3}')
            [ $? -eq 0 ] && [ -n "${MountDir}" ] || return 1
            echo -e ${MountDir}
            return 0
        fi
    done
}

# Usage: Mount [-c <RootDir>] [-t <Type> | -b] <Source> <DstDir>
Mount() {
    local Usage="Usage: Mount [-c <RootDir>] [-t <Type> | -b] <Source> <DstDir>"
    local Prefix=""
    local Options=""
    local RootDir=""

    while [ $# -ne 0 ]; do
        case $1 in
            -c|--chroot)
                RootDir=$2
                Prefix="${Prefix:+${Prefix} }chroot ${RootDir}"
                shift 2
            ;;
            -t|--types)
                local Type=$2
                [[ ${Options} =~ "bind" ]] && (echo -e ${Usage} && return 1)
                Options="${Options:+${Options} }--types $2"
                shift 2
            ;;
            -b|--bind)
                [[ ${Options} =~ "types" ]] && (echo -e ${Usage} && return 1)
                Options="${Options:+${Options} }--bind"
                shift
            ;;
            *)
                [ $# -eq 2 ] || (echo -e ${Usage} && return 1)
                local Source=$1
                local DstDir=$2
                shift 2
            ;;
        esac
    done

    if [ -z ${Source} -o -z ${DstDir} ]; then
        echo -e ${Usage} && return 1
    fi

    if eval ${Prefix} mountpoint -q ${DstDir}; then
        return 0
    fi

    printf "MOUNT: ${C_GEN}${Options:+[${Options}] }${C_YEL}${Source#*${WorkDir}/}${C_CLR} --> ${C_BLU}${DstDir#*${WorkDir}/}${C_CLR}"
    if ! eval ${Prefix} mount ${Options} ${Source} ${DstDir} >/dev/null 2>&1; then
        printf " [${C_FL}]\n" && return 1
    fi
    printf " [${C_OK}]\n"

    return 0
}

# Usage: UnMount [-c <RootDir>] <Directory>
UnMount() {
    local Usage="Usage: UnMount [-c <RootDir>] <Directory>"
    local Prefix=""
    local RootDir=""
    local Directory=""

    while [ $# -ne 0 ]; do
        case $1 in
            -c|--chroot)
                RootDir=$2
                Prefix="${Prefix:+${Prefix} }chroot ${RootDir}"
                shift 2
            ;;
            *)
                [ $# -eq 1 ] || (echo -e ${Usage} && return 1)
                Directory=$1
                shift
            ;;
        esac
    done

    if [ -z ${Directory} ]; then
        echo -e ${Usage} && return 1
    fi

    if eval ${Prefix} umount --help | grep -q "recursive"; then
        if eval ${Prefix} mountpoint -q ${Directory}; then
            printf "UMOUNT: [${C_GEN}Recursive${C_CLR}] ${C_YEL}${Directory#*${WorkDir}/}${C_CLR}"
            if ! eval ${Prefix} umount -R ${Directory} >/dev/null 2>&1; then
                if ! eval ${Prefix} umount -Rl ${Directory} >/dev/null 2>&1; then
                    printf " [${C_FL}]\n" && return 1
                fi
            fi
            printf " [${C_OK}]\n"
        fi
    else
        dirlist=$(eval ${Prefix} mount | grep "${Directory}")
        [ $? -eq 0 ] && [ -n "${dirlist}" ] && return 0
        for dir in ${dirlist}; do
            if eval ${Prefix} mountpoint -q ${dir}; then
                printf "UNMOUNT: ${C_YEL}${dir}${C_CLR}"
                if ! eval ${Prefix} umount ${dir}; then
                    if ! eval ${Prefix} umount -l ${dir}; then
                        printf " [${C_FL}]\n" && return 1
                    fi
                fi
                printf " [${C_OK}]\n"
            fi
        done
    fi

    return 0
}

# Usage: MountVDisk <VirtualDisk> <RootDir>
MountVDisk() {
    [ $# -eq 2 ] || (echo -e "Usage: MountVDisk <VirtualDisk> <RootDir>" && return 1)

    local VirtualDisk=$1
    local RootDir=$2
    local StbInfoDir=${RootDir}/etc/stbinfo
    local UefiDir=${RootDir}/boot/efi
    local RecoveryDir=${RootDir}/boot/recovery
    local SysConfDir=${RootDir}/etc/sysconf
    local UserDataDir=${RootDir}/data

    # Check and load virtual disk
    if ! IsVirtualDiskLoaded ${VirtualDisk}; then
        LoadVirtualDisk ${VirtualDisk} || return 1
    fi

    # Get partitions list
    local Partitions=$(GetDiskPartitions ${VirtualDisk})
    [ $? -eq 0 ] && [ -n "${Partitions}" ] || return 1
    local LastParts=

    # Find ROOT partition and mount it first
    for dev in ${Partitions}; do
        local PartLabel=$(GetDiskPartInfo Label $(realpath -L ${dev}))
        [ $? -eq 0 ] && [ -n "${PartLabel}" ] || return 1
        if [ x"${PartLabel}" == x"ROOT" ]; then
            mkdir -p ${RootDir} || return 1
            #Mount $(realpath -L ${dev}) ${RootDir} || return 1
            Mount ${dev} ${RootDir} || return 1
        else
            LastParts=${LastParts:+${LastParts} }${dev}
        fi
    done

    # Mount other partitions
    for dev in ${LastParts}; do
        local PartLabel=$(GetDiskPartInfo Label $(realpath -L ${dev}))
        [ $? -eq 0 ] && [ -n "${PartLabel}" ] || return 1
        case ${PartLabel} in
            STBINFO)
                mkdir -p ${StbInfoDir} || return 1
                Mount ${dev} ${StbInfoDir} || return 1
            ;;
            ESP)
                mkdir -p ${UefiDir} || return 1
                Mount ${dev} ${UefiDir} || return 1
            ;;
            RECOVERY)
                mkdir -p ${RecoveryDir} || return 1
                Mount ${dev} ${RecoveryDir} || return 1
            ;;
            SYSCONF)
                mkdir -p ${SysConfDir} || return 1
                Mount ${dev} ${SysConfDir} || return 1
            ;;
            USERDATA)
                mkdir -p ${UserDataDir} || return 1
                Mount ${dev} ${UserDataDir} || return 1
            ;;
            *)
            ;;
        esac
    done

    return 0
}

# Usage: MountCache <RootDir> <CacheDir>
MountCache() {
    [ $# -eq 2 ] || (echo -e "Usage: MountCache <RootDir> <CacheDir>" && return 1)

    local RootDir=$1
    local CacheDir=$2
    local RootAptCache=${RootDir}/var/cache/apt
    local RootAptLists=${RootDir}/var/lib/apt/lists
    local CacheAptCache=${CacheDir}/aptcache
    local CacheAptLists=${CacheDir}/aptlists
    [ -n "${RootDir}" ] || return 1

    mkdir -p ${CacheAptCache} ${CacheAptLists} ${RootAptCache} ${RootAptLists} || return 1

    Mount --bind ${CacheAptCache} ${RootAptCache} || return 1
    Mount --bind ${CacheAptLists} ${RootAptLists} || return 1

    return 0
}

# Usage: UnMountCache <RootDir>
UnMountCache() {
    [ $# -eq 1 ] || (echo -e "Usage: UnMountCache <RootDir>" && return 1)

    local RootDir=$1
    local RootAptCache=${RootDir}/var/cache/apt
    local RootAptLists=${RootDir}/var/lib/apt/lists
    [ -n "${RootDir}" ] || return 1

    for dir in ${RootAptCache} ${RootAptLists}; do
        UnMount ${dir} || return 1
    done

    return 0
}

# Usage: MountSystemEntries <RootDir>
MountSystemEntries() {
    [ $# -eq 1 ] || (echo -e "Usage: MountSystemEntries <RootDir>" && return 1)

    local RootDir=$1
    [ -n "${RootDir}" ] || return 1

    mkdir -p ${RootDir}/proc ${RootDir}/sys ${RootDir}/dev ${RootDir}/run ${RootDir}/tmp || return 1

    if [ -x ${RootDir}/bin/mount ]; then
        Mount --chroot ${RootDir} --types proc proc /proc
        Mount --chroot ${RootDir} --types sysfs sysfs /sys
        Mount --chroot ${RootDir} --types devtmpfs udev /dev
        [ -d ${RootDir}/dev/pts ] || mkdir ${RootDir}/dev/pts
        Mount --chroot ${RootDir} --types devpts devpts /dev/pts
        Mount --bind /run ${RootDir}/run
        Mount --bind /tmp ${RootDir}/tmp
    else
        echo -e "MOUNT: ${C_WARN} Please unpack rootfs package first."
        return 99
    fi

    return 0
}

# Usage: UnMountSystemEntries <RootDir>
UnMountSystemEntries() {
    [ $# -eq 1 ] || (echo -e "Usage: MountSystemEntries <RootDir>" && return 1)

    local RootDir=$1
    local Prefix=""
    [ -n "${RootDir}" ] || return 1

    [ -x ${RootDir}/bin/mountpoint ] && Prefix="chroot ${RootDir}"

    for dir in tmp run dev/pts dev sys proc; do
        if eval ${Prefix} mountpoint -q ${RootDir}/proc; then
            UnMount --chroot ${RootDir} ${dir} || return 1
        else
            UnMount ${RootDir}/${dir} || return 1
        fi
    done

    return 0
}

# Usage: MountUserEntries <RootDir>
MountUserEntries() {
    [ $# -eq 1 ] || (echo -e "Usage: MountUserEntries <RootDir>" && return 1)

    local RootDir=$1
    local UserDir=${RootDir}/data
    [ -n "${RootDir}" ] || return 1

    for dir in home root var/log; do
        mkdir -p ${RootDir}/${dir} ${UserDir}/${dir} || return 1
        Mount --bind ${UserDir}/${dir} ${RootDir}/${dir} || return 1
    done

    return 0
}

# Usage: UnMountUserEntries <RootDir>
UnMountUserEntries() {
    [ $# -eq 1 ] || (echo -e "Usage: UnMountUserEntries <RootDir>" && return 1)

    local RootDir=$1
    [ -n "${RootDir}" ] || return 1

    for dir in home root var/log; do
        UnMount ${RootDir}/${dir} || return 1
    done

    return 0
}

# Usage: MountAll <VirtualDisk> <RootDir> <CacheDir>
MountAll() {
    [ $# -eq 3 ] || (echo -e "Usage: MountAll <VirtualDisk> <RootDir> <CacheDir>" && return 1)

    local VirtualDisk=$1
    local RootDir=$2
    local CacheDir=$3
    local StbInfoDir=${RootDir}/etc/stbinfo
    local UefiDir=${RootDir}/boot/efi
    local RecoveryDir=${RootDir}/boot/recovery
    local SysConfDir=${RootDir}/etc/sysconf
    local UserDataDir=${RootDir}/data

    # Mount virtual disk
    MountVDisk ${VirtualDisk} ${RootDir} || (echo "MountVDisk failed" && return 1)

    # Mount Cache dirs
    local SysLogDir=${RootDir}/var/log
    local SysLogSaveDir=${UserDataDir}/var/log

    mkdir -p ${SysLogDir} ${SysLogSaveDir}
    Mount --bind ${SysLogSaveDir} ${SysLogDir} || return 1

    MountCache ${RootDir} ${CacheDir} || return ?
    MountSystemEntries ${RootDir} || return $?
    MountUserEntries ${RootDir} || return $?

    return 0
}

# Usage: UnMountAll <VirtualDisk> <RootDir>
UnMountAll() {
    [ $# -eq 2 ] || (echo -e "Usage: UnMountAll <VirtualDisk> <RootDir>" && return 1)

    local VirtualDisk=$1
    local RootDir=$2

    if IsVirtualDiskMounted ${VirtualDisk}; then
        local VirtualDiskRoot=$(GetVirtualDiskMountedRoot ${VirtualDisk})
        if [ $? -eq 0 ] && [ -n "${VirtualDiskRoot}" ]; then
            UnMountCache ${VirtualDiskRoot} || return 1
            UnMountUserEntries ${VirtualDiskRoot} || return 1
            UnMountSystemEntries ${VirtualDiskRoot} || return 1
            UnMount ${VirtualDiskRoot} || return 1
        fi
    fi

    UnMountCache ${RootDir} || return 1
    UnMountUserEntries ${RootDir} || return 1
    UnMountSystemEntries ${RootDir} || return 1

    UnMount ${RootDir} || return 1

    return 0
}

# Usage: UnLoadVirtualDisk <VirtualDisk>
UnLoadVirtualDisk() {
    [ $# -eq 1 ] || (echo -e "Usage: UnLoadVirtualDisk <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -e ${VirtualDisk} ] || return 1

    if IsVirtualDiskMounted ${VirtualDisk}; then
        ShowVirtualDiskMountedInfo ${VirtualDisk} || return 1
        MountedDir=$(GetVirtualDiskMountedRoot ${VirtualDisk})
        [ $? -eq 0 ] && [ -n "${MountedDir}" ] || return 1
        UnMountAll ${VirtualDisk} ${MountedDir} || return 1
    fi

    if IsVirtualDiskLoaded ${VirtualDisk}; then
        local LoopDevice=$(GetVirtualDiskLoadedDevice ${VirtualDisk})
        if [ $? -eq 0 ] && [ -n "${LoopDevice}" ]; then
            printf "UNLOADING: ${C_HL}$(basename ${VirtualDisk})${C_CLR} <--> ${C_YEL}${LoopDevice}${C_CLR} "
            losetup --detach ${LoopDevice} >/dev/null 2>&1
            # if ! IsVirtualDiskLoaded ${VirtualDisk}; then
            if [ $? -eq 0 ]; then
                printf " [${C_OK}]\n" && return 0
            else
                printf " [${C_FL}]\n" && return 1
            fi
        fi
    fi
    echo -e "VirtualDisk ${C_HL}$(basename ${VirtualDisk})${C_CLR} not loaded"

    return 0
}

# Usage: InitializeVirtualDisk <VirtualDisk> <RootDir>
InitializeVirtualDisk() {
    [ $# -eq 2 ] || (echo -e "Usage: InitializeVirtualDisk <VirtualDisk> <RootDir>" && return 1)

    local VirtualDisk=$1
    local RootDir=$2

    # Check VirtualDisk exist
    if [ ! -e ${VirtualDisk} ]; then
        echo -e "Cannot find VirtualDisk file ${C_HL}${VirtualDisk}${C_CLR}, create it."
        CreateVirtualDisk ${VirtualDisk} || return 1
        CreatePartitions ${VirtualDisk} || return 1
    fi

    # Unmount VirtualDisk
    UnMountAll ${VirtualDisk} ${RootDir} || return 1

    # Load VirtualDisk
    if ! IsVirtualDiskLoaded ${VirtualDisk}; then
        LoadVirtualDisk ${VirtualDisk} || return 1
    fi

    # Format VirtualDisk partitions
    FormatPartitions ${VirtualDisk} || return 1

    return 0
}

# Usage: UnPackRootFS <Package> <RootDir>
UnPackRootFS() {
    [ $# -eq 2 ] || (echo -e "Usage: UnPackRootFS <Package> <RootDir>" && return 1)

    local Package=$1
    local RootDir=$2

    printf "UNPACK: ${C_HL}$(basename ${Package})${C_CLR} --> ${C_BLU}$(basename ${RootDir})${C_CLR} ..."
    if ! tar --exclude=dev/* -xf ${Package} -C ${RootDir} >>/dev/null 2>&1; then
        printf " [${C_FL}]\n" && return 1
    else
        printf " [${C_OK}]\n"
    fi
}

# Usage: GetConfPackages <ConfigFile> <Section>
GetConfPackages() {
    [ $# -eq 2 ] || (echo -e "Usage: GetConfPackages <ConfigFile> <Section>" && return 1)
    local ConfigFile=$1
    local Section=$2
    local Packages=""

    [ -n "${ConfigFile}" ] || return 1
    [ -f "${ConfigFile}" ] || return 1

    local PackagesList=$(ConfGetKeys ${ConfigFile} ${Section})
    [ $? -eq 0 ] && [ -n "${PackagesList}" ] || return 1

    for Package in ${PackagesList}; do
        local Enabled=$(ConfGetValue ${ConfigFile} ${Section} ${Package})
        if [ $? -eq 0 ] && [ -n "${Enabled}" ]; then
            case ${Enabled} in
                y|Y|yes|YES|Yes)
                    Packages=${Packages:+${Packages} }${Package}
                    ;;
                *)
                    ;;
            esac
        fi
    done

    if [ -z "${Packages}" ]; then
        return 1
    fi

    echo ${Packages}
}

# Usage: ReplaceFiles <RootDir> <ProfilesDir> <Files...>
ReplaceFiles() {
    [ $# -gt 2 ] || (echo -e "Usage: ReplaceFiles <RootDir> <ProfilesDir> <Files...>" && return 1)

    local RootDir=$1
    local ProfilesDir=$2
    shift 2
    local FileList=$@
    local BackupDir=${ProfilesDir}/backup
    local ModifiedDir=${ProfilesDir}/modified

    if [ -d "${ProfilesDir}/modified" ]; then
        for File in ${FileList}; do
            # Backup File
            mkdir -p ${BackupDir} || return $?
            if [ -f "${RootDir}/${File}" ]; then
                cp -a "${RootDir}/${File}" "${BackupDir}" >/dev/null 2>&1
            fi
            # Copy File
            FileName=$(basename ${File})
            if [ -f "${ModifiedDir}/${FileName}" ]; then
                printf "REPLACE: ${C_HL}${File}${C_CLR} ..."
                mkdir -p "$(dirname ${RootDir}/${File})" || return $?
                if ! cp -a "${ModifiedDir}/${FileName}" "${RootDir}/${File}" >/dev/null 2>&1; then
                    printf " [${C_FL}]\n"
                else
                    printf " [${C_OK}]\n"
                fi
            fi
        done
    fi
}

# Usage: InstallPreSettings <RootDir> <PreSettingsDir>
InstallPreSettings() {
    [ $# -eq 2 ] || (echo -e "Usage: InstallPreSettings <RootDir> <PreSettingsDir>" && return 1)

    local RootDir=$1
    local PreSettingsDir=$2
    [ -d ${PreSettingsDir} ] || return 1
    [ -d ${RootDir} ] || return 1

    printf "PRESETTING: Installing Pre-Settings files ..."
    if rsync -aq ${PreSettingsDir}/ ${RootDir}; then
        printf "[${C_OK}]\n"
        return 0
    else
        printf "[${C_FL}]\n"
        return 1
    fi
}

# Usage: InstallPackages <RootDir> <Option: Update|Upgrade|Install> <Packages...>
InstallPackages() {
    [ $# -ge 2 ] || (echo -e "Usage: InstallPackages <RootDir> <Option: Update|Upgrade|Install> <Packages...>" && return 1)
    local RootDir=$1
    local Options=$2
    shift 2
    local Packages=$@
    local InsLogFile=$(pwd)/InsLogFile.log
    local AptOptions=""

    [ -n "${RootDir}" ] || return 1
    [ -n "${InsLogFile}" ] || return 1
    [ -f ${InsLogFile} ] && rm -f ${InsLogFile}
    [ -d ${RootDir} ] || return 1
    [ -n "${Options}" ] || return 1

    AptOptions="${AptOptions:+${AptOptions} }--quiet"
    AptOptions="${AptOptions:+${AptOptions} }--yes"
    AptOptions="${AptOptions:+${AptOptions} }--allow-change-held-packages"
    AptOptions="${AptOptions:+${AptOptions} }--force-yes"
    AptOptions="${AptOptions:+${AptOptions} }--no-install-recommends"

    case ${Options} in
        -u|--update|Update|UPDATE)
            printf "PKGINSTALL: ${C_YEL}Updating${C_CLR} Packages List ..."
            # if ! chroot ${RootDir} apt-get ${AptOptions} update >>${InsLogFile} 2>&1; then
            if ! chroot ${RootDir} apt ${AptOptions} update >>${InsLogFile} 2>&1; then
                printf " [${C_FL}]\n" && return 1
            else
                printf " [${C_OK}]\n"
            fi
        ;;
        -U|--upgrade|Upgrade|UPGRADE)
            printf "PKGINSTALL: ${C_YEL}Upgrading${C_CLR} Packages ..."
            # if ! chroot ${RootDir} apt-get ${AptOptions} upgrade >>${InsLogFile} 2>&1; then
            if ! chroot ${RootDir} apt ${AptOptions} upgrade >>${InsLogFile} 2>&1; then
                printf " [${C_FL}]\n" && return 1
            else
                printf " [${C_OK}]\n"
            fi
        ;;
        -i|--install|Install|INSTALL)
            for Package in ${Packages}; do
                printf "PKGINSTALL: ${C_YEL}Installing${C_CLR} ${C_HL}${Package}${C_CLR} ..."
                # if ! chroot ${RootDir} apt-get ${AptOptions} install ${Package} >>${InsLogFile} 2>&1; then
                if ! DEBIAN_FRONTEND=noninteractive chroot ${RootDir} apt ${AptOptions} install ${Package} >>${InsLogFile} 2>&1; then
                    printf " [${C_FL}]\n" && return 1
                else
                    printf " [${C_OK}]\n"
                fi
            done
        ;;
        -f|--fix-broken|Fix|FIX|FixBroken|FIXBROKEN)
            printf "PKGCHECK: ${C_YEL}Checking${C_CLR} Packages ..."
            # if ! chroot ${RootDir} apt-get ${AptOptions} --fix-broken install >>${InsLogFile} 2>&1; then
            if ! chroot ${RootDir} apt ${AptOptions} --fix-broken install >>${InsLogFile} 2>&1; then
                printf " [${C_FL}]\n" && return 1
            else
                printf " [${C_OK}]\n"
            fi
        ;;
        *)
            echo -e "PKGINSTALL: Error: Unknown Options"
            return 1
        ;;
    esac

    rm -f ${InsLogFile}
    return 0
}

# Usage: InstallExtrenPackages <RootDir> <Packages>
InstallExtrenPackages() {
    [ $# -ge 2 ] || (echo -e "Usage: InstallExtrenPackages <RootDir> <Packages>" && return 1)

    local RootDir=$1
    shift
    local Packages=$@

    local InsLogFile=$(pwd)/InsLogFile.log
    [ -d "${RootDir}" ] || return 1
    [ -n "${Packages}" ] || return 1

    local DpkgOptions=""
    DpkgOptions="${DpkgOptions:+${DpkgOptions} }--install"

    for Package in ${Packages}; do
        [ -f "${ExtPackageDir}/${Package}" ] || continue
        printf "PKGINSTALL: ${C_YEL}Installing${C_CLR} ${C_HL}${Package}${C_CLR} ..."
        cp ${ExtPackageDir}/${Package} ${RootDir}/tmp
        DEBIAN_FRONTEND=noninteractive chroot ${RootDir} dpkg ${DpkgOptions} /tmp/${Package} >>${InsLogFile} 2>&1
        if [ $? -ne 0 ]; then
            DEBIAN_FRONTEND=noninteractive chroot ${RootDir} apt install -f >>${InsLogFile} 2>&1
            if [ $? -ne 0 ]; then
                printf " [${C_FL}]\n" && return 1
            else
                printf " [${C_OK}]\n"
            fi
        else
            printf " [${C_OK}]\n"
        fi
        rm ${RootDir}/tmp/${Package}
    done
}

# Usage: UnInstallPackages <RootDir> <Option: Remove|Purge> <Packages...>
UnInstallPackages() {
    [ $# -ge 2 ] || (echo -e "Usage: UnInstallPackages <RootDir> <Option: Remove|Purge> <Packages...>" && return 1)
    local RootDir=$1
    local Options=$2
    shift 2
    local Packages=$@
    local LogFile=$(pwd)/LogFile-Package.log
    local AptOptions=""

    [ -d "${RootDir}" ] || (echo "Cannot find Rootfs dir."; return 1)
    [ -n "${Packages}" ] || (echo "Please assign at least one package to uninstall."; return 1)
    [ -f "${LogFile}" ] && rm -f "${LogFile}"

    AptOptions="${AptOptions:+${AptOptions} }--quiet"
    AptOptions="${AptOptions:+${AptOptions} }--yes"
    AptOptions="${AptOptions:+${AptOptions} }--allow-change-held-packages"
    # AptOptions="${AptOptions:+${AptOptions} }--force-yes"
    # AptOptions="${AptOptions:+${AptOptions} }--no-install-recommends"

    case ${Options} in
        -r|--remove|remove|Remove|REMOMVE)
            for Package in ${Packages}; do
                printf "PKGUNINSTALL: ${C_YEL}Removing${C_CLR} ${C_HL}${Package}${C_CLR} ..."
                if ! DEBIAN_FRONTEND=noninteractive chroot "${RootDir}" apt ${AptOptions} remove ${Package} >>"${LogFile}" 2>&1; then
                    printf " [${C_FL}]\n" && return 1
                else
                    printf " [${C_OK}]\n"
                fi
            done
            ;;
        -p|--purge|purge|Purge|PURGE)
            for Package in ${Packages}; do
                printf "PKGUNINSTALL: ${C_YEL}Purging${C_CLR} ${C_HL}${Package}${C_CLR} ..."
                if ! DEBIAN_FRONTEND=noninteractive chroot "${RootDir}" apt ${AptOptions} purge ${Package} >>"${LogFile}" 2>&1; then
                    printf " [${C_FL}]\n" && return 1
                else
                    printf " [${C_OK}]\n"
                fi
            done
            ;;
        *)
            echo -e "PKGUNINSTALL: Error: Unknown Options [${Options}]"
            return 1
            ;;
    esac

    rm -f "${LogFile}"
    return 0
}

# Usage: UpdateFSTAB <VirtualDisk> <RootDir>
UpdateFSTAB() {
    [ $# -eq 2 ] || (echo -e "Usage: UpdateFSTAB <VirtualDisk> <RootDir>" && return 1)

    local VirtualDisk=$1
    local RootDir=$2

    [ -f ${VirtualDisk} ] || return 1

    # Check and load virtual disk
    if ! IsVirtualDiskLoaded ${VirtualDisk}; then
        LoadVirtualDisk ${VirtualDisk} || return 1
    fi

    local Partitions=$(GetDiskPartitions ${VirtualDisk})
    [ $? -eq 0 ] && [ -n "${Partitions}" ] || return 1

    local StbiUUID=
    local UefiUUID=
    local RecoUUID=
    local RootUUID=
    local ConfUUID=
    local UserUUID=

    for dev in ${Partitions}; do
        local PartLabel=$(GetDiskPartInfo Label $(realpath -L ${dev}))
        [ $? -eq 0 ] && [ -n "${PartLabel}" ] || return 1
        case ${PartLabel} in
            ESP)
                UefiUUID=$(GetDiskPartInfo UUID $(realpath -L ${dev}))
                [ $? -eq 0 ] && [ -n "${UefiUUID}" ] || return 1
            ;;
            STBINFO)
                StbiUUID=$(GetDiskPartInfo UUID $(realpath -L ${dev}))
                [ $? -eq 0 ] && [ -n "${StbiUUID}" ] || return 1
            ;;
            RECOVERY)
                RecoUUID=$(GetDiskPartInfo UUID $(realpath -L ${dev}))
                [ $? -eq 0 ] && [ -n "${RecoUUID}" ] || return 1
            ;;
            ROOT)
                RootUUID=$(GetDiskPartInfo UUID $(realpath -L ${dev}))
                [ $? -eq 0 ] && [ -n "${RootUUID}" ] || return 1
            ;;
            SYSCONF|CONFIG)
                ConfUUID=$(GetDiskPartInfo UUID $(realpath -L ${dev}))
                [ $? -eq 0 ] && [ -n "${ConfUUID}" ] || return 1
            ;;
            USERDATA)
                UserUUID=$(GetDiskPartInfo UUID $(realpath -L ${dev}))
                [ $? -eq 0 ] && [ -n "${UserUUID}" ] || return 1
            ;;
            *)
            ;;
        esac
    done

    printf "UPDATE-FSTAB: Updating ${C_HL}$(basename ${RootDir})/etc/fstab${C_CLR} ..."
    mkdir -p ${RootDir}/etc
    local FSTAB=''
    FSTAB="${FSTAB:+${FSTAB}\n}# System Entry"
    [ -n "${RootUUID}" ] && FSTAB="${FSTAB:+${FSTAB}\n}UUID=${RootUUID} /               ext4  noatime,nodiratime,errors=remount-ro  0 1"
    [ -n "${UefiUUID}" ] && FSTAB="${FSTAB:+${FSTAB}\n}UUID=${UefiUUID} /boot/efi       vfat  umask=0077                            0 1"
    [ -n "${RecoUUID}" ] && FSTAB="${FSTAB:+${FSTAB}\n}UUID=${RecoUUID} /boot/recovery  ext4  ro,noatime,nodiratime                 0 1"
    [ -n "${StbiUUID}" ] && FSTAB="${FSTAB:+${FSTAB}\n}UUID=${StbiUUID} /etc/stbinfo    ext4  ro,noatime,nodiratime                 0 1"
    [ -n "${ConfUUID}" ] && FSTAB="${FSTAB:+${FSTAB}\n}UUID=${ConfUUID} /etc/sysconf    ext4  noatime,nodiratime                    0 2"
    [ -n "${UserUUID}" ] && FSTAB="${FSTAB:+${FSTAB}\n}UUID=${UserUUID} /data           ext4  noatime,nodiratime                    0 2"
    [ -n "${UserUUID}" ] && FSTAB="${FSTAB:+${FSTAB}\n}UUID=${UserUUID} /data           ext4  noatime,nodiratime                    0 2"
    FSTAB="${FSTAB:+${FSTAB}\n}"
    FSTAB="${FSTAB:+${FSTAB}\n}# User Data Entry"
    FSTAB="${FSTAB:+${FSTAB}\n}/data/home       /home           none  rw,bind                               0 0"
    FSTAB="${FSTAB:+${FSTAB}\n}/data/root       /root           none  rw,bind                               0 0"
    FSTAB="${FSTAB:+${FSTAB}\n}/data/var/log    /var/log        none  rw,bind                               0 0"
    FSTAB="${FSTAB:+${FSTAB}\n}"
    echo -e "${FSTAB}" > ${RootDir}/etc/fstab

    if [ $? -ne 0 ]; then
        printf " [${C_FL}]\n" && return 1
    else
        printf " [${C_OK}]\n"
    fi

    [ -n "${UefiUUID}" ] && echo -e "  ${C_YEL}ESP${C_CLR}      UUID = ${C_BLU}${UefiUUID}${C_CLR}"
    [ -n "${StbiUUID}" ] && echo -e "  ${C_YEL}STBINFO${C_CLR}  UUID = ${C_BLU}${StbiUUID}${C_CLR}"
    [ -n "${RecoUUID}" ] && echo -e "  ${C_YEL}RECOVERY${C_CLR} UUID = ${C_BLU}${RecoUUID}${C_CLR}"
    [ -n "${RootUUID}" ] && echo -e "  ${C_YEL}ROOT${C_CLR}     UUID = ${C_BLU}${RootUUID}${C_CLR}"
    [ -n "${ConfUUID}" ] && echo -e "  ${C_YEL}SYSCONF${C_CLR}  UUID = ${C_BLU}${ConfUUID}${C_CLR}"
    [ -n "${UserUUID}" ] && echo -e "  ${C_YEL}USERDATA${C_CLR} UUID = ${C_BLU}${UserUUID}${C_CLR}"

    return 0
}

# UpdateTimeZone <RootDir> <TimeZone>
UpdateTimeZone() {
    [ $# -eq 2 ] || (echo -e "Usage: UpdateTimeZone <RootDir> <TimeZone>" && return 1)

    local RootDir=$1
    local TimeZone=$2
    [ -n "${RootDir}" ] || return 1
    [ -n "${TimeZone}" ] || return 1

    IsTargetMounted ${RootDir} || (echo -e "${C_BLU}${RootDIr}${C_CLR} not mounted"; return 1)

    local tzConf=${RootDir}/etc/timezone
    local ltLink=${RootDir}/etc/localtime

    printf "UPDATE-TIMEZONE: Updating ${C_HL}$(basename ${RootDir})/etc/timezone${C_CLR} ..."
    echo "${TimeZone}" > ${tzConf}
    chown root:root ${tzConf}
    rm -f ${ltLink}
    ln -s /usr/share/zoneinfo/${TimeZone} ${ltLink}

    if [ $? -ne 0 ]; then
        printf " [${C_FL}]\n" && return 1
    else
        printf " [${C_OK}]\n"
    fi

    return 0
}

# Usage: UpdateLocales <RootDir> <Locales>
UpdateLocales() {
    [ $# -gt 1 ] || (echo -e "Usage: UpdateLocales <RootDir> <Locales>" && return 1)

    local RootDir=$1
    shift
    local Locales=$@
    [ -n "${RootDir}" ] || return 1
    [ -d "${RootDir}" ] || return 1
    [ -n "${Locales}" ] || return 1

    IsTargetMounted ${RootDir} || (echo -e "${C_BLU}${RootDIr}${C_CLR} not mounted"; return 1)

    if [ -x ${RootDir}/usr/sbin/locale-gen ]; then
        for locale in ${Locales}; do
            printf "UPDATE-LOCALE: Updating ${C_HL}${locale}${C_CLR} ..."
            if ! chroot ${RootDir} locale-gen ${locale} >/dev/null 2>&1; then
                printf " [${C_FL}]\n" && return 1
            else
                printf " [${C_OK}]\n"
            fi
        done
    else
        echo "Error: Missing locale-gen command, please install locales package first!"
        return 1
    fi

    return 0
}

# Usage: UpdateSourcesList <RootDir> <AptUrl>
UpdateSourcesList() {
    [ $# -eq 2 ] || (echo -e "Usage: UpdateSourcesList <RootDir> <AptUrl>" && return 1)

    local RootDir=$1
    local AptUrl=$2
    [ -n "${RootDir}" ] || return 1
    [ -n "${AptUrl}" ] || return 1

    IsTargetMounted ${RootDir} || (echo -e "${C_BLU}${RootDIr}${C_CLR} not mounted"; return 1)

    local SourceListFile=${RootDir}/etc/apt/sources.list
    if [ -f ${SourceListFile} ]; then
        printf "UPDATE-SOURCESLIST: Updating ${C_HL}$(basename ${RootDir})/etc/apt/sources.list${C_CLR} ..."
        local CodeName=$(grep partner ${RootDir}/etc/apt/sources.list | awk '/^# deb /{print $4}')
        local SourceList=$(head -1 ${SourceListFile})
        SourceList="${SourceList:+${SourceList}\n}"
        SourceList="${SourceList:+${SourceList}\n}deb ${AptUrl} ${CodeName} main restricted universe multiverse"
        SourceList="${SourceList:+${SourceList}\n}deb ${AptUrl} ${CodeName}-updates main restricted universe multiverse"
        SourceList="${SourceList:+${SourceList}\n}deb ${AptUrl} ${CodeName}-security main restricted universe multiverse"
        SourceList="${SourceList:+${SourceList}\n}# deb ${AptUrl} ${CodeName}-backports main restricted universe multiverse"
        SourceList="${SourceList:+${SourceList}\n}"
        SourceList="${SourceList:+${SourceList}\n}# deb-src ${AptUrl} ${CodeName} main restricted universe multiverse"
        SourceList="${SourceList:+${SourceList}\n}# deb-src ${AptUrl} ${CodeName}-updates main restricted universe multiverse"
        SourceList="${SourceList:+${SourceList}\n}# deb-src ${AptUrl} ${CodeName}-security main restricted universe multiverse"
        SourceList="${SourceList:+${SourceList}\n}# deb-src ${AptUrl} ${CodeName}-backports main restricted universe multiverse"
        SourceList="${SourceList:+${SourceList}\n}"
        SourceList="${SourceList:+${SourceList}\n}# Canonical's 'partner' repository."
        SourceList="${SourceList:+${SourceList}\n}# deb http://archive.canonical.com/ubuntu ${CodeName} partner"
        SourceList="${SourceList:+${SourceList}\n}# deb-src http://archive.canonical.com/ubuntu ${CodeName} partner"
        SourceList="${SourceList:+${SourceList}\n}"

        echo -e "${SourceList}" > ${SourceListFile}

        if [ $? -ne 0 ]; then
            printf " [${C_FL}]\n" && return 1
        else
            printf " [${C_OK}]\n"
        fi
    fi
}

# Usage: SetUserPassword <RootDir> <Username> <Password>
SetUserPassword() {
    [ $# -eq 3 ] || (echo -e "Usage: SetUserPassword <RootDir> <Username> <Password>" && return 1)

    local RootDir=$1
    local Username=$2
    local Password=$3
    [ -n "${RootDir}" ] || return 1
    [ -d "${RootDir}" ] || return 1
    [ -n "${Username}" ] || return 1
    [ -n "${Password}" ] || return 1

    IsTargetMounted ${RootDir} || return 1

    if ! /bin/grep -q ${Username} ${RootDir}/etc/passwd; then
        printf "SETPASSWD: Adding User: ${C_HL}${Username}${C_CLR} ..."
        if ! chroot ${RootDir} useradd --user-group --create-home --skel /etc/skel --shell /bin/bash ${Username}; then
            printf printf " [${C_FL}]\n" && return 1
        else
            printf " [${C_OK}]\n"
        fi
    fi

    # Init Root User with base profile
    local SkelDir=${RootDir}/etc/skel
    local RootUserDir=${RootDir}/root
    rsync -aq ${SkelDir}/ ${RootUserDir}

    local ChPwdScript="/tmp/ChangeUserPassword"

    printf "SETPASSWD: Change Password: [${C_HL}${Username}${C_CLR}]:[${C_GEN}${Password}${C_CLR}] ..."
    local SCRIPT=''
    SCRIPT="${SCRIPT:+${SCRIPT}\n}#!/bin/bash"
    SCRIPT="${SCRIPT:+${SCRIPT}\n}echo ${Username}:${Password} | chpasswd"

    if echo -e ${SCRIPT} > ${RootDir}/${ChPwdScript} && chroot ${RootDir} bash ${ChPwdScript} && rm -f ${RootDir}/${ChPwdScript}; then
        printf " [${C_OK}]\n"
    else
        printf " [${C_FL}]\n" && return 1
    fi

    return 0
}

# Usage: SetupBootloader <VirtualDisk> <RootDir> <BootloaderID>
SetupBootloader() {
    [ $# -eq 3 ] || (echo -e "Usage: SetupBootloader <VirtualDisk> <RootDir> <BootloaderID>" && return 1)

    local VirtualDisk=$1
    local RootDir=$2
    local BootloaderID=$3
    local BootloaderArch="x86_64-efi"
    local BootloaderLogfile=$(pwd)/bootloader.log
    [ -n "${VirtualDisk}" ] || return 1
    [ -e "${VirtualDisk}" ] || return 1
    [ -n "${RootDir}" ] || return 1
    [ -d "${RootDir}" ] || return 1
    [ -n "${BootloaderID}" ] || return 1
    [ -f ${BootloaderLogfile} ] && rm -f ${BootloaderLogfile}

    IsVirtualDiskLoaded ${VirtualDisk} || return 1
    IsTargetMounted ${RootDir} || return 1

    local Partitions=$(GetDiskPartitions ${VirtualDisk})
    [ $? -eq 0 ] && [ -n "${Partitions}" ] || return 1
    for Partition in ${Partitions}; do
        local PartLabel=$(GetDiskPartInfo Label $(realpath -L ${Partition}))
        if [ $? -eq 0 ] && [ x"${PartLabel}" == x"ESP" ]; then
            IsTargetMounted ${Partition} || return 1
        fi
    done

    local BootDevice=$(GetVirtualDiskLoadedDevice ${VirtualDisk})
    [ $? -eq 0 ] && [ -n "${BootDevice}" ] || return 1

    # Setup grub default settings
    local GrubDefault=${RootDir}/etc/default/grub
    local RootPartDev=$(GetDiskPartDevice ${VirtualDisk} LABEL ROOT)
    [ $? -eq 0 ] || return 1
    local RootPartUUID=$(GetDiskPartInfo PARTUUID ${RootPartDev})
    [ $? -eq 0 ] || return 1
    if [ -f ${GrubDefault} ]; then
        local Rst=0
        printf "BOOTLOADER: Update Bootloader Settings ..."

        # Bootup and Shutdown logo
        if /bin/grep -q "GRUB_CMDLINE_LINUX_DEFAULT" ${GrubDefault}; then
            sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT=/" ${GrubDefault}
        else
            echo "GRUB_CMDLINE_LINUX_DEFAULT=" >> ${GrubDefault}
        fi
        Rst=$((${Rst} + $?))

        # Close Other OS Prober
        if /bin/grep -q "GRUB_DISABLE_OS_PROBER" ${GrubDefault}; then
            sed -i "s/^GRUB_DISABLE_OS_PROBER.*/GRUB_DISABLE_OS_PROBER=true/" ${GrubDefault}
        else
            echo "GRUB_DISABLE_OS_PROBER=true" >> ${GrubDefault}
        fi
        Rst=$((${Rst} + $?))

        # Set Root Partition PARTUUID
        if /bin/grep -q "GRUB_FORCE_PARTUUID" ${GrubDefault}; then
            sed -i "s/^GRUB_FORCE_PARTUUID.*/GRUB_FORCE_PARTUUID=${RootPartUUID}/" ${GrubDefault}
        else
            echo "GRUB_FORCE_PARTUUID=${RootPartUUID}" >> ${GrubDefault}
        fi
        Rst=$((${Rst} + $?))

        if [ ${Rst} -ne 0 ]; then
            printf " [${C_FL}]\n" && return ${Rst}
        else
            printf " [${C_OK}]\n"
        fi
    fi

    local BootOptions=""
    BootOptions="${BootOptions:+${BootOptions} }--target=${BootloaderArch}"
    BootOptions="${BootOptions:+${BootOptions} }--boot-directory=/boot"
    BootOptions="${BootOptions:+${BootOptions} }--efi-directory=/boot/efi"
    BootOptions="${BootOptions:+${BootOptions} }--bootloader-id=${BootloaderID}"
    BootOptions="${BootOptions:+${BootOptions} }--no-uefi-secure-boot"
    BootOptions="${BootOptions:+${BootOptions} }--recheck"

    printf "BOOTLOADER: Installing Bootloader to ${C_YEL}${BootDevice}${C_CLR} ..."
    if ! chroot ${RootDir} grub-install ${BootOptions} ${BootDevice} >>${BootloaderLogfile} 2>&1; then
        printf " [${C_FL}]\n" && return 1
    else
        printf " [${C_OK}]\n"
    fi

    printf "BOOTLOADER: Generate Bootloader Configuration ..."
    if ! chroot ${RootDir} update-grub >>${BootloaderLogfile} 2>&1; then
        printf " [${C_FL}]\n" && return 1
    else
        printf " [${C_OK}]\n"
    fi

    # GENERATE GRUB EFI IMAGE AGAIN TO FIX GRUB CAN NOT FIND CONFIG
    local RootPartitionIndex=${RootPartDev##*[a-zA-Z]}
    local BootIMGOptions=""
    BootIMGOptions="${BootIMGOptions:+${BootIMGOptions} }--format ${BootloaderArch}"
    BootIMGOptions="${BootIMGOptions:+${BootIMGOptions} }--directory /usr/lib/grub/${BootloaderArch}"
    BootIMGOptions="${BootIMGOptions:+${BootIMGOptions} }--prefix (hd0,gpt${RootPartitionIndex})/boot/grub"
    #BootIMGOptions="${BootIMGOptions:+${BootIMGOptions} }--compression auto"

    # TODO: move modules config to settings.conf
    local BootGrubModules="ext2 part_gpt"

    local DestImages="BOOT/BOOTX64.EFI ${BootloaderID}/grubx64.efi"
    for IMG in ${DestImages}; do
        local IMGPath="/boot/efi/EFI/${IMG}"
        BootIMGOptions="${BootIMGOptions:+${BootIMGOptions} }--output ${IMGPath}"

        mkdir -p $(dirname ${RootDir}${IMGPath}) || return 1
        printf "BOOTLOADER: Generate Bootloader images ${C_YEL}$(basename ${RootDir})${IMGPath}${C_CLR} ..."
        if ! chroot ${RootDir} grub-mkimage ${BootIMGOptions} ${BootGrubModules} >>${BootloaderLogfile} 2>&1; then
            printf " [${C_FL}]\n" && return 1
        else
            printf " [${C_OK}]\n"
        fi
    done

    [ -f ${BootloaderLogfile} ] && rm -f ${BootloaderLogfile}
    return 0
}

# Usage: MakeSquashfs <Squashfs File> <RootDir>
MakeSquashfs() {
    if [ $# -ne 2 ]; then
        echo -e "Usage: MakeSquashfs <Squashfs File> <RootDir>"
        return 1
    fi

    local Squashfs=$1
    local RootDir=$2

    if [ ! -d "${RootDir}" ]; then
        echo "Cannot find Rootfs dir."
        return 1
    fi

    [ -f "${Squashfs}" ] || rm -f "${Squashfs}"

    printf "MKSQUASH: ${C_HL}${RootDir##*${WorkDir}/}${C_CLR} --> ${C_BLU}${Squashfs##*${WorkDir}/}${C_CLR} ..."
    if ! mksquashfs "${RootDir}" "${Squashfs}" -comp xz -processors 4 >>/dev/null 2>&1; then
        printf " [${C_FL}]\n"
        return 1
    else
        printf " [${C_OK}]\n"
        return 0
    fi
}

# Usage: CompressVirtualDisk <VirtualDisk>
CompressVirtualDisk() {
    [ $# -eq 1 ] || (echo -e "Usage: CompressVirtualDisk <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    local ZipFile=${VirtualDisk}.zip
    [ -f ${VirtualDisk} ] || return 1
    [ -f ${ZipFile} ] && rm -f ${ZipFile}

    local ZipOptions=""
    ZipOptions="${ZipOptions:+${ZipOptions} }-q"

    printf "COMPRESS: Compressing the image ${C_YEL}$(basename ${VirtualDisk})${C_CLR} --> ${C_YEL}$(basename ${ZipFile})${C_CLR}"
    if ! zip ${ZipOptions} ${ZipFile} ${VirtualDisk}; then
        printf " [${C_FL}]\n" && return 1
    else
        printf " [${C_OK}]\n"
    fi

    return 0
}

ShowSettings() {
    echo -e "VDisk = ${VDisk}"
    echo -e "RootDir = ${RootDir}"
    echo -e "CacheDir = ${CacheDir}"
    echo -e "ProfilesDir = ${ProfilesDir}"
    echo -e "RootfsBasePackage = ${RootfsBasePackage}"
    echo -e "PreReplaceFiles = ${PreReplaceFiles}"
    echo -e "PostReplaceFiles = ${PostReplaceFiles}"
    echo -e "AptUrl = ${AptUrl}"
    echo -e "Encoding = ${Encoding}"
    echo -e "Language = ${Language}"
    echo -e "Locales = ${Locales}"
    echo -e "BootloaderID = ${BootloaderID}"
    echo -e "AccountUsername = ${AccountUsername}"
    echo -e "AccountPassword = ${AccountPassword}"
}

# Usage: LoadSettings <ConfigFile>
LoadSettings() {
    [ $# -eq 1 ] || (echo -e "Usage: LoadSettings <ConfigFile>" && return 1)
    local ConfigFile=$1

    SquashfsFile=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings SquashfsFile)
    VDisk=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings VDisk)
    RootDir=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings RootDir)
    CacheDir=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings CacheDir)
    ProfilesDir=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings ProfilesDir)
    ExtPackageDir=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings ExtPackageDir)
    RootfsBasePackage=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings RootfsBasePackage)

    PreReplaceFiles=$(ConfGetValues ${ConfigFile} PreReplaces)
    PostReplaceFiles=$(ConfGetValues ${ConfigFile} PostReplaces)

    Packages=$(GetConfPackages ${ConfigFile} Packages)
    PackagesExtra=$(GetConfPackages ${ConfigFile} PackagesExtra)
    PackagesUnInstall=$(GetConfPackages ${ConfigFile} PackagesUnInstall)

    TimeZone=$(ConfGetValue ${ConfigFile} Settings TimeZone)
    AptUrl=$(ConfGetValue ${ConfigFile} Settings AptUrl)
    Encoding=$(ConfGetValue ${ConfigFile} Settings Encoding)
    Language=$(ConfGetValue ${ConfigFile} Settings Language)
    Locales=$(ConfGetValue ${ConfigFile} Settings Locales)
    BootloaderID=$(ConfGetValue ${ConfigFile} Settings BootloaderID)
    AccountUsername=$(ConfGetValue ${ConfigFile} Settings AccountUsername)
    AccountPassword=$(ConfGetValue ${ConfigFile} Settings AccountPassword)
}

doInstallPackages() {
    InstallPackages ${RootDir} Update || InstallPackages ${RootDir} FixBroken || return $?
    InstallPackages ${RootDir} Upgrade || InstallPackages ${RootDir} FixBroken || return $?
    InstallPackages ${RootDir} Install ${Packages} || InstallPackages ${RootDir} FixBroken || return $?

    return 0
}

doInstallExtraPackages() {
    InstallExtrenPackages ${RootDir} ${PackagesExtra} || return $?
    return 0
}

doRemovePackages() {
    UnInstallPackages "${RootDir}" Purge ${PackagesUnInstall} || return $?

    return 0
}

Usage() {
    local USAGE=''
    USAGE="${USAGE:+${USAGE}\n}$(basename ${Script}) <Command> <Command> ... (Command Sequence)"
    USAGE="${USAGE:+${USAGE}\n}Commands:"
    USAGE="${USAGE:+${USAGE}\n}  -a|a|auto        : Auto process all by step [-a] = [-c -i -m -U -M -p -I -E -R -P -u]."
    USAGE="${USAGE:+${USAGE}\n}  -c|c|create      : Create a virtual disk file."
    USAGE="${USAGE:+${USAGE}\n}  -i|i|init        : Initialize the virtual disk file, if file does not exist, create it."
    USAGE="${USAGE:+${USAGE}\n}  -m|m|mount-disk  : Mount virtual disk only to \"$(basename ${RootDir})\"."
    USAGE="${USAGE:+${USAGE}\n}  -M|M|mount-all   : Mount virtual disk, cache dirs and system dirs to \"$(basename ${RootDir})\"."
    USAGE="${USAGE:+${USAGE}\n}  -u|u|umount      : Unmount virtual disk from \"$(basename ${RootDir})\"."
    USAGE="${USAGE:+${USAGE}\n}  -U|U|unpack      : Unpack the base filesystem(default is \"$(basename ${RootfsBasePackage})\") to \"$(basename ${RootDir})\"."
    USAGE="${USAGE:+${USAGE}\n}  -p|p|pre-setup   : Pre-Setup settings, include replace files, gen-locales, ie...."
    USAGE="${USAGE:+${USAGE}\n}  -P|P|post-setup  : Post-Setup settings, include setup bootloader, user password, ie...."
    USAGE="${USAGE:+${USAGE}\n}  -I|I|install     : Install packages."
    USAGE="${USAGE:+${USAGE}\n}  -E|E|instext     : Install extra packages."
    USAGE="${USAGE:+${USAGE}\n}  -R|R|remove      : Remove exist packages."
    USAGE="${USAGE:+${USAGE}\n}  -s|s|make-squash : Compress rootfs to squash file: \"$(basename ${SquashfsFile}))\"."
    USAGE="${USAGE:+${USAGE}\n}  -z|z|zip         : Compress image to a zip file \"${VDisk}.zip\"."
    USAGE="${USAGE:+${USAGE}\n}  -s|show-settings : Show current settings."
    echo -e ${USAGE}
}

doMain() {
    LoadSettings ${ConfigFile} || exit $?
    CheckPrivilege || exit $?
    CheckBuildEnvironment || exit $?

    while [ $# -ne 0 ]
    do
        case $1 in
            -c|c|create)
                shift
                CreateVirtualDisk ${VDisk} || exit $?
                CreatePartitions ${VDisk} || exit $?
                ;;
            -i|i|init)
                shift
                InitializeVirtualDisk ${VDisk} ${RootDir} || exit $?
                ;;
            -m|m|mount-disk)
                shift
                MountVDisk ${VDisk} ${RootDir} || exit $?
                ;;
            -M|M|mount-all)
                shift
                MountAll ${VDisk} ${RootDir} ${CacheDir} || exit $?
                ;;
            -u|u|umount|uload)
                shift
                UnLoadVirtualDisk ${VDisk} || exit $?
                ;;
            -U|U|unpack)
                shift
                UnPackRootFS ${RootfsBasePackage} ${RootDir} || exit $?
                ;;
            -p|p|pre-setup)
                shift
                ReplaceFiles ${RootDir} ${ProfilesDir} ${PreReplaceFiles} || exit $?
                UpdateFSTAB ${VDisk} ${RootDir} || exit $?
                UpdateTimeZone ${RootDir} ${TimeZone} || exit $?
                UpdateSourcesList ${RootDir} ${AptUrl} || exit $?
                ;;
            -I|I|install)
                shift
                doInstallPackages || exit $?
                ;;
            -E|E|instext)
                shift
                doInstallExtraPackages || exit $?
                ;;
            -R|R|remove)
                shift
                doRemovePackages || exit $?
                ;;
            -P|P|post-setup)
                shift
                ReplaceFiles ${RootDir} ${ProfilesDir} ${PostReplaceFiles} || exit $?
                SetUserPassword ${RootDir} ${AccountUsername} ${AccountPassword} || exit $?
                SetupBootloader ${VDisk} ${RootDir} ${BootloaderID} || exit $?
                ;;
            -a|a|auto)
                shift
                InitializeVirtualDisk ${VDisk} ${RootDir} || exit $?
                MountVDisk ${VDisk} ${RootDir} || exit $?
                UnPackRootFS ${RootfsBasePackage} ${RootDir} || exit $?
                MountAll ${VDisk} ${RootDir} ${CacheDir} || exit $?
                ReplaceFiles ${RootDir} ${ProfilesDir} ${PreReplaceFiles} || exit $?
                UpdateFSTAB ${VDisk} ${RootDir} || exit $?
                UpdateTimeZone ${RootDir} ${TimeZone} || exit $?
                UpdateSourcesList ${RootDir} ${AptUrl} || exit $?
                doInstallPackages || exit $?
                doInstallExtraPackages || exit $?
                doRemovePackages || exit $?
                ReplaceFiles ${RootDir} ${ProfilesDir} ${PostReplaceFiles} || exit $?
                SetUserPassword ${RootDir} ${AccountUsername} ${AccountPassword} || exit $?
                SetupBootloader ${VDisk} ${RootDir} ${BootloaderID} || exit $?
                UnLoadVirtualDisk ${VDisk} || exit $?
                ;;
            -s|s|make-squash)
                shift
                MakeSquashfs ${SquashfsFile} ${RootDir} || exit $?
                ;;
            -z|z|zip)
                shift
                CompressVirtualDisk ${VDisk} || exit $?
                ;;
            -s|show-settings)
                shift
                ShowSettings
                ;;
            -h|--help|h|help)
                Usage
                exit 0
                ;;
            *)
                Usage
                exit 1
                ;;
        esac
    done
}

if [ $# -lt 1 ]; then
    doMain --help
else
    doMain $@
fi
