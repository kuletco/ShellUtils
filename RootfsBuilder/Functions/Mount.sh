#!/bin/bash

ScriptDir=$(cd $(dirname ${BASH_SOURCE}); pwd)
source ${ScriptDir}/Color.sh

# Usage: IsTargetMounted <Target>
IsTargetMounted()
{
    [ $# -eq 1 ] || (echo -e "Usage: IsTargetMounted <Target>" && return 1)

    local Target=$1

    if [ -d "${Target}" ]; then
        return $(mountpoint -q "${Target}")
    elif [ -f "${Target}" -o -L "${Target}" ]; then
        return $(mount | /bin/grep -q ${Target})
    else
        return 1
    fi
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
    local UserDir=${RootDir}/data
    [ -n "${RootDir}" ] || return 1

    for dir in home root var/log
    do
        mkdir -p ${RootDir}/${dir} ${UserDir}/${dir} || return 1
        Mount --bind ${UserDir}/${dir} ${RootDir}/${dir} || return 1
    done

    # Mount ExtraPackage to rootfs/media
    mkdir -p ${RootDir}/media
    Mount --bind ${ExtPackageDir} ${RootDir}/media

    return 0
}

# Usage: UnMountUserEntries <RootDir>
UnMountUserEntries()
{
    [ $# -eq 1 ] || (echo -e "Usage: UnMountUserEntries <RootDir>" && return 1)

    local RootDir=$1
    [ -n "${RootDir}" ] || return 1

    # Mount ExtraPackage to rootfs/media
    UnMount ${RootDir}/media

    for dir in home root var/log
    do
        UnMount ${RootDir}/${dir} || return 1
    done

    return 0
}
