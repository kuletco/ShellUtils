#!/bin/bash

RequiredUtils="mount dmsetup losetup blkid lsblk parted mkfs.ext4 mkfs.fat mksquashfs"

# Base Vars
WorkDir=$(pwd)
ScriptDir=$(cd $(dirname ${BASH_SOURCE}); pwd)
FunctionsDir=${ScriptDir}/Functions
ConfigFile=${ScriptDir}/settings.conf

if [ ! -d ${FunctionsDir} ]; then
    echo "Error: Cannot find 'Functions' in the script folder."
    exit 1
fi

if [ ! -f ${ConfigFile} ]; then
    echo "Error: Cannot find 'settings.conf' in the current folder."
    exit 1
fi

source ${FunctionsDir}/Color.sh
source ${FunctionsDir}/Base.sh
source ${FunctionsDir}/Configure.sh
source ${FunctionsDir}/Mount.sh
source ${FunctionsDir}/Rootfs.sh
source ${FunctionsDir}/Packages.sh

# Usage: MountChroot <RootDir> <CacheDir>
doMountChroot()
{
    if [ $# -ne 2 ]; then
        echo -e "Usage: MountChroot <RootDir> <CacheDir>"
        return 1
    fi

    local RootDir=$1
    local CacheDir=$2

    local SysLogDir="${RootDir}/var/log"
    local SysLogSaveDir="${UserDataDir}/var/log"

    mkdir -p "${SysLogDir}" "${SysLogSaveDir}"
    Mount --bind "${SysLogSaveDir}" "${SysLogDir}" || return 1

    MountCache "${RootDir}" "${CacheDir}" || return ?
    MountSystemEntries "${RootDir}" || return $?
    MountUserEntries "${RootDir}" || return $?
}

# Usage: UnMountChroot <RootDir>
doUnMountChroot()
{
    if [ $# -ne 1 ]; then
        echo -e "Usage: UnMountChroot <RootDir>"
        return 1
    fi

    local RootDir=$1

    UnMountCache "${RootDir}" || return 1
    UnMountUserEntries "${RootDir}" || return 1
    UnMountSystemEntries "${RootDir}" || return 1

    UnMount "${RootDir}" || return 1

    return 0
}

doInstallPackages()
{
    InstallPackages "${RootDir}" Update || return $?
    InstallPackages "${RootDir}" Upgrade || return $?
    InstallPackages "${RootDir}" Install ${Packages} || return $?

    return 0
}

doInstallExtraPackages()
{
    InstallExtrenPackages "${RootDir}" ${PackagesExtra} || return $?

    return 0
}

doRemovePackages()
{
    UnInstallPackages "${RootDir}" Purge ${PackagesUnInstall} || return $?

    return 0
}

Usage()
{
    local USAGE=''
    USAGE="${USAGE:+${USAGE}\n}$(basename $0) <Command> <Command> ... (Command Sequence)"
    USAGE="${USAGE:+${USAGE}\n}Commands:"
    USAGE="${USAGE:+${USAGE}\n}  -a|a|auto        : Auto process all by step [default: empiIrPuZ]."
    USAGE="${USAGE:+${USAGE}\n}  -e|e|expand      : Uncompress the base filesystem(default is '$(basename ${RootfsBasePackage})') to '$(basename ${RootDir})'."
    USAGE="${USAGE:+${USAGE}\n}  -m|m|mount       : Mount 'chroot' env to '$(basename ${RootDir})'."
    USAGE="${USAGE:+${USAGE}\n}  -u|u|umount      : Unmount 'chroot' env from '$(basename ${RootDir})'."
    USAGE="${USAGE:+${USAGE}\n}  -i|i|install     : Install packages."
    USAGE="${USAGE:+${USAGE}\n}  -I|I|instext     : Install extra packages."
    USAGE="${USAGE:+${USAGE}\n}  -r|r|remove      : Remove exist packages."
    USAGE="${USAGE:+${USAGE}\n}  -p|p|pre-setup   : Pre-Setup settings, include replace files, gen-locales, ie...."
    USAGE="${USAGE:+${USAGE}\n}  -P|P|post-setup  : Post-Setup settings, include user password, ie...."
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
                doMountChroot "${RootDir}" "${CacheDir}" || exit $?
                ;;
            -u|u|umount|uload)
                shift
                CheckPrivilege || exit $?
                doUnMountChroot "${RootDir}" || exit $?
                ;;
            -e|e|expand)
                shift
                CheckPrivilege || exit $?
                UnPackRootFS "${RootfsBasePackage}" "${RootDir}" || exit $?
                ;;
            -p|p|pre-setup)
                shift
                CheckPrivilege || exit $?
                GenerateFSTAB "${RootDir}" || exit $?
                ReplaceFiles "${RootDir}" "${ProfilesDir}" ${PreReplaceFiles} || exit $?
                ;;
            -i|i|install)
                shift
                CheckPrivilege || exit $?
                doInstallPackages || exit $?
                ;;
            -I|I|instext)
                shift
                CheckPrivilege || exit $?
                doInstallExtraPackages || exit $?
                ;;
            -r|r|remove)
                shift
                CheckPrivilege || exit $?
                doRemovePackages || exit $?
                ;;
            -P|P|post-setup)
                shift
                CheckPrivilege || exit $?
                ReplaceFiles "${RootDir}" "${ProfilesDir}" ${PostReplaceFiles} || exit $?
                SetUserPassword "${RootDir}" ${AccountUsername} ${AccountPassword} || exit $?
                ClearRootFS "${RootDir}" || exit $?
                ;;
            -Z|Z|mksquashfs)
                shift
                CheckPrivilege || exit $?
                doUnMountChroot "${RootDir}" || exit $?
                MakeSquashfs "${SquashfsFile}" "${RootDir}" || exit $?
                ;;
            -a|a|auto)
                shift
                CheckPrivilege || exit $?
                # expand
                UnPackRootFS "${RootfsBasePackage}" "${RootDir}" || exit $?
                # mount
                doMountChroot "${RootDir}" "${CacheDir}" || exit $?
                # pre-setup
                GenerateFSTAB "${RootDir}" || exit $?
                CopyFiles "${RootDir}" "${ProfilesDir}" ${PreCopyFiles} || exit $?
                ReplaceFiles "${RootDir}" "${ProfilesDir}" ${PreReplaceFiles} || exit $?
                # install
                doInstallPackages || exit $?
                # instext
                doInstallExtraPackages || exit $?
                # remove
                doRemovePackages || exit $?
                # post-setup
                CopyFiles "${RootDir}" "${ProfilesDir}" ${PostCopyFiles} || exit $?
                ReplaceFiles "${RootDir}" "${ProfilesDir}" ${PostReplaceFiles} || exit $?
                SetUserPassword "${RootDir}" ${AccountUsername} ${AccountPassword} || exit $?
                ClearRootFS "${RootDir}" || exit $?
                # umount
                doUnMountChroot "${RootDir}" || exit $?
                # mksquashfs
                MakeSquashfs "${SquashfsFile}" "${RootDir}" || exit $?
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
