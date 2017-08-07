#!/bin/bash

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

CheckBuildEnvironment()
{
    Utils="blkid lsblk kpartx parted mkfs.ext4 mkfs.fat"
    echo "Checking Build Environment..."

    for Util in ${Utils}
    do
        printf " ${C_YEL}${Util}${C_CLR} is "
        if ! which ${Util} >/dev/null 2>&1; then
            printf "[${C_FL}]\n"
            echo "Please install ${Unit} first"
            return 1
        else
            printf "[${C_OK}]\n"
        fi
    done

    return 0
}

# USAGE: ConfGetSections <ConfFile>
ConfGetSections()
{
    [ $# -eq 1 ] || (echo -e "Usage: ConfGetSections <ConfFile>" && return 1)

    local ConfFile=$1
    sed -n "/\[*\]/{s/\[//;s/\]///^;.*$/d;/^#.*$/d;p}" ${ConfFile}
}

# USAGE: ConfGetKeys <ConfFile> <Section>
ConfGetKeys()
{
    [ $# -eq 2 ] || (echo -e "Usage: ConfGetKeys <ConfFile> <Section>" && return 1)

    local ConfFile=$1
    local Section=$2

    sed -n "/\[${Section}\]/,/\[.*\]/{/^\[.*\]/d;/^[ ]*$/d;/^;.*$/d;/^#.*$/d;p}" ${ConfFile} | awk -F '=' '{print $1}'
}

# USAGE: ConfGetValues <ConfFile> <Section>
ConfGetValues()
{
    [ $# -eq 2 ] || (echo -e "Usage: ConfGetValues <ConfFile> <Section>" && return 1)

    local ConfFile=$1
    local Section=$2

    sed -n "/\[${Section}\]/,/\[.*\]/{/^\[.*\]/d;/^[ ]*$/d;/^;.*$/d;/^#.*$/d;p}" ${ConfFile} | awk -F '=' '{print $2}'
}

# USAGE: ConfGetValue <ConfFile> <Section> <Key>
ConfGetValue()
{
    [ $# -eq 3 ] || (echo -e "Usage: ConfGetValue <ConfFile> <Section> <Key>" && return 1)

    local ConfFile=$1
    local Section=$2
    local Key=$3

    sed -n "/\[${Section}\]/,/\[.*\]/{/^\[.*\]/d;/^[ ]*$/d;s/;.*$//;s/^[| ]*${Key}[| ]*=[| ]*\(.*\)[| ]*/\1/p}" ${ConfFile}
}

# USAGE: ConfSetValue <ConfFile> <Section> <Key> <Value>
ConfSetValue()
{
    [ $# -eq 4 ] || (echo -e "Usage: ConfGetValue <ConfFile> <Section> <Key>" && return 1)

    local ConfFile=$1
    local Section=$2
    local Key=$3
    local Value=$4

    sed -i "/^\[${Section}\]/,/^\[/ {/^\[${Section}\]/b;/^\[/b;s/^${Key}*=.*/${Key}=${Value}/g;}" ${ConfFile}
}

CheckPrivilege()
{
    if [ $UID -ne 0 ]; then
        echo -e  "Please run this script with \033[1m\033[31mroot\033[0m privileges."
        return 1
    else
        return 0
    fi
}

# Usage: GetPartitionInfo <Info> <Device>
GetPartitionInfo()
{
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
        *)
            ;;
    esac

    local PartInfo=$(blkid -s ${expr} -o value  ${Device})
    [ -n "${PartInfo}" ] || return 1

    echo ${PartInfo}
}

# Usage: IsVirtualDiskMapped <VirtualDisk>
IsVirtualDiskMapped()
{
    [ $# -eq 1 ] || (echo -e "Usage: IsVirtualDiskMapped <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -e ${VirtualDisk} ] || return 1

    if ! kpartx -l ${VirtualDisk} | /bin/grep -q "deleted"; then
        return 0
    else
        return 1
    fi
}

# Usage: GetVirtualDiskMappedDevice <VirtualDisk>
GetVirtualDiskMappedDevice()
{
    [ $# -eq 1 ] || (echo -e "Usage: GetVirtualDiskMappedDevice <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -e ${VirtualDisk} ] || return 1

    if IsVirtualDiskMapped ${VirtualDisk}; then
        kpartx -l ${VirtualDisk} | head -1 | awk '{print $5}'
        [ $? -eq 0 ] || return 1
    else
        return 1
    fi
}

# Usage: GetVirtualDiskMappedParts <VirtualDisk>
GetVirtualDiskMappedParts()
{
    [ $# -eq 1 ] || (echo -e "Usage: GetVirtualDiskMappedParts <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -f ${VirtualDisk} ] || return 1

    local Partitions=$(kpartx -l ${VirtualDisk} | /bin/grep "^loop[0-9]" | awk '{print $1}')
    [ -n "${Partitions}" ] || return 1

    local Parts=""
    for Part in ${Partitions}
    do
        Parts="${Parts:+${Parts} }/dev/mapper/${Part}"
    done
    [ -n "${Parts}" ] || return 1

    echo -e ${Parts}
}

# Usage: MapVirtualDisk <VirtualDisk>
MapVirtualDisk()
{
    [ $# -eq 1 ] || (echo -e "Usage: MapVirtualDisk <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -e ${VirtualDisk} ] || return 1

    if ! IsVirtualDiskMapped ${VirtualDisk}; then
        printf "MAPPING: ${C_HL}${VirtualDisk}${C_CLR}"
        if kpartx -as ${VirtualDisk}; then
            printf " [${C_OK}]\n"
        else
            printf " [${C_FL}]\n"
            return 1
        fi
    fi

    local LoopDevice=$(GetVirtualDiskMappedDevice ${VirtualDisk})
    if [ -n "${LoopDevice}" ]; then
        echo -e " ${C_HL}${VirtualDisk}${C_CLR} --> ${C_YEL}${LoopDevice}${C_CLR}"
        return 0
    fi
}

# Usage: CreateVirtualDisk <VirtualDisk>
CreateVirtualDisk()
{
    [ $# -eq 1 ] || (echo -e "Usage: CreateVirtualDisk <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -e ${VirtualDisk} ] && (echo -e "VirtualDisk file ${VirtualDisk} exists!" && return 1)

    dd if=/dev/zero of=${VirtualDisk} bs=4M count=0 seek=1024 status=none || return 1

    parted -s ${VirtualDisk} mklabel gpt                    || return 1
    parted -s ${VirtualDisk} mkpart ESP fat32 1M 100M       || return 1
    parted -s ${VirtualDisk} set 1 boot on                  || return 1
    parted -s ${VirtualDisk} mkpart ROOT ext4 100M 70%      || return 1
    parted -s ${VirtualDisk} mkpart USERDATA ext4 70% 100%  || return 1

    return 0
}

# Usage: FormatPartitions <VirtualDisk>
FormatPartitions()
{
    [ $# -eq 1 ] || (echo -e "Usage: FormatPartitions <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -e ${VirtualDisk} ] || return 1

    if ! IsVirtualDiskMapped ${VirtualDisk}; then
        echo -e "VirtualDisk[${C_HL}${VirtualDisk}${C_CLR}] does not mapped."
        return 1
    fi

    local Partitions=$(GetVirtualDiskMappedParts ${VirtualDisk})
    [ -n "${Partitions}" ] || return 1

    for Partition in ${Partitions}
    do
        local PartType=$(GetPartitionInfo Type ${Partition})
        if [ -n "${PartType}" ]; then
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
                    echo -e "FORMAT_ERROR: Unkown format type"
                    return 1
                    ;;
            esac
        else
            local PartLabel=$(GetPartitionInfo Label ${Partition})
            [ -n "${PartLabel}" ] || (echo -e "FORMAT_ERROR: Get Partition Information failed" && return 1)
            case ${PartLabel} in
                ESP)
                    fstype="vfat"
                    opts="-a"
                    ;;
                ROOT|USERDATA)
                    fstype="ext4"
                    opts="-q -F"
                    ;;
                *)
                    echo -e "FORMAT_ERROR: Unkown format type"
                    return 1
                    ;;
            esac
        fi
        printf "FORMAT: Partition[${C_YEL}${Partition}${C_CLR}] --> [${C_BLU}${fstype}${C_CLR}] ..."
        if ! mkfs.${fstype} ${opts} ${Partition} > /dev/null 2>&1; then
            printf " [${C_FL}]\n"
            return 1
        else
            printf " [${C_OK}]\n"
        fi
    done

    sync

    return 0
}

# Usage: IsTargetMounted <Device>
IsTargetMounted()
{
    [ $# -eq 1 ] || (echo -e "Usage: IsTargetMounted <Device>" && return 1)

    local Device=$1

    mount | /bin/grep -q ${Device}

    return $?
}

# Usage: GetTargetMountPoint <Device>
GetTargetMountPoint()
{
    [ $# -eq 1 ] || (echo -e "Usage: GetTargetMountPoint <Device>" && return 1)

    local Device=$1
    [ -e ${Device} ] || return 1

    IsTargetMounted ${Device} || return 1
    local MountedDir=$(lsblk -n -o MOUNTPOINT ${Device})
    [ -n "${MountedDir}" ] || return 1

    echo ${MountedDir}
}

# Usage: IsVirtualDiskMounted <VirtualDisk>
IsVirtualDiskMounted()
{
    [ $# -eq 1 ] || (echo -e "Usage: IsVirtualDiskMounted <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -e ${VirtualDisk} ] || return 1

    IsVirtualDiskMapped ${VirtualDisk} || return 1

    local loopdev=$(GetVirtualDiskMappedDevice ${VirtualDisk})
    [ -n "${loopdev}" ] || return 1

    if mount | /bin/grep -q "$(basename ${loopdev}p)"; then
        return 0
    fi
    return 1
}

# Usage: ShowVirtualDiskMountedInfo <VirtualDisk>
ShowVirtualDiskMountedInfo()
{
    [ $# -eq 1 ] || (echo -e "Usage: IsVirtualDiskMounted <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -e ${VirtualDisk} ] || return 1

    IsVirtualDiskMapped ${VirtualDisk} || return 0
    IsVirtualDiskMounted ${VirtualDisk} || return 0

    local loopdev=$(GetVirtualDiskMappedDevice ${VirtualDisk})
    [ -n "${loopdev}" ] || return 1

    echo -e "MAPPED: ${C_HL}${VirtualDisk}${C_CLR} ${C_YEL}${loopdev}${C_CLR}"
    mount | /bin/grep "$(basename ${loopdev}p)" | while read line
    do
        local mdev=$(echo ${line} | awk '{print $1}')
        local mdir=$(echo ${line} | awk '{print $3}')
        echo -e "MOUNTED: ${C_YEL}${mdev}${C_CLR} --> ${C_BLU}${mdir}${C_CLR}"
    done
}

# Usage: GetVirtualDiskMountedParts <VirtualDisk>
GetVirtualDiskMountedParts()
{
    [ $# -eq 1 ] || (echo -e "Usage: GetVirtualDiskMountedParts <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -e ${VirtualDisk} ] || return 1

    local loopdev=$(GetVirtualDiskMappedDevice ${VirtualDisk})
    [ -n "${loopdev}" ] || return 1

    local MountedParts=$(mount | /bin/grep "$(basename ${loopdev}p)" | awk '{print $1}')
    [ -n "${MountedParts}" ] || return 1

    echo ${MountedParts}
}

# Usage: GetVirtualDiskMountedRoot <VirtualDisk>
GetVirtualDiskMountedRoot()
{
    [ $# -eq 1 ] || (echo -e "Usage: GetVirtualDiskMountedRoot <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -e ${VirtualDisk} ] || return 1

    IsVirtualDiskMounted ${VirtualDisk} || return 1

    local Partitions=$(GetVirtualDiskMappedParts ${VirtualDisk})
    [ -n "${Partitions}" ] || return 1

    for Partition in ${Partitions}
    do
        local PartLabel=$(GetPartitionInfo Label ${Partition})
        [ -n "${PartLabel}" ] || return 1
        if [ x"${PartLabel}" == x"ROOT" ]; then
            IsTargetMounted ${Partition} || return 1
            local MountDir=$(mount | /bin/grep ${Partition} | awk '{print $3}')
            [ -n "${MountDir}" ] || return 1
            echo -e ${MountDir}
            return 0
        fi
    done
}

# Usage: Mount [-c <RootDir>] [-t <Type> | -b] <Source> <DstDir>
Mount()
{
    local Usage="Usage: Mount [-c <RootDir>] [-t <Type> | -b] <Source> <DstDir>"
    local Prefix=""
    local Options=""
    local RootDir=""

    while [ $# -ne 0 ]
    do
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

    printf "MOUNT: ${C_GEN}${Options:+[${Options}] }${C_YEL}${Source}${C_CLR} --> ${C_BLU}${RootDir}${DstDir}${C_CLR}"
    if ! eval ${Prefix} mount ${Options} ${Source} ${DstDir} >/dev/null 2>&1; then
        printf " [${C_FL}]\n"
        return 1
    fi
    printf " [${C_OK}]\n"

    return 0
}

# Usage: UnMount [-c <RootDir>] <Directory>
UnMount()
{
    local Usage="Usage: UnMount [-c <RootDir>] <Directory>"
    local Prefix=""
    local RootDir=""
    local Directory=""

    while [ $# -ne 0 ]
    do
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
            printf "UMOUNT: [${C_GEN}Recursive${C_CLR}] ${C_YEL}${Directory}${C_CLR}"
            if ! eval ${Prefix} umount -R ${Directory} >/dev/null 2>&1; then
                if ! eval ${Prefix} umount -Rl ${Directory} >/dev/null 2>&1; then
                    printf " [${C_FL}]\n"
                    return 1
                fi
            fi
            printf " [${C_OK}]\n"
        fi
    else
        dirlist=$(eval ${Prefix} mount | grep "${Directory}")
        [ -n "${dirlist}" ] && return 0
        for dir in ${dirlist}
        do
            if eval ${Prefix} mountpoint -q ${dir}; then
                printf "UNMOUNT: ${C_YEL}${dir}${C_CLR}"
                if ! eval ${Prefix} umount ${dir}; then
                    if ! eval ${Prefix} umount -l ${dir}; then
                        printf " [${C_FL}]\n"
                        return 1
                    fi
                fi
                printf " [${C_OK}]\n"
            fi
        done
    fi

    return 0
}

# Usage: MountCache <RootDir> <CacheDir>
MountCache()
{
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
UnMountCache()
{
    [ $# -eq 1 ] || (echo -e "Usage: UnMountCache <RootDir>" && return 1)

    local RootDir=$1
    local RootAptCache=${RootDir}/var/cache/apt
    local RootAptLists=${RootDir}/var/lib/apt/lists
    [ -n "${RootDir}" ] || return 1

    for dir in ${RootAptCache} ${RootAptLists}
    do
        UnMount ${dir} || return 1
    done

    return 0
}

# Usage: MountSystemEntries <RootDir>
MountSystemEntries()
{
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
UnMountSystemEntries()
{
    [ $# -eq 1 ] || (echo -e "Usage: MountSystemEntries <RootDir>" && return 1)

    local RootDir=$1
    local Prefix=""
    [ -n "${RootDir}" ] || return 1

    [ -x ${RootDir}/bin/mountpoint ] && Prefix="chroot ${RootDir}"

    for dir in tmp run dev/pts dev sys proc
    do
        if eval ${Prefix} mountpoint -q ${RootDir}/proc; then
            UnMount --chroot ${RootDir} ${dir} || return 1
        else
            UnMount ${RootDir}/${dir} || return 1
        fi
    done

    return 0
}

# Usage: MountUserEntries <RootDir>
MountUserEntries()
{
    [ $# -eq 1 ] || (echo -e "Usage: MountUserEntries <RootDir>" && return 1)

    local RootDir=$1
    local UserDir=${RootDir}/userdata
    [ -n "${RootDir}" ] || return 1

    for dir in home root var/log
    do
        mkdir -p ${RootDir}/${dir} ${UserDir}/${dir} || return 1
        Mount --bind ${UserDir}/${dir} ${RootDir}/${dir} || return 1
    done

    return 0
}

# Usage: UnMountUserEntries <RootDir>
UnMountUserEntries()
{
    [ $# -eq 1 ] || (echo -e "Usage: UnMountUserEntries <RootDir>" && return 1)

    local RootDir=$1
    [ -n "${RootDir}" ] || return 1

    for dir in home root var/log
    do
        UnMount ${RootDir}/${dir} || return 1
    done

    return 0
}

# Usage: MountVirtualDisk <VirtualDisk> <RootDir> <CacheDir>
MountVirtualDisk()
{
    [ $# -eq 3 ] || (echo -e "Usage: MountVirtualDisk <VirtualDisk> <RootDir> <CacheDir>" && return 1)

    local VirtualDisk=$1
    local RootDir=$2
    local CacheDir=$3
    local UefiDir=${RootDir}/boot/efi
    local UserDir=${RootDir}/userdata

    # Check and map virtual disk
    if ! IsVirtualDiskMapped ${VirtualDisk}; then
        MapVirtualDisk ${VirtualDisk} || return 1
    fi

    # Mount partition by partition label
    local Partitions=$(GetVirtualDiskMappedParts ${VirtualDisk})
    [ -n "${Partitions}" ] || return 1
    local LastParts=

    # Find ROOT partition and mount it first
    for dev in ${Partitions}
    do
        local PartLabel=$(GetPartitionInfo Label $(realpath -L ${dev}))
        [ -n "${PartLabel}" ] || return 1
        if [ x"${PartLabel}" == x"ROOT" ]; then
            mkdir -p ${RootDir} || return 1
            #Mount $(realpath -L ${dev}) ${RootDir} || return 1
            Mount ${dev} ${RootDir} || return 1
        else
            LastParts=${LastParts:+${LastParts} }${dev}
        fi
    done

    for dev in ${LastParts}
    do
        local PartLabel=$(GetPartitionInfo Label $(realpath -L ${dev}))
        [ -n "${PartLabel}" ] || return 1
        case ${PartLabel} in
            ESP)
                mkdir -p ${UefiDir} || return 1
                Mount ${dev} ${UefiDir} || return 1
            ;;
            USERDATA)
                mkdir -p ${UserDir} || return 1
                Mount ${dev} ${UserDir} || return 1
            ;;
            *)
            ;;
        esac
    done

    MountCache ${RootDir} ${CacheDir} || return ?
    MountSystemEntries ${RootDir} || return $?
    MountUserEntries ${RootDir} || return $?

    return 0
}

# Usage: UnMountVirtualDisk <VirtualDisk> <RootDir>
UnMountVirtualDisk()
{
    [ $# -eq 2 ] || (echo -e "Usage: UnMountVirtualDisk <VirtualDisk> <RootDir>" && return 1)

    local VirtualDisk=$1
    local RootDir=$2

    if IsVirtualDiskMounted ${VirtualDisk}; then
        local VirtualDiskRoot=$(GetVirtualDiskMountedRoot ${VirtualDisk})
        if [ -n "${VirtualDiskRoot}" ]; then
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

# Usage: UnMapVirtualDisk <VirtualDisk>
UnMapVirtualDisk()
{
    [ $# -eq 1 ] || (echo -e "Usage: UnMapVirtualDisk <VirtualDisk>" && return 1)

    local VirtualDisk=$1
    [ -e ${VirtualDisk} ] || return 1

    if IsVirtualDiskMounted ${VDisk}; then
        ShowVirtualDiskMountedInfo ${VDisk} || return 1
        MountedDir=$(GetVirtualDiskMountedRoot ${VDisk})
        [ -n "${MountedDir}" ] || return 1
        UnMountVirtualDisk ${VDisk} ${MountedDir} || return 1
    fi

    if IsVirtualDiskMapped ${VirtualDisk}; then
        local LoopDevice=$(GetVirtualDiskMappedDevice ${VirtualDisk})
        if [ -n "${LoopDevice}" ]; then
            printf "UMAPPING: ${C_HL}${VirtualDisk}${C_CLR} <--> ${C_YEL}${LoopDevice}${C_CLR} ..."
            if kpartx -d ${VirtualDisk} >/dev/null 2>&1; then
                printf " [${C_OK}]\n"
                return 0
            else
                printf " [${C_FL}]\n"
                return 1
            fi
        fi
    fi
    echo -e "VirtualDisk ${C_HL}${VirtualDisk}${C_CLR} not mapped"

    return 0
}

# Usage: InitializeVirtualDisk <VirtualDisk> <RootDir>
InitializeVirtualDisk()
{
    [ $# -eq 2 ] || (echo -e "Usage: InitializeVirtualDisk <VirtualDisk> <RootDir>" && return 1)

    local VirtualDisk=$1
    local RootDir=$2

    # Check VirtualDisk exist
    if [ ! -e ${VirtualDisk} ]; then
        echo -e "Cannot find VirtualDisk file ${C_HL}${VirtualDisk}${C_CLR}, create it."
        CreateVirtualDisk ${VirtualDisk} || return 1
    fi

    # Unmount VirtualDisk
    UnMountVirtualDisk ${VirtualDisk} ${RootDir} || return 1

    # Map VirtualDisk
    if ! IsVirtualDiskMapped ${VirtualDisk}; then
        MapVirtualDisk ${VirtualDisk} || return 1
    fi

    # Format VirtualDisk partitions
    FormatPartitions ${VirtualDisk} || return 1

    return 0
}

# Usage: UnPackRootFS <Package> <RootDir>
UnPackRootFS()
{
    [ $# -eq 2 ] || (echo -e "Usage: UnPackRootFS <Package> <RootDir>" && return 1)

    local Package=$1
    local RootDir=$2

    printf "UNPACK: ${C_HL}${Package}${C_CLR} --> ${C_BLU}${RootDir}${C_CLR} ..."
    if ! tar --exclude=dev/* -xf ${Package} -C ${RootDir} >>/dev/null 2>&1; then
        printf " [${C_FL}]\n"
        return 1
    else
        printf " [${C_OK}]\n"
        return 0
    fi
}

# Usage: GetConfPackages <ConfigFile>
GetConfPackages()
{
    [ $# -eq 1 ] || (echo -e "Usage: GetConfPackages <ConfigFile>" && return 1)
    local ConfigFile=$1
    local Packages=""

    [ -n "${ConfigFile}" ] || return 1
    [ -f "${ConfigFile}" ] || return 1

    local PackagesList=$(ConfGetKeys ${ConfigFile} Packages)
    [ -n "${PackagesList}" ] || return 1

    for Package in ${PackagesList}
    do
        local Enabled=$(ConfGetValue ${ConfigFile} Packages ${Package})
        if [ -n "${Enabled}" ]; then
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

# Usage: InstallPackages <RootDir> <Option> <Packages...>
InstallPackages()
{
    [ $# -ge 2 ] || (echo -e "Usage: InstallPackages <RootDir> <Option> <Packages...>" && return 1)
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
    #AptOptions="${AptOptions:+${AptOptions} }--force-yes"
    #AptOptions="${AptOptions:+${AptOptions} }--no-install-recommends"

    case ${Options} in
        -u|--update|Update|UPDATE)
            printf "PKGINSTALL: ${C_YEL}Updating${C_CLR} Packages List ..."
            if ! chroot ${RootDir} apt-get ${AptOptions} update >>${InsLogFile} 2>&1; then
                printf " [${C_FL}]\n"
                return 1
            fi
            printf " [${C_OK}]\n"
        ;;
        -U|--upgrade|Upgrade|UPGRADE)
            printf "PKGINSTALL: ${C_YEL}Upgrading${C_CLR} Packages ..."
            if ! chroot ${RootDir} apt-get ${AptOptions} upgrade >>${InsLogFile} 2>&1; then
                printf " [${C_FL}]\n"
                return 1
            fi
            printf " [${C_OK}]\n"
        ;;
        -i|--install|Install|INSTALL)
            for Package in ${Packages}
            do
                printf "PKGINSTALL: ${C_YEL}Installing${C_CLR} ${C_HL}${Package}${C_CLR} ..."
                if ! chroot ${RootDir} apt-get ${AptOptions} install ${Package} >>${InsLogFile} 2>&1; then
                    printf " [${C_FL}]\n"
                    return 1
                fi
                printf " [${C_OK}]\n"
            done
        ;;
        *)
            echo -e "PKGINSTALL: Error: Unknown Options"
            return 1
        ;;
    esac

    rm -f ${InsLogFile}
    return 0
}

# Usage: ReplaceFiles <RootDir> <ProfilesDir> <Files...>
ReplaceFiles()
{
    [ $# -gt 2 ] || (echo -e "Usage: ReplaceFiles <RootDir> <ProfilesDir> <Files...>" && return 1)

    local RootDir=$1
    local ProfilesDir=$2
    shift 2
    local FileList=$@
    local BackupDir=${ProfilesDir}/backup
    local ModifiedDir=${ProfilesDir}/modified

    for File in ${FileList}
    do
        # Backup File
        if [ -f ${RootDir}/${File} ]; then
            cp -a ${RootDir}/${File} ${BackupDir} >/dev/null 2>&1
        fi
        # Copy File
        printf "REPLACE: ${C_HL}${File}${C_CLR} ..."
        if [ -f ${ModifiedDir}/$(basename ${File}) ]; then
            if ! cp -a ${ModifiedDir}/$(basename ${File}) ${RootDir}/${File} >/dev/null 2>&1; then
                printf " [${C_FL}]\n"
            fi
        fi
        printf " [${C_OK}]\n"
    done
}

# Usage: GenerateFSTAB <VirtualDisk> <RootDir>
GenerateFSTAB()
{
    [ $# -eq 2 ] || (echo -e "Usage: GenerateFSTAB <VirtualDisk> <RootDir>" && return 1)

    local VirtualDisk=$1
    local RootDir=$2

    [ -f ${VirtualDisk} ] || return 1

    # Check and map virtual disk
    if ! IsVirtualDiskMapped ${VirtualDisk}; then
        MapVirtualDisk ${VirtualDisk} || return 1
    fi

    local Partitions=$(GetVirtualDiskMappedParts ${VirtualDisk})
    [ -n "${Partitions}" ] || return 1

    local UefiUUID=
    local RootUUID=
    local UserUUID=

    for dev in ${Partitions}
    do
        local PartLabel=$(GetPartitionInfo Label $(realpath -L ${dev}))
        [ -n "${PartLabel}" ] || return 1
        case ${PartLabel} in
            ESP)
                UefiUUID=$(GetPartitionInfo UUID $(realpath -L ${dev}))
                [ -n "${UefiUUID}" ] || return 1
            ;;
            ROOT)
                RootUUID=$(GetPartitionInfo UUID $(realpath -L ${dev}))
                [ -n "${RootUUID}" ] || return 1
            ;;
            USERDATA)
                UserUUID=$(GetPartitionInfo UUID $(realpath -L ${dev}))
                [ -n "${UserUUID}" ] || return 1
            ;;
            *)
            ;;
        esac
    done

    printf "GENFSTAB: Generating ${C_HL}${RootDir}/etc/fstab${C_CLR} ..."
    mkdir -p ${RootDir}/etc
    cat > ${RootDir}/etc/fstab <<EOF
# System Entry
UUID=${RootUUID} /         ext4 errors=remount-ro 0 1
UUID=${UefiUUID} /boot/efi vfat umask=0077        0 1
UUID=${UserUUID} /userdata ext4 defaults          0 2

# User Data Entry
/userdata/home        /home     none rw,bind           0 0
/userdata/root        /root     none rw,bind           0 0
/userdata/var/log     /var/log  none rw,bind           0 0
EOF
    if [ $? -ne 0 ]; then
        printf " [${C_FL}]\n"
        return 1
    fi
    printf " [${C_OK}]\n"

    echo -e "  ${C_YEL}ESP${C_CLR}      UUID = ${C_BLU}${UefiUUID}${C_CLR}"
    echo -e "  ${C_YEL}ROOT${C_CLR}     UUID = ${C_BLU}${RootUUID}${C_CLR}"
    echo -e "  ${C_YEL}USERDATA${C_CLR} UUID = ${C_BLU}${UserUUID}${C_CLR}"

    return 0
}

# Usage: GenerateLocales <RootDir> <Locales>
GenerateLocales()
{
    [ $# -gt 1 ] || (echo -e "Usage: GenerateLocales <RootDir> <Locales>" && return 1)

    local RootDir=$1
    shift
    local Locales=$@
    [ -n "${RootDir}" ] || return 1
    [ -d "${RootDir}" ] || return 1
    [ -n "${Locales}" ] || return 1

    IsTargetMounted ${RootDir} || (echo -e "${C_BLU}${RootDIr}${C_CLR} not mounted" && return 1)
    [ -x ${RootDir}/usr/sbin/locale-gen ] || (echo -e "Please unpack rootfs package first." && return 1)

    for locale in ${Locales}
    do
        printf "GENLOCALES: Generating ${C_HL}${locale}${C_CLR} ..."
        if ! chroot ${RootDir} locale-gen ${locale} >/dev/null 2>&1; then
            printf " [${C_FL}]\n"
        fi
        printf " [${C_OK}]\n"
    done

    return 0
}

# Usage: GenerateSourcesList <RootDir> <AptUrl>
GenerateSourcesList()
{
    local CODENAME=$(chroot ${RootDir} lsb_release -s -c)
}

# Usage: SetUserPassword <RootDir> <Username> <Password>
SetUserPassword()
{
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
            printf printf " [${C_FL}]\n"
            return 1
        fi
        printf " [${C_OK}]\n"
    fi

    local ChPwdScript="/tmp/ChangeUserPassword"

    printf "SETPASSWD: Change Password: [${C_HL}${Username}${C_CLR}]:[${C_GEN}${Password}${C_CLR}] ..."
    cat > ${RootDir}/${ChPwdScript} <<EOF
#!/bin/bash
echo ${Username}:${Password} | chpasswd
EOF
    if [ $? -ne 0 ]; then
        printf " [${C_FL}]\n"
        return 1
    fi

    if ! chroot ${RootDir} bash ${ChPwdScript}; then
        printf " [${C_FL}]\n"
    fi
    rm -f ${RootDir}/${ChPwdScript}
    printf " [${C_OK}]\n"

    return 0
}

# Usage: SetupBootloader <VirtualDisk> <RootDir> <BootloaderID>
SetupBootloader()
{
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

    IsVirtualDiskMapped ${VirtualDisk} || return 1
    IsTargetMounted ${RootDir} || return 1

    local Partitions=$(GetVirtualDiskMappedParts ${VirtualDisk})
    [ -n "${Partitions}" ] || return 1
    for Partition in ${Partitions}
    do
        local PartLabel=$(GetPartitionInfo Label $(realpath -L ${Partition}))
        if [ x"${PartLabel}" == x"ESP" ]; then
            IsTargetMounted ${Partition} || return 1
        fi
    done

    local BootDevice=$(GetVirtualDiskMappedDevice ${VirtualDisk})
    [ -n "${BootDevice}" ] || return 1

    # Setup grub default settings
    local GrubDefault=${RootDir}/etc/default/grub
    if [ -f ${GrubDefault} ]; then
        local Rst=0
        printf "BOOTLOADER: Update Bootloader Settings ..."
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT=""/' ${GrubDefault}
        Rst=$((${Rst} + $?))
        echo "GRUB_DISABLE_OS_PROBER=true" >> ${GrubDefault}
        Rst=$((${Rst} + $?))
        if [ ${Rst} -ne 0 ]; then
            printf " [${C_FL}]\n"
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
        printf " [${C_FL}]\n"
        return 1
    else
        printf " [${C_OK}]\n"
    fi

    printf "BOOTLOADER: Generate Bootloader Configuration ..."
    if ! chroot ${RootDir} update-grub >>${BootloaderLogfile} 2>&1; then
        printf " [${C_FL}]\n"
        return 1
    else
        printf " [${C_OK}]\n"
    fi

    # GENERATE GRUB EFI IMAGE AGAIN TO FIX GRUB CAN NOT FIND CONFIG
    local BootIMGOptions=""
    BootIMGOptions="${BootIMGOptions:+${BootIMGOptions} }--format ${BootloaderArch}"
    BootIMGOptions="${BootIMGOptions:+${BootIMGOptions} }--directory /usr/lib/grub/${BootloaderArch}"
    BootIMGOptions="${BootIMGOptions:+${BootIMGOptions} }--prefix (hd0,gpt2)/boot/grub"
    BootIMGOptions="${BootIMGOptions:+${BootIMGOptions} }--compression auto"

    # TODO: move modules config to settings.conf
    local BootGrubModules="ext2 part_gpt"

    local DestImages="BOOT/BOOTX64.EFI ${BootloaderID}/grubx64.efi"
    for IMG in ${DestImages}
    do
        local IMGPath="/boot/efi/EFI/${IMG}"
        BootIMGOptions="${BootIMGOptions:+${BootIMGOptions} }--output ${IMGPath}"

        mkdir -p $(dirname ${RootDir}${IMGPath})
        printf "BOOTLOADER: Generate Bootloader images ${C_YEL}${RootDir}${IMGPath}${C_CLR} ..."
        if ! chroot ${RootDir} grub-mkimage ${BootIMGOptions} ${BootGrubModules} >>${BootloaderLogfile} 2>&1; then
            printf " [${C_FL}]\n"
            return 1
        else
            printf " [${C_OK}]\n"
        fi
    done

    [ -f ${BootloaderLogfile} ] && rm -f ${BootloaderLogfile}
    return 0
}

WorkDir=$(pwd)
ConfigFile=${WorkDir}/settings.conf
[ -f ${ConfigFile} ] || (echo "Error: Cannot find 'settings.conf' in the current folder." && return 1)

VDisk=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings VDisk)
RootDir=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings RootDir)
CacheDir=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings CacheDir)
ProfilesDir=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings ProfilesDir)
RootfsPackage=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings RootfsPackage)
Packages=$(GetConfPackages ${ConfigFile})
ReplaceFiles=$(ConfGetValues ${ConfigFile} Replaces)

AptUrl=$(ConfGetValue ${ConfigFile} Settings AptUrl)
Encoding=$(ConfGetValue ${ConfigFile} Settings Encoding)
Language=$(ConfGetValue ${ConfigFile} Settings Language)
Locales=$(ConfGetValue ${ConfigFile} Settings Locales)
BootloaderID=$(ConfGetValue ${ConfigFile} Settings BootloaderID)
AccountUsername=$(ConfGetValue ${ConfigFile} Settings AccountUsername)
AccountPassword=$(ConfGetValue ${ConfigFile} Settings AccountPassword)

ShowSettings()
{
    echo -e "VDisk = ${VDisk}"
    echo -e "RootDir = ${RootDir}"
    echo -e "CacheDir = ${CacheDir}"
    echo -e "ProfilesDir = ${ProfilesDir}"
    echo -e "RootfsPackage = ${RootfsPackage}"
    echo -e "ReplaceFiles = ${ReplaceFiles}"
    echo -e "AptUrl = ${AptUrl}"
    echo -e "Encoding = ${Encoding}"
    echo -e "Language = ${Language}"
    echo -e "Locales = ${Locales}"
    echo -e "BootloaderID = ${BootloaderID}"
    echo -e "AccountUsername = ${AccountUsername}"
    echo -e "AccountPassword = ${AccountPassword}"
}

Usage()
{
    cat <<EOF
$(basename ${Script}) <Command> <Command> ... (Command Sequence)
Commands:
  -a|a|auto        : Auto process all by step.
  -c|c|create      : Create a virtual disk file.
  -i|i|init        : Initialize the virtual disk file, if file does not exist, create it.
  -m|m|mount       : Mount virtual disk to '$(basename ${RootDir})'.
  -u|u|umount      : Unmount virtual disk from '$(basename ${RootDir})'.
  -U|U|unpack      : Unpack the base filesystem(default is '$(basename ${RootfsPackage})') to '$(basename ${RootDir})'.
  -P|P|pre-process : Pre-Process unpacked filesystem, include replace files, gen-locales, ie....
  -I|I|install     : Install extra packages.
  -S|S|setup       : Setup settings, include setup bootloader, user password, ie....
EOF
}

CheckPrivilege || exit $?
CheckBuildEnvironment || exit $?

#ShowSettings

while [ $# -ne 0 ]
do
    case $1 in
        -c|c|create)
            shift
            CreateVirtualDisk ${VDisk} || exit $?
            ;;
        -i|i|init)
            shift
            InitializeVirtualDisk ${VDisk} ${RootDir} || exit $?
            ;;
        -m|m|mount)
            shift
            MountVirtualDisk ${VDisk} ${RootDir} ${CacheDir} || exit $?
            ;;
        -u|u|umount|umap)
            shift
            UnMapVirtualDisk ${VDisk} || exit $?
            ;;
        -U|U|unpack)
            shift
            UnPackRootFS ${RootfsPackage} ${RootDir} || exit $?
            ;;
        -P|P|pre-process)
            shift
            GenerateFSTAB ${VDisk} ${RootDir} || exit $?
            ReplaceFiles ${RootDir} ${ProfilesDir} ${ReplaceFiles} || exit $?
            GenerateLocales ${RootDir} ${Locales} || exit $?
            ;;
        -I|I|install)
            shift
            InstallPackages ${RootDir} Update || exit $?
            InstallPackages ${RootDir} Upgrade || exit $?
            InstallPackages ${RootDir} Install ${Packages} || exit $?
            ;;
        -S|S|setup)
            shift
            SetUserPassword ${RootDir} ${AccountUsername} ${AccountPassword} || exit $?
            SetupBootloader ${VDisk} ${RootDir} ${BootloaderID} || exit $?
            ;;
        -a|a|auto)
            InitializeVirtualDisk ${VDisk} ${RootDir} || exit $?
            MountVirtualDisk ${VDisk} ${RootDir} ${CacheDir}
            RST=$?
            if [ ${RST} -eq 99 ]; then
                UnPackRootFS ${RootfsPackage} ${RootDir} || exit $?
                MountVirtualDisk ${VDisk} ${RootDir} ${CacheDir} || exit $?
            elif [ ${RST} -ne 0 ]; then
                exit 1
            fi
            GenerateFSTAB ${VDisk} ${RootDir} || exit $?
            ReplaceFiles ${RootDir} ${ProfilesDir} ${ReplaceFiles} || exit $?
            GenerateLocales ${RootDir} ${Locales} || exit $?
            InstallPackages ${RootDir} Update || exit $?
            InstallPackages ${RootDir} Upgrade || exit $?
            InstallPackages ${RootDir} Install ${Packages} || exit $?
            SetUserPassword ${RootDir} ${AccountUsername} ${AccountPassword} || exit $?
            SetupBootloader ${VDisk} ${RootDir} ${BootloaderID} || exit $?
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
