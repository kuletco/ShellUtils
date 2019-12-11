#!/bin/bash

WorkDir=$(pwd)
ScriptDir=$(cd $(dirname ${BASH_SOURCE}); pwd)
source ${ScriptDir}/Color.sh
source ${ScriptDir}/Mount.sh
source ${ScriptDir}/Configure.sh

# Usage: UnPackRootFS <Package> <RootDir>
UnPackRootFS()
{
    if [ $# -ne 2 ]; then
        echo -e "Usage: UnPackRootFS <Package> <RootDir>"
        return 1
    fi

    local Package=$1
    local RootDir=$2

    if [ ! -f "${Package}" ]; then
        echo "Cannot find Rootfs Package."
        return 1
    fi

    [ -d "${RootDir}" ] || mkdir -p "${RootDir}"

    printf "UNPACK: ${C_HL}${Package##*${WorkDir}/}${C_CLR} --> ${C_BLU}${RootDir##*${WorkDir}/}${C_CLR} ..."
    if ! tar --exclude=dev/* -xf "${Package}" -C "${RootDir}" >>/dev/null 2>&1; then
        printf " [${C_FL}]\n"
        return 1
    else
        printf " [${C_OK}]\n"
        return 0
    fi
}

# Usage: MakeSquashfs <Squashfs File> <RootDir>
MakeSquashfs()
{
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

# Usage: ReplaceFiles <RootDir> <ProfilesDir> <Files...>
ReplaceFiles()
{
    if [ $# -lt 2 ]; then
        echo -e "Usage: ReplaceFiles <RootDir> <ProfilesDir> <Files...>"
        return 1
    fi

    local RootDir=$1
    local ProfilesDir=$2
    shift 2
    local FileList=$@
    local BackupDir="${ProfilesDir}/backup"
    local ModifiedDir="${ProfilesDir}/modified"

    if [ ! -d "${RootDir}" ]; then
        echo "Cannot find Rootfs dir."
        return 1
    fi

    if [ -z "${FileList}" ] || [ ! -d "${ModifiedDir}" ]; then
        return 0
    fi

    if [ -d "${ProfilesDir}/modified" ]; then
        for File in ${FileList}
        do
            # Backup File
            mkdir -p ${BackupDir}
            if [ -f "${RootDir}/${File}" ]; then
                cp -a "${RootDir}/${File}" "${BackupDir}" >/dev/null 2>&1
            fi
            # Copy File
            printf "REPLACE: ${C_HL}${File}${C_CLR} ..."
            FileName=$(basename ${File})
            if [ -f "${ModifiedDir}/${FileName}" ]; then
                mkdir -p "$(dirname ${RootDir}/${File})"
                if ! cp -a "${ModifiedDir}/${FileName}" "${RootDir}/${File}" >/dev/null 2>&1; then
                    printf " [${C_FL}]\n"
                else
                    printf " [${C_OK}]\n"
                fi
            fi
        done
    fi
}

# Usage: CopyFiles <RootDir> <ProfilesDir> <Files...>
CopyFiles()
{
    if [ $# -lt 2 ]; then
        echo -e "Usage: CopyFiles <RootDir> <ProfilesDir> <Files...>"
        return 1
    fi

    local RootDir=$1
    local ProfilesDir=$2
    shift 2
    local FileList=$@
    local CopyFilesDir="${ProfilesDir}/copyfiles"

    if [ ! -d "${RootDir}" ]; then
        echo "Cannot find Rootfs dir."
        return 1
    fi

    if [ -z "${FileList}" ] || [ ! -d "${CopyFilesDir}" ]; then
        return 0
    fi

    if [ -d "${ProfilesDir}/${CopyFilesDir}" ]; then
        for File in ${FileList}
        do
            # Check Target File
            if [ -f "${RootDir}/${File}" ]; then
                echo "COPY: Skip! Target [${RootDir##*${WorkDir}/}/${File}] Exist! Use ReplaceFiles Function instead it and rebuild again."
                continue
            fi
            # Copy File
            printf "COPY: ${C_HL}${File}${C_CLR} ..."
            FileName=$(basename ${File})
            if [ -f "${CopyFilesDir}/${FileName}" ]; then
                mkdir -p "$(dirname ${RootDir}/${File})"
                if ! cp -a "${CopyFilesDir}/${FileName}" "${RootDir}/${File}" >/dev/null 2>&1; then
                    printf " [${C_FL}]\n"
                else
                    printf " [${C_OK}]\n"
                fi
            fi
        done
    fi
}

# Usage: InstallPreSettings <RootDir> <PreSettingsDir>
InstallPreSettings()
{
    if [ $# -ne 2 ]; then
        echo -e "Usage: InstallPreSettings <RootDir> <PreSettingsDir>"
        return 1
    fi

    local RootDir=$1
    local PreSettingsDir=$2

    if [ ! -d "${RootDir}" ]; then
        echo "Cannot find Rootfs dir."
        return 1
    fi

    if [ -d "${PreSettingsDir}" ]; then
        printf "PRESETTING: Installing Pre-Settings files ..."
        rsync -aq ${PreSettingsDir}/ ${RootDir}
        if [ $? -eq 0 ]; then
            printf "[${C_OK}]\n"
            return 0
        else
            printf "[${C_FL}]\n"
            return 1
        fi
    else
        echo "PRESETTING: Skip."
        return 0
    fi
}

# Usage: GenerateFSTAB <VirtualDisk> <RootDir>
GenerateFSTAB()
{
    if [ $# -ne 1 ]; then
        echo -e "Usage: UnMountChroot <RootDir>"
        return 1
    fi

    local RootDir=$1

    if [ ! -d "${RootDir}" ]; then
        echo "Cannot find Rootfs dir."
        return 1
    fi
    if [ ! -d "${RootDir}/etc" ]; then
        echo "${RootDir} dir is invalid root file system dir"
        return 1
    fi

    # touch "${RootDir}/etc/fstab"
    ln -sf ../proc/self/mounts "${RootDir}/etc/fstab"

    return 0
}

# Usage: GenerateLocales <RootDir> <Locales>
GenerateLocales()
{
    if [ $# -lt 2 ]; then
        echo -e "Usage: GenerateLocales <RootDir> <Locales>"
        return 1
    fi

    local RootDir=$1
    shift
    local Locales=$@

    if [ ! -d "${RootDir}" ]; then
        echo "Cannot find Rootfs dir."
        return 1
    fi
    if [ ! -d "${RootDir}/etc" ]; then
        echo "${RootDir} dir is invalid root file system dir"
        return 1
    fi

    if [ -x "${RootDir}/usr/sbin/locale-gen" ]; then
        for locale in ${Locales}
        do
            printf "GENLOCALES: Generating ${C_HL}${locale}${C_CLR} ..."
            if ! chroot "${RootDir}" locale-gen ${locale} >/dev/null 2>&1; then
                printf " [${C_FL}]\n"
            else
                printf " [${C_OK}]\n"
            fi
        done
    fi

    return 0
}

# Usage: SetUserPassword <RootDir> <Username> <Password>
SetUserPassword()
{
    if [ $# -ne 3 ]; then
        echo -e "Usage: SetUserPassword <RootDir> <Username> <Password>"
        return 1
    fi

    local RootDir=$1
    local Username=$2
    local Password=$3

    if [ ! -d "${RootDir}" ]; then
        echo "Cannot find Rootfs dir."
        return 1
    fi
    if [ ! -f "${RootDir}/etc/passwd" ]; then
        echo "${RootDir} dir is invalid Rootfs dir"
        return 1
    fi

    if ! /bin/grep -q ${Username} "${RootDir}/etc/passwd"; then
        printf "SETPASSWD: Adding User: ${C_HL}${Username}${C_CLR} ..."
        if ! chroot "${RootDir}" useradd --user-group --create-home --skel /etc/skel --shell /bin/bash ${Username}; then
            printf " [${C_FL}]\n"
            return 1
        fi
        printf " [${C_OK}]\n"
    fi

    # Init Root User with base profile
    local SkelDir="${RootDir}/etc/skel"
    local RootUserDir="${RootDir}/root"
    rsync -aq "${SkelDir}/" "${RootUserDir}"

    local ChPwdScript="/tmp/ChangeUserPassword"

    printf "SETPASSWD: Change Password: [${C_HL}${Username}${C_CLR}]:[${C_GEN}${Password}${C_CLR}] ..."
    local SCRIPT=''
    SCRIPT="${SCRIPT:+${SCRIPT}\n}#!/bin/bash"
    SCRIPT="${SCRIPT:+${SCRIPT}\n}echo ${Username}:${Password} | chpasswd"
    echo -e ${SCRIPT} > "${RootDir}/${ChPwdScript}"

    if [ $? -ne 0 ]; then
        printf " [${C_FL}]\n"
        return 1
    fi

    if ! chroot ${RootDir} bash "${ChPwdScript}"; then
        printf " [${C_FL}]\n"
    fi
    rm -f "${RootDir}/${ChPwdScript}"
    printf " [${C_OK}]\n"

    return 0
}

# Usage: ClearRootFS <RootDir>
ClearRootFS()
{
    if [ $# -ne 1 ]; then
        echo -e "Usage: ClearRootFS <RootDir>"
        return 1
    fi

    local RootDir=$1

    if [ ! -d "${RootDir}" ]; then
        echo "Cannot find Rootfs dir."
        return 1
    fi

    rm -f "${RootDir}/*.old"
}
