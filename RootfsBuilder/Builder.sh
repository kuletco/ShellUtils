#!/bin/bash

RequiredUtils="mount dmsetup losetup blkid lsblk parted mkfs.ext4 mkfs.fat mksquashfs"

# Base Vars
WorkDir=$(pwd)
ScriptDir=$(cd $(dirname ${BASH_SOURCE}); pwd)
FunctionsDir=${ScriptDir}/Functions
ConfigFile=${WorkDir}/settings.conf
[ -d ${FunctionsDir} ] || (echo "Error: Cannot find 'Functions' in the script folder." && return 1)
[ -f ${ConfigFile} ] || (echo "Error: Cannot find 'settings.conf' in the current folder." && return 1)

source ${FunctionsDir}/Color.sh
source ${FunctionsDir}/Base.sh
source ${FunctionsDir}/Configure.sh
source ${FunctionsDir}/Mount.sh
source ${FunctionsDir}/Rootfs.sh
source ${FunctionsDir}/Packages.sh

# Usage: MountChroot <RootDir> <CacheDir>
doMountChroot()
{
    [ $# -eq 2 ] || (echo -e "Usage: MountChroot <RootDir> <CacheDir>" && return 1)

    local RootDir=$1
    local CacheDir=$2

    local SysLogDir=${RootDir}/var/log
    local SysLogSaveDir=${UserDataDir}/var/log

    mkdir -p ${SysLogDir} ${SysLogSaveDir}
    Mount --bind ${SysLogSaveDir} ${SysLogDir} || return 1

    MountCache ${RootDir} ${CacheDir} || return ?
    MountSystemEntries ${RootDir} || return $?
    MountUserEntries ${RootDir} || return $?
}

# Usage: UnMountChroot <RootDir>
doUnMountChroot()
{
    [ $# -eq 1 ] || (echo -e "Usage: UnMountChroot <RootDir>" && return 1)

    local RootDir=$1

    UnMountCache ${RootDir} || return 1
    UnMountUserEntries ${RootDir} || return 1
    UnMountSystemEntries ${RootDir} || return 1

    UnMount ${RootDir} || return 1

    return 0
}

doInstallPackages()
{
    InstallPackages ${RootDir} Update || return $?
    InstallPackages ${RootDir} Upgrade || return $?
    InstallPackages ${RootDir} Install ${Packages} || return $?

    return 0
}

doInstallExtraPackages()
{
    InstallExtrenPackages ${RootDir} ${PackagesExtra} || return $?

    return 0
}

Usage()
{
    local USAGE=''
    USAGE="${USAGE:+${USAGE}\n}$(basename $0) <Command> <Command> ... (Command Sequence)"
    USAGE="${USAGE:+${USAGE}\n}Commands:"
    USAGE="${USAGE:+${USAGE}\n}  -a|a|auto        : Auto process all by step."
    USAGE="${USAGE:+${USAGE}\n}  -m|m|mount       : Mount 'chroot' env to '$(basename ${RootDir})'."
    USAGE="${USAGE:+${USAGE}\n}  -u|u|umount      : Unmount 'chroot' env from '$(basename ${RootDir})'."
    USAGE="${USAGE:+${USAGE}\n}  -U|U|unpack      : Unpack the base filesystem(default is '$(basename ${RootfsPackage})') to '$(basename ${RootDir})'."
    USAGE="${USAGE:+${USAGE}\n}  -P|P|pre-process : Pre-Process unpacked filesystem, include replace files, gen-locales, ie...."
    USAGE="${USAGE:+${USAGE}\n}  -I|I|install     : Install packages."
    USAGE="${USAGE:+${USAGE}\n}  -E|E|instext     : Install extra packages."
    USAGE="${USAGE:+${USAGE}\n}  -S|S|setup       : Setup settings, include user password, ie...."
    USAGE="${USAGE:+${USAGE}\n}  -Z|Z|mksquashfs  : Make a SquashFS image contain the RootFS."
    USAGE="${USAGE:+${USAGE}\n}  -s|show-settings : Show current settings."
    echo -e ${USAGE}
}

doMain()
{
    LoadSettings ${ConfigFile} || exit $?
    CheckBuildEnvironment || exit $?

    while [ $# -ne 0 ]
    do
        case $1 in
            -m|m|mount)
                shift
                CheckPrivilege || exit $?
                doMountChroot ${RootDir} ${CacheDir} || exit $?
                ;;
            -u|u|umount|uload)
                shift
                CheckPrivilege || exit $?
                doUnMountChroot ${RootDir} || exit $?
                ;;
            -U|U|unpack)
                shift
                CheckPrivilege || exit $?
                UnPackRootFS ${RootfsPackage} ${RootDir} || exit $?
                ;;
            -P|P|pre-process)
                shift
                CheckPrivilege || exit $?
                GenerateFSTAB ${RootDir} || exit $?
                ReplaceFiles ${RootDir} ${ProfilesDir} ${ReplaceFiles} || exit $?
                ;;
            -I|I|install)
                shift
                CheckPrivilege || exit $?
                doInstallPackages || exit $?
                ;;
            -E|E|instext)
                shift
                CheckPrivilege || exit $?
                doInstallExtraPackages || exit $?
                ;;
            -S|S|setup)
                shift
                CheckPrivilege || exit $?
                SetUserPassword ${RootDir} ${AccountUsername} ${AccountPassword} || exit $?
                ClearRootFS ${RootDir} || exit $?
                ;;
            -Z|Z|mksquashfs)
                shift
                CheckPrivilege || exit $?
                ClearRootFS ${RootDir} || exit $?
                MakeSquashfs ${SquashfsFile} ${RootDir} || exit $?
                ;;
            -a|a|auto)
                shift
                CheckPrivilege || exit $?
                UnPackRootFS ${RootfsPackage} ${RootDir} || exit $?
                doMountChroot ${RootDir} ${CacheDir} || exit $?
                GenerateFSTAB ${RootDir} || exit $?
                ReplaceFiles ${RootDir} ${ProfilesDir} ${ReplaceFiles} || exit $?
                doInstallPackages || exit $?
                doInstallExtraPackages || exit $?
                ReplaceFiles ${RootDir} ${ProfilesDir} ${ReplaceFiles} || exit $?
                SetUserPassword ${RootDir} ${AccountUsername} ${AccountPassword} || exit $?
                ClearRootFS ${RootDir} || exit $?
                doUnMountChroot ${RootDir} || exit $?
                MakeSquashfs ${SquashfsFile} ${RootDir} || exit $?
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
