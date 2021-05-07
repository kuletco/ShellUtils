#!/bin/bash

[ -n "${ScriptDir}" ] || ScriptDir=$(cd $(dirname ${BASH_SOURCE}); pwd)
[ -n "${FunctionsDir}" ] || FunctionsDir=${ScriptDir}/Functions
[ -n "${WorkDir}" ] || WorkDir=$(pwd)

if [ -f ${ScriptDir}/Color.sh ]; then
    source ${ScriptDir}/Color.sh
elif [ -f ${FunctionsDir}/Color.sh ]; then
    source ${FunctionsDir}/Color.sh
fi

if [ -f ${ScriptDir}/Mount.sh ]; then
    source ${ScriptDir}/Mount.sh
elif [ -f ${FunctionsDir}/Mount.sh ]; then
    source ${FunctionsDir}/Mount.sh
fi

# losetup need util-linux > v2.21

# Usage: IsVDiskAttached <VDisk>
IsVDiskAttached() {
    [ $# -eq 1 ] || (echo -e "Usage: IsVDiskAttached <VDisk>" && return 1)

    local VDisk=$1
    [ -e ${VDisk} ] || return 1

    if [ -n "$(losetup --associated ${VDisk})" ]; then
        return 0
    else
        return 1
    fi
}

# Usage: GetDeviceVDiskAttached <VDisk>
GetDeviceVDiskAttached() {
    [ $# -eq 1 ] || (echo -e "Usage: GetDeviceVDiskAttached <VDisk>" && return 1)

    local VDisk=$1
    [ -e ${VDisk} ] || return 1

    if [ -n "$(losetup --associated ${VDisk})" ]; then
        losetup --associated ${VDisk} | awk -F: '{print $1}'
    else
        return 1
    fi
}

# Usage: CreateVDisk <VDisk>
CreateVDisk() {
    [ $# -eq 1 ] || (echo -e "Usage: CreateVDisk <VDisk>" && return 1)

    local VDisk=$1
    [ -e ${VDisk} ] && (echo -e "VDisk file ${VDisk} exists!" && return 1)

    dd if=/dev/zero of=${VDisk} bs=4M count=0 seek=1024 status=none || return 1

    return 0
}

# Usage: CreateDiskParts <Disk>
CreateDiskParts() {
    [ $# -eq 1 ] || (echo -e "Usage: CreateDiskParts <Disk>" && return 1)

    local Disk=$1
    [ -e ${Disk} ] || (echo -e "Disk file ${Disk} not exists!" && return 1)

    IsVDiskAttached ${Disk} || (echo -e "Disk file ${Disk} attached!" && return 1)

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

# Usage: GetDiskParts <Disk>
GetDiskParts() {
    [ $# -eq 1 ] || (echo -e "Usage: GetDiskParts <Disk>" && return 1)

    local Disk=$1
    [ -e ${Disk} ] || return 1

    local Device=""
    local Parts=""

    # local DevType=$(lsblk ${Disk} -n -r -d | awk '{print $6}')
    # if [ $? -ne 0 ] || [ x"${DevType}" = x"loop" ]; then
    #     Device=$(GetDeviceVDiskAttached ${Disk})
    # else
    #     Device=${Disk}
    # fi
    if lsblk ${Disk} >/dev/null 2>&1; then
        Device=${Disk}
    else
        Device=$(GetVirtualDiskLoadedDevice ${Disk})
    fi

    Parts=$(lsblk ${Device} -p -r -n | awk '/part/{print $1}')
    [ -n "${Parts}" ] || return 1

    echo -e ${Parts}
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
    [ -n "${PartInfo}" ] || return 1

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

    local Parts=$(GetDiskParts ${Disk})
    [ -n "${Parts}" ] || return 1

    for Partition in ${Parts}; do
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

# Usage: FormatParts <VDisk>
FormatParts() {
    [ $# -eq 1 ] || (echo -e "Usage: FormatParts <VDisk>" && return 1)

    local VDisk=$1
    [ -e ${VDisk} ] || return 1

    if ! IsVDiskAttached ${VDisk}; then
        echo -e "VDisk[${C_HL}${VDisk}${C_CLR}] does not loaded."
        return 1
    fi

    local Parts=$(GetDiskParts ${VDisk})
    [ -n "${Parts}" ] || return 1

    for Partition in ${Parts}; do
        local PartType=$(GetDiskPartInfo Type ${Partition})
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
                    echo -e "FORMAT_ERROR: Unkown filesystem type: ${PartType}"
                    return 1
                    ;;
            esac
        else
            local PartLabel=$(GetDiskPartInfo Label ${Partition})
            # [ -n "${PartLabel}" ] || (echo -e "FORMAT_ERROR: Get Partition Information failed" && return 1)
            if [ -z "${PartLabel}" ]; then
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
        printf "Format: Partition[${C_YEL}${Partition}${C_CLR}] --> [${C_BLU}${fstype}${C_CLR}] ..."
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

# Usage: AttachVDisk <VDisk>
AttachVDisk() {
    [ $# -eq 1 ] || (echo -e "Usage: AttachVDisk <VDisk>" && return 1)

    local VDisk=$1
    [ -e ${VDisk} ] || return 1

    local Device=$(GetDeviceVDiskAttached ${VDisk})
    if [ -z "${Device}" ]; then
        printf "Attaching: ${C_HL}$(basename ${VDisk})${C_CLR}"
        Device=$(losetup --partscan --find --show ${VDisk})
        if [ $? -eq 0 ] && [ -n "${Device}" ] && [ -e "${Device}" ]; then
            printf " [${C_OK}]\n"
            echo -e " ${C_HL}$(basename ${VDisk})${C_CLR} --> ${C_YEL}${Device}${C_CLR}"
        else
            printf " [${C_FL}]\n"
        fi
    fi
}

# Usage: DetachVDisk <VDisk>
DetachVDisk() {
    [ $# -eq 1 ] || (echo -e "Usage: DetachVDisk <VDisk>" && return 1)

    local VDisk=$1
    [ -e ${VDisk} ] || return 1

    local Device=$(GetDeviceVDiskAttached ${VDisk})
    if [ -n "${Device}" ]; then
        printf "Detaching: ${C_HL}$(basename ${VDisk}) from ${Device} ${C_CLR}"
        losetup --detach ${Device}
        local RST=$?
        if [ ${RST} -eq 0 ]; then
            printf " [${C_OK}]\n"
        else
            printf " [${C_FL}]\n"
        fi
        return ${RST}
    fi
}

# Usage: MountVDisk <VDisk> <RootDir> <CacheDir>
MountVDisk() {
    [ $# -eq 3 ] || (echo -e "Usage: MountVDisk <VDisk> <RootDir> <CacheDir>" && return 1)

    local VDisk=$1
    local RootDir=$2
    local CacheDir=$3
    local StbInfoDir=${RootDir}/etc/stbinfo
    local UefiDir=${RootDir}/boot/efi
    local RecoveryDir=${RootDir}/boot/recovery
    local SysConfDir=${RootDir}/etc/sysconf
    local UserDataDir=${RootDir}/data

    # Check and attach virtual disk
    if ! IsVDiskAttached ${VDisk}; then
        AttachVDisk ${VDisk} || return 1
    fi

    # Get partitions list
    local Partitions=$(GetDiskParts ${VDisk})
    [ -n "${Partitions}" ] || return 1
    local LastParts=

    # Find ROOT partition and mount it first
    for dev in ${Partitions}; do
        local PartLabel=$(GetDiskPartInfo Label $(realpath -L ${dev}))
        [ -n "${PartLabel}" ] || return 1
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
        [ -n "${PartLabel}" ] || return 1
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

# Usage: UnMountVDisk <VDisk>
UnMountVDisk() {
    [ $# -eq 2 ] || (echo -e "Usage: UnMountVDisk <VDisk>" && return 1)

    local VDisk=$1
    local RootDir=$2

    local Device=$(GetDeviceVDiskAttached ${VDisk})
    if [ $? -eq 0 ] && [ -n "${Device}" ]; then
        if IsTargetMounted ${Device}; then
            local VDiskRoot=$(GetTargetMountPoint ${Device})
            if [ -n "${VDiskRoot}" ]; then
                UnMountUserEntries ${VDiskRoot} || return 1
                UnMountSystemEntries ${VDiskRoot} || return 1
                UnMountCache ${VDiskRoot} || return 1
                UnMount ${VDiskRoot} || return 1
            fi
        fi
    fi

    UnMountUserEntries ${RootDir} || return 1
    UnMountSystemEntries ${RootDir} || return 1
    UnMountCache ${RootDir} || return 1

    UnMount ${RootDir} || return 1

    return 0
}







# Usage: GetVDIskMountPoint <VDisk>
GetVDIskMountPoint() {
    [ $# -eq 1 ] || (echo -e "Usage: GetVDIskMountPoint <VDisk>" && return 1)

    local VDisk=$1
    [ -e ${VDisk} ] || return 1

    IsVDiskMounted ${VDisk} || return 1

    local Partitions=$(GetDiskParts ${VDisk})
    [ -n "${Partitions}" ] || return 1

    for Partition in ${Partitions}; do
        local PartLabel=$(GetDiskPartInfo Label ${Partition})
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

# Usage: ShowVirtualDiskMountedInfo <VDisk>
ShowVirtualDiskMountedInfo() {
    [ $# -eq 1 ] || (echo -e "Usage: IsVDiskMounted <VDisk>" && return 1)

    local VDisk=$1
    [ -e ${VDisk} ] || return 1

    IsVirtualDiskLoaded ${VDisk} || return 0
    IsVDiskMounted ${VDisk} || return 0

    local loopdev=$(GetVirtualDiskLoadedDevice ${VDisk})
    [ -n "${loopdev}" ] || return 1

    echo -e "LOADED: ${C_HL}${VDisk}${C_CLR} ${C_YEL}${loopdev}${C_CLR}"
    mount | /bin/grep "$(basename ${loopdev}p)" | while read line
    do
        local mdev=$(echo ${line} | awk '{print $1}')
        local mdir=$(echo ${line} | awk '{print $3}')
        echo -e "MOUNTED: ${C_YEL}${mdev}${C_CLR} --> ${C_BLU}${mdir}${C_CLR}"
    done
}




