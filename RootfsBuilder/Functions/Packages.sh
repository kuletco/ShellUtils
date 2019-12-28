#!/bin/bash

WorkDir=$(pwd)
ScriptDir=$(cd $(dirname ${BASH_SOURCE}); pwd)
source ${ScriptDir}/Color.sh
source ${ScriptDir}/Mount.sh

# Usage: InstallPackages <RootDir> <Option: Update|Upgrade|Install> <Packages...>
InstallPackages()
{
    if [ $# -lt 2 ]; then
        echo -e "Usage: InstallPackages <RootDir> <Option: Update|Upgrade|Install> <Packages...>"
        return 1
    fi
    local RootDir=$1
    local Options=$2
    shift 2
    local Packages=$@
    local LogFile=$(pwd)/LogFile-Package.log
    local AptOptions=""

    if [ ! -d "${RootDir}" ]; then
        echo "Cannot find Rootfs dir."
        return 1
    fi

    [ -f "${LogFile}" ] && rm -f ${LogFile}

    AptOptions="${AptOptions:+${AptOptions} }--quiet"
    AptOptions="${AptOptions:+${AptOptions} }--yes"
    AptOptions="${AptOptions:+${AptOptions} }--allow-change-held-packages"
    # AptOptions="${AptOptions:+${AptOptions} }--force-yes"
    # AptOptions="${AptOptions:+${AptOptions} }--no-install-recommends"

    case ${Options} in
        -u|--update|update|Update|UPDATE)
            printf "PKGINSTALL: ${C_YEL}Updating${C_CLR} Packages List ..."
            if ! chroot ${RootDir} apt ${AptOptions} update >>${LogFile} 2>&1; then
                printf " [${C_FL}]\n"
                return 1
            fi
            printf " [${C_OK}]\n"
            ;;
        -U|--upgrade|upgrade|Upgrade|UPGRADE)
            printf "PKGINSTALL: ${C_YEL}Upgrading${C_CLR} Packages ..."
            if ! DEBIAN_FRONTEND=noninteractive chroot ${RootDir} apt ${AptOptions} upgrade >>${LogFile} 2>&1; then
                printf " [${C_FL}]\n"
                return 1
            fi
            printf " [${C_OK}]\n"
            ;;
        -i|--install|install|Install|INSTALL)
            if [ -z "${Packages}" ]; then
                echo "Please assign at least one package to install."
                return 1
            fi
            for Package in ${Packages}
            do
                printf "PKGINSTALL: ${C_YEL}Installing${C_CLR} ${C_HL}${Package}${C_CLR} ..."
                if ! DEBIAN_FRONTEND=noninteractive chroot "${RootDir}" apt ${AptOptions} install ${Package} >>"${LogFile}" 2>&1; then
                    printf " [${C_FL}]\n"
                    return 1
                fi
                printf " [${C_OK}]\n"
            done
            ;;
        *)
            echo -e "PKGINSTALL: Error: Unknown Options [${Options}]."
            return 1
            ;;
    esac

    rm -f ${LogFile}
    return 0
}

# Usage: InstallExtrenPackages <RootDir> <Packages>
InstallExtrenPackages()
{
    if [ $# -lt 2 ]; then
        echo -e "Usage: InstallExtrenPackages <RootDir> <Packages>"
        return 1
    fi

    local RootDir=$1
    shift
    local Packages=$@
    local LogFile=$(pwd)/LogFile-Package.log

    if [ ! -d "${RootDir}" ]; then
        echo "Cannot find Rootfs dir."
        return 1
    fi
    if [ -z "${Packages}" ]; then
        echo "Please assign at least one package to install."
        return 1
    fi

    local DpkgOptions=""
    DpkgOptions="${DpkgOptions:+${DpkgOptions} }--install"

    for Package in ${Packages}
    do
        [ -f "${ExtPackageDir}/${Package}" ] || continue
        printf "PKGINSTALL: ${C_YEL}Installing${C_CLR} ${C_HL}${Package}${C_CLR} ..."
        DEBIAN_FRONTEND=noninteractive chroot "${RootDir}" dpkg ${DpkgOptions} /media/PackagesExtra/${Package} >>"${LogFile}" 2>&1
        if [ $? -ne 0 ]; then
            DEBIAN_FRONTEND=noninteractive chroot "${RootDir}" apt install -f >>"${LogFile}" 2>&1
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

# Usage: UnInstallPackages <RootDir> <Option: Remove|Purge> <Packages...>
UnInstallPackages()
{
    if [ $# -lt 2 ]; then
        echo -e "Usage: UnInstallPackages <RootDir> <Option: Remove|Purge> <Packages...>"
        return 1
    fi

    local RootDir=$1
    local Options=$2
    shift 2
    local Packages=$@
    local LogFile=$(pwd)/LogFile-Package.log
    local AptOptions=""

    if [ ! -d "${RootDir}" ]; then
        echo "Cannot find Rootfs dir."
        return 1
    fi
    if [ -z "${Packages}" ]; then
        echo "Please assign at least one package to uninstall."
        return 1
    fi

    [ -f "${LogFile}" ] && rm -f "${LogFile}"

    AptOptions="${AptOptions:+${AptOptions} }--quiet"
    AptOptions="${AptOptions:+${AptOptions} }--yes"
    AptOptions="${AptOptions:+${AptOptions} }--allow-change-held-packages"
    # AptOptions="${AptOptions:+${AptOptions} }--force-yes"
    # AptOptions="${AptOptions:+${AptOptions} }--no-install-recommends"

    case ${Options} in
        -r|--remove|remove|Remove|REMOMVE)
            for Package in ${Packages}
            do
                printf "PKGUNINSTALL: ${C_YEL}Removing${C_CLR} ${C_HL}${Package}${C_CLR} ..."
                if ! DEBIAN_FRONTEND=noninteractive chroot "${RootDir}" apt ${AptOptions} remove ${Package} >>"${LogFile}" 2>&1; then
                    printf " [${C_FL}]\n"
                    return 1
                fi
                printf " [${C_OK}]\n"
            done
            ;;
        -p|--purge|purge|Purge|PURGE)
            for Package in ${Packages}
                do
                printf "PKGUNINSTALL: ${C_YEL}Purging${C_CLR} ${C_HL}${Package}${C_CLR} ..."
                if ! DEBIAN_FRONTEND=noninteractive chroot "${RootDir}" apt ${AptOptions} purge ${Package} >>"${LogFile}" 2>&1; then
                    printf " [${C_FL}]\n"
                    return 1
                fi
                printf " [${C_OK}]\n"
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
