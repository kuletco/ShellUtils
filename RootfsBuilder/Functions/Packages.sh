#!/bin/bash

ScriptDir=$(cd $(dirname ${BASH_SOURCE}); pwd)
source ${ScriptDir}/Color.sh
source ${ScriptDir}/Mount.sh

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
            # if ! chroot ${RootDir} apt-get ${AptOptions} update >>${InsLogFile} 2>&1; then
            if ! chroot ${RootDir} apt ${AptOptions} update >>${InsLogFile} 2>&1; then
                printf " [${C_FL}]\n"
                return 1
            fi
            printf " [${C_OK}]\n"
        ;;
        -U|--upgrade|Upgrade|UPGRADE)
            printf "PKGINSTALL: ${C_YEL}Upgrading${C_CLR} Packages ..."
            # if ! chroot ${RootDir} apt-get ${AptOptions} upgrade >>${InsLogFile} 2>&1; then
            if ! chroot ${RootDir} apt ${AptOptions} upgrade >>${InsLogFile} 2>&1; then
                printf " [${C_FL}]\n"
                return 1
            fi
            printf " [${C_OK}]\n"
        ;;
        -i|--install|Install|INSTALL)
            for Package in ${Packages}
            do
                printf "PKGINSTALL: ${C_YEL}Installing${C_CLR} ${C_HL}${Package}${C_CLR} ..."
                # if ! chroot ${RootDir} apt-get ${AptOptions} install ${Package} >>${InsLogFile} 2>&1; then
                if ! DEBIAN_FRONTEND=noninteractive chroot ${RootDir} apt ${AptOptions} install ${Package} >>${InsLogFile} 2>&1; then
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

# Usage: InstallExtrenPackages <RootDir> <Packages>
InstallExtrenPackages()
{
    [ $# -ge 2 ] || (echo -e "Usage: InstallExtrenPackages <RootDir> <Packages>" && return 1)

    local RootDir=$1
    shift
    local Packages=$@
    local InsLogFile=$(pwd)/InsLogFile.log
    [ -d "${RootDir}" ] || return 1
    [ -n "${Packages}" ] || return 1
    echo "${Packages}"

    local DpkgOptions=""
    DpkgOptions="${DpkgOptions:+${DpkgOptions} }--install"

    for Package in ${Packages}
    do
        [ -f "${ExtPackageDir}/${Package}" ] || continue
        printf "PKGINSTALL: ${C_YEL}Installing${C_CLR} ${C_HL}${Package}${C_CLR} ..."
        DEBIAN_FRONTEND=noninteractive chroot ${RootDir} dpkg ${DpkgOptions} /media/${Package} >>${InsLogFile} 2>&1
        if [ $? -ne 0 ]; then
            DEBIAN_FRONTEND=noninteractive chroot ${RootDir} apt install -f >>${InsLogFile} 2>&1
            if [ $? -ne 0 ]; then
                printf " [${C_FL}]\n"
                return 1
            else
                printf " [${C_OK}]\n"
            fi
        else
            printf " [${C_OK}]\n"
        fi
    done
}
