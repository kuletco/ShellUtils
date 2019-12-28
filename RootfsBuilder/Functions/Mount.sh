#!/bin/bash

WorkDir=$(pwd)
ScriptDir=$(cd $(dirname ${BASH_SOURCE}); pwd)
source ${ScriptDir}/Color.sh

# Usage: IsTargetMounted <Target>
IsTargetMounted()
{
    if [ $# -ne 1 ]; then
        echo -e "Usage: IsTargetMounted <Target>"
        return 1
    fi

    local Target=$1

    if [ -d "${Target}" ]; then
        return $(mountpoint -q "${Target}")
    elif [ -f "${Target}" -o -L "${Target}" ]; then
        return $(mount | /bin/grep -q ${Target})
    else
        return 1
    fi
}

# Usage: GetTargetMountPoint <Target>
GetTargetMountPoint()
{
    if [ $# -ne 1 ]; then
        echo -e "Usage: GetTargetMountPoint <Target>"
        return 1
    fi

    local Target=$1
    if [ -e "${Target}" ]; then
        echo "Target:[${Target}] Not Exist!"
        return 1
    fi

    IsTargetMounted "${Target}" || return 1
    local MountedDir=$(lsblk -n -o MOUNTPOINT "${Target}")
    [ -n "${MountedDir}" ] || return 1

    echo "${MountedDir}"
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
                Options="${Options:+${Options} }--types $2"
                shift 2
                ;;
            -b|--bind)
                Options="${Options:+${Options} }--bind"
                shift
                ;;
            -ro|--readonly)
                Options="${Options:+${Options} }--options ro"
                shift
                ;;
            *)
                if [ $# -ne 2 ]; then
                    echo -e ${Usage}
                    return 1
                fi
                local Source=$1
                local DstDir=$2
                shift 2
                ;;
        esac
    done

    if [ -z "${Source}" -o -z "${DstDir}" ]; then
        echo -e ${Usage} && return 1
    fi

    if eval ${Prefix} mountpoint -q "${DstDir}"; then
        return 0
    fi

    printf "MOUNT: ${C_GEN}${Options:+[${Options}] }${C_YEL}${Source##*${WorkDir}/}${C_CLR} --> ${C_BLU}${DstDir##*${WorkDir}/}${C_CLR}"
    if ! eval ${Prefix} mount ${Options} "${Source}" "${DstDir}" >/dev/null 2>&1; then
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
                Prefix="${Prefix:+${Prefix} }chroot \"${RootDir}\""
                shift 2
                ;;
            *)
                if [ $# -ne 1 ]; then
                    echo -e ${Usage}
                    return 1
                fi
                Directory=$1
                shift
                ;;
        esac
    done

    if [ -z "${Directory}" ]; then
        echo -e ${Usage} && return 1
    fi

    if eval ${Prefix} umount --help | grep -q "recursive"; then
        if eval ${Prefix} mountpoint -q "${Directory}"; then
            printf "UMOUNT: [${C_GEN}Recursive${C_CLR}] ${C_YEL}${Directory##*${WorkDir}/}${C_CLR}"
            if ! eval ${Prefix} umount -R "${Directory}" >/dev/null 2>&1; then
                if ! eval ${Prefix} umount -Rl "${Directory}" >/dev/null 2>&1; then
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
            if eval ${Prefix} mountpoint -q "${dir}"; then
                printf "UNMOUNT: ${C_YEL}${dir##*${WorkDir}/}${C_CLR}"
                if ! eval ${Prefix} umount "${dir}"; then
                    if ! eval ${Prefix} umount -l "${dir}"; then
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
    if [ $# -ne 2 ]; then
        echo -e "Usage: MountCache <RootDir> <CacheDir>"
        return 1
    fi

    local RootDir=$1
    local CacheDir=$2
    local RootAptCache=${RootDir}/var/cache/apt
    local RootAptLists=${RootDir}/var/lib/apt/lists
    local CacheAptCache=${CacheDir}/aptcache
    local CacheAptLists=${CacheDir}/aptlists

    mkdir -p ${CacheAptCache} ${CacheAptLists} ${RootAptCache} ${RootAptLists} || return 1

    Mount --bind ${CacheAptCache} ${RootAptCache} || return 1
    Mount --bind ${CacheAptLists} ${RootAptLists} || return 1

    return 0
}

# Usage: UnMountCache <RootDir>
UnMountCache()
{
    if [ $# -ne 1 ]; then
        echo -e "Usage: UnMountCache <RootDir>"
        return 1
    fi

    local RootDir=$1
    local RootAptCache=${RootDir}/var/cache/apt
    local RootAptLists=${RootDir}/var/lib/apt/lists

    for dir in ${RootAptCache} ${RootAptLists}
    do
        UnMount ${dir} || return 1
    done

    return 0
}

# Usage: MountSystemEntries <RootDir>
MountSystemEntries()
{
    if [ $# -ne 1 ]; then
        echo -e "Usage: MountSystemEntries <RootDir>"
        return 1
    fi

    local RootDir=$1

    mkdir -p ${RootDir}/proc ${RootDir}/sys ${RootDir}/dev ${RootDir}/run ${RootDir}/tmp ${RootDir}/host || return 1

    if [ -x ${RootDir}/bin/mount ]; then
        Mount --chroot ${RootDir} --types proc proc /proc
        Mount --chroot ${RootDir} --types sysfs sysfs /sys
        Mount --chroot ${RootDir} --types devtmpfs udev /dev
        [ -d ${RootDir}/dev/pts ] || mkdir ${RootDir}/dev/pts
        Mount --chroot ${RootDir} --types devpts devpts /dev/pts
        Mount --bind /run ${RootDir}/run
        Mount --bind /tmp ${RootDir}/tmp
        Mount --readonly --bind / ${RootDir}/host
    else
        echo -e "MOUNT: ${C_WARN} Please unpack rootfs package first."
        return 99
    fi

    return 0
}

# Usage: UnMountSystemEntries <RootDir>
UnMountSystemEntries()
{
    if [ $# -ne 1 ]; then
        echo -e "Usage: MountSystemEntries <RootDir>"
        return 1
    fi

    local RootDir=$1
    local Prefix=""

    [ -x ${RootDir}/bin/mountpoint ] && Prefix="chroot ${RootDir}"

    for dir in host tmp run dev/pts dev sys proc
    do
        if eval ${Prefix} mountpoint -q ${RootDir}/proc; then
            UnMount --chroot ${RootDir} ${dir} || return 1
        else
            UnMount ${RootDir}/${dir} || return 1
        fi
    done

    rm -rf ${RootDir}/host

    return 0
}

# Usage: MountUserEntries <RootDir>
MountUserEntries()
{
    if [ $# -ne 1 ]; then
        echo -e "Usage: MountUserEntries <RootDir>"
        return 1
    fi

    local RootDir=$1
    local UserDir=${RootDir}/data

    for dir in home root var/log
    do
        mkdir -p ${RootDir}/${dir} ${UserDir}/${dir} || return 1
        Mount --bind ${UserDir}/${dir} ${RootDir}/${dir} || return 1
    done

    # Mount ExtraPackage to rootfs/media
    mkdir -p ${RootDir}/media/PackagesExtra ${ExtPackageDir}
    Mount --bind ${ExtPackageDir} ${RootDir}/media/PackagesExtra

    return 0
}

# Usage: UnMountUserEntries <RootDir>
UnMountUserEntries()
{
    if [ $# -ne 1 ]; then
        echo -e "Usage: UnMountUserEntries <RootDir>"
        return 1
    fi

    local RootDir=$1

    # Mount ExtraPackage to rootfs/media
    UnMount ${RootDir}/media/PackagesExtra
    rm -rf ${RootDir}/media/PackagesExtra

    for dir in home root var/log
    do
        UnMount ${RootDir}/${dir} || return 1
    done

    return 0
}
