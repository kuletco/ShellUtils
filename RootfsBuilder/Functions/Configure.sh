#!/bin/bash

[ -n "${ScriptDir}" ] || ScriptDir=$(cd $(dirname ${BASH_SOURCE}); pwd)
[ -n "${WorkDir}" ] || WorkDir=$(pwd)

BuildType=

SquashfsFile=
VDisk=
RootDir=
CacheDir=
ProfilesDir=
ExtPackageDir=
RootfsBasePackage=

PreCopyFiles=
PostCopyFiles=

PreReplaceFiles=
PostReplaceFiles=

Packages=
PackagesExtra=
PackagesUnInstall=

AptUrl=
Encoding=
Language=
Locales=
BootloaderID=
AccountUsername=
AccountPassword=

# USAGE: ConfGetSections <ConfFile>
ConfGetSections()
{
    if [ $# -ne 1 ]; then
        echo -e "Usage: ConfGetSections <ConfFile>"
        return 1
    fi

    local ConfFile=$1
    sed -n "/\[*\]/{s/\[//;s/\]///^;.*$/d;/^#.*$/d;p}" ${ConfFile}
}

# USAGE: ConfGetKeys <ConfFile> <Section>
ConfGetKeys()
{
    if [ $# -ne 2 ]; then
        echo -e "Usage: ConfGetKeys <ConfFile> <Section>"
        return 1
    fi

    local ConfFile=$1
    local Section=$2

    sed -n "/\[${Section}\]/,/\[.*\]/{/^\[.*\]/d;/^[ ]*$/d;/^;.*$/d;/^#.*$/d;p}" ${ConfFile} | awk -F '=' '{print $1}'
}

# USAGE: ConfGetValues <ConfFile> <Section>
ConfGetValues()
{
    if [ $# -ne 2 ]; then
        echo -e "Usage: ConfGetValues <ConfFile> <Section>"
        return 1
    fi

    local ConfFile=$1
    local Section=$2

    sed -n "/\[${Section}\]/,/\[.*\]/{/^\[.*\]/d;/^[ ]*$/d;/^;.*$/d;/^#.*$/d;p}" ${ConfFile} | awk -F '=' '{print $2}'
}

# USAGE: ConfGetValue <ConfFile> <Section> <Key>
ConfGetValue()
{
    if [ $# -ne 3 ]; then
        echo -e "Usage: ConfGetValue <ConfFile> <Section> <Key>"
        return 1
    fi

    local ConfFile=$1
    local Section=$2
    local Key=$3

    sed -n "/\[${Section}\]/,/\[.*\]/{/^\[.*\]/d;/^[ ]*$/d;s/;.*$//;s/^[| ]*${Key}[| ]*=[| ]*\(.*\)[| ]*/\1/p}" ${ConfFile}
}

# USAGE: ConfSetValue <ConfFile> <Section> <Key> <Value>
ConfSetValue()
{
    if [ $# -ne 4 ]; then
        echo -e "Usage: ConfSetValue <ConfFile> <Section> <Key> <Value>"
        return 1
    fi

    local ConfFile=$1
    local Section=$2
    local Key=$3
    local Value=$4

    sed -i "/^\[${Section}\]/,/^\[/ {/^\[${Section}\]/b;/^\[/b;s/^${Key}*=.*/${Key}=${Value}/g;}" ${ConfFile}
}

# Usage: GetConfPackages <ConfigFile> <Section>
GetConfPackages()
{
    if [ $# -ne 2 ]; then
        echo -e "Usage: GetConfPackages <ConfigFile> <Section>"
        return 1
    fi

    local ConfigFile=$1
    local Section=$2
    local Packages=""

    local PackagesList=$(ConfGetKeys ${ConfigFile} ${Section})
    [ -n "${PackagesList}" ] || return 1

    for Package in ${PackagesList}
    do
        local Enabled=$(ConfGetValue ${ConfigFile} ${Section} ${Package})
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

# Usage: GetConfPackages
ShowSettings()
{
    echo -e "BuildType          = ${BuildType}"
    echo -e "SquashfsFile       = ${SquashfsFile}"
    echo -e "VDisk              = ${VDisk}"
    echo -e "RootDir            = ${RootDir}"
    echo -e "CacheDir           = ${CacheDir}"
    echo -e "ProfilesDir        = ${ProfilesDir}"
    echo -e "RootfsBasePackage  = ${RootfsBasePackage}"
    echo -e "PreReplaceFiles    = ${PreReplaceFiles}"
    echo -e "PostReplaceFiles   = ${PostReplaceFiles}"
    echo -e "AptUrl             = ${AptUrl}"
    echo -e "Encoding           = ${Encoding}"
    echo -e "Language           = ${Language}"
    echo -e "Locales            = ${Locales}"
    echo -e "BootloaderID       = ${BootloaderID}"
    echo -e "AccountUsername    = ${AccountUsername}"
    echo -e "AccountPassword    = ${AccountPassword}"
}

# Usage: LoadSettings <ConfigFile>
LoadSettings()
{
    if [ $# -ne 1 ]; then
        echo -e "Usage: LoadSettings <ConfigFile>"
        return 1
    fi

    local ConfigFile=$1

    BuildType=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings BuildType)
    SquashfsFile=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings SquashfsFile)
    VDisk=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings VDisk)
    RootDir=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings RootDir)
    CacheDir=${ScriptDir}/$(ConfGetValue ${ConfigFile} Settings CacheDir)
    ProfilesDir=${ScriptDir}/$(ConfGetValue ${ConfigFile} Settings ProfilesDir)
    ExtPackageDir=${ScriptDir}/$(ConfGetValue ${ConfigFile} Settings ExtPackageDir)
    RootfsBasePackage=${ScriptDir}/$(ConfGetValue ${ConfigFile} Settings RootfsBasePackage)

    PreCopyFiles=$(ConfGetValues ${ConfigFile} PreCopy)
    PostCopyFiles=$(ConfGetValues ${ConfigFile} PostCopy)

    PreReplaceFiles=$(ConfGetValues ${ConfigFile} PreReplaces)
    PostReplaceFiles=$(ConfGetValues ${ConfigFile} PostReplaces)

    Packages=$(GetConfPackages ${ConfigFile} Packages)
    PackagesExtra=$(GetConfPackages ${ConfigFile} PackagesExtra)
    PackagesUnInstall=$(GetConfPackages ${ConfigFile} PackagesUnInstall)

    AptUrl=$(ConfGetValue ${ConfigFile} Settings AptUrl)
    Encoding=$(ConfGetValue ${ConfigFile} Settings Encoding)
    Language=$(ConfGetValue ${ConfigFile} Settings Language)
    Locales=$(ConfGetValue ${ConfigFile} Settings Locales)
    BootloaderID=$(ConfGetValue ${ConfigFile} Settings BootloaderID)
    AccountUsername=$(ConfGetValue ${ConfigFile} Settings AccountUsername)
    AccountPassword=$(ConfGetValue ${ConfigFile} Settings AccountPassword)
}
