#!/bin/bash

ScriptDir=$(cd $(dirname ${BASH_SOURCE}); pwd)
source ${ScriptDir}/Color.sh
source ${ScriptDir}/Mount.sh
source ${ScriptDir}/Configure.sh

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

# Usage: MakeSquashfs <Squashfs File> <RootDir>
MakeSquashfs()
{
    [ $# -eq 2 ] || (echo -e "Usage: MakeSquashfs <Squashfs File> <RootDir>" && return 1)

    local Squashfs=$1
    local RootDir=$2

    printf "PACK: ${C_HL}${RootDir}${C_CLR} --> ${C_BLU}${Squashfs}${C_CLR} ..."
    if ! mksquashfs ${RootDir} ${Squashfs} -comp xz -processors 4 >>/dev/null 2>&1; then
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
    [ $# -gt 2 ] || (echo -e "Usage: ReplaceFiles <RootDir> <ProfilesDir> <Files...>" && return 1)

    local RootDir=$1
    local ProfilesDir=$2
    shift 2
    local FileList=$@
    local BackupDir=${ProfilesDir}/backup
    local ModifiedDir=${ProfilesDir}/modified

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

# Usage: InstallPreSettings <RootDir> <PreSettingsDir>
InstallPreSettings()
{
    [ $# -eq 2 ] || (echo -e "Usage: InstallPreSettings <RootDir> <PreSettingsDir>" && return 1)

    local RootDir=$1
    local PreSettingsDir=$2
    [ -d ${PreSettingsDir} ] || return 1
    [ -d ${RootDir} ] || return 1

    printf "PRESETTING: Installing Pre-Settings files ..."
    rsync -aq ${PreSettingsDir}/ ${RootDir}
    if [ $? -eq 0 ]; then
        printf "[${C_OK}]\n"
        return 0
    else
        printf "[${C_FL}]\n"
        return 1
    fi
}

# Usage: GenerateFSTAB <VirtualDisk> <RootDir>
GenerateFSTAB()
{
    [ $# -eq 1 ] || (echo -e "Usage: UnMountChroot <RootDir>" && return 1)

    local RootDir=$1

    # touch ${RootDir}/etc/fstab
    ln -sf ../proc/self/mounts ${RootDir}/etc/fstab

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

    IsTargetMounted ${RootDir} || (echo -e "${C_BLU}${RootDir}${C_CLR} not mounted"; return 1)
    if [ -x ${RootDir}/usr/sbin/locale-gen ]; then
        for locale in ${Locales}
        do
            printf "GENLOCALES: Generating ${C_HL}${locale}${C_CLR} ..."
            if ! chroot ${RootDir} locale-gen ${locale} >/dev/null 2>&1; then
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
    [ $# -eq 3 ] || (echo -e "Usage: SetUserPassword <RootDir> <Username> <Password>" && return 1)
    local RootDir=$1
    local Username=$2
    local Password=$3
    [ -n "${RootDir}" ] || return 1
    [ -d "${RootDir}" ] || return 1
    [ -n "${Username}" ] || return 1
    [ -n "${Password}" ] || return 1

    [ -f "${RootDir}/etc/passwd" ] || return 1

    if ! /bin/grep -q ${Username} ${RootDir}/etc/passwd; then
        printf "SETPASSWD: Adding User: ${C_HL}${Username}${C_CLR} ..."
        if ! chroot ${RootDir} useradd --user-group --create-home --skel /etc/skel --shell /bin/bash ${Username}; then
            printf printf " [${C_FL}]\n"
            return 1
        fi
        printf " [${C_OK}]\n"
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
    echo -e ${SCRIPT} > ${RootDir}/${ChPwdScript}

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

# Usage: ClearRootFS <RootDir>
ClearRootFS()
{
    [ $# -eq 1 ] || (echo -e "Usage: ClearRootFS <RootDir>" && return 1)

    local RootDir=$1

    rm -f ${RootDir}/*.old
}
