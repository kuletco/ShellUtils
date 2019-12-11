
SquashfsFile=
VDisk=
RootDir=
CacheDir=
ProfilesDir=
ExtPackageDir=
RootfsPackage=
Packages=
PackagesExtra=
ReplaceFiles=

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
    [ $# -eq 1 ] || (echo -e "Usage: ConfGetSections <ConfFile>" && return 1)

    local ConfFile=$1
    sed -n "/\[*\]/{s/\[//;s/\]///^;.*$/d;/^#.*$/d;p}" ${ConfFile}
}

# USAGE: ConfGetKeys <ConfFile> <Section>
ConfGetKeys()
{
    [ $# -eq 2 ] || (echo -e "Usage: ConfGetKeys <ConfFile> <Section>" && return 1)

    local ConfFile=$1
    local Section=$2

    sed -n "/\[${Section}\]/,/\[.*\]/{/^\[.*\]/d;/^[ ]*$/d;/^;.*$/d;/^#.*$/d;p}" ${ConfFile} | awk -F '=' '{print $1}'
}

# USAGE: ConfGetValues <ConfFile> <Section>
ConfGetValues()
{
    [ $# -eq 2 ] || (echo -e "Usage: ConfGetValues <ConfFile> <Section>" && return 1)

    local ConfFile=$1
    local Section=$2

    sed -n "/\[${Section}\]/,/\[.*\]/{/^\[.*\]/d;/^[ ]*$/d;/^;.*$/d;/^#.*$/d;p}" ${ConfFile} | awk -F '=' '{print $2}'
}

# USAGE: ConfGetValue <ConfFile> <Section> <Key>
ConfGetValue()
{
    [ $# -eq 3 ] || (echo -e "Usage: ConfGetValue <ConfFile> <Section> <Key>" && return 1)

    local ConfFile=$1
    local Section=$2
    local Key=$3

    sed -n "/\[${Section}\]/,/\[.*\]/{/^\[.*\]/d;/^[ ]*$/d;s/;.*$//;s/^[| ]*${Key}[| ]*=[| ]*\(.*\)[| ]*/\1/p}" ${ConfFile}
}

# USAGE: ConfSetValue <ConfFile> <Section> <Key> <Value>
ConfSetValue()
{
    [ $# -eq 4 ] || (echo -e "Usage: ConfGetValue <ConfFile> <Section> <Key>" && return 1)

    local ConfFile=$1
    local Section=$2
    local Key=$3
    local Value=$4

    sed -i "/^\[${Section}\]/,/^\[/ {/^\[${Section}\]/b;/^\[/b;s/^${Key}*=.*/${Key}=${Value}/g;}" ${ConfFile}
}

# Usage: GetConfPackages <ConfigFile> <Section>
GetConfPackages()
{
    [ $# -eq 2 ] || (echo -e "Usage: GetConfPackages <ConfigFile> <Section>" && return 1)
    local ConfigFile=$1
    local Section=$2
    local PKGs=""

    [ -n "${ConfigFile}" ] || return 1
    [ -f "${ConfigFile}" ] || return 1

    local PackagesList=$(ConfGetKeys ${ConfigFile} ${Section})
    [ -n "${PackagesList}" ] || return 1

    for PKG in ${PackagesList}
    do
        local Enabled=$(ConfGetValue ${ConfigFile} ${Section} ${PKG})
        if [ -n "${Enabled}" ]; then
            case ${Enabled} in
                y|Y|yes|YES|Yes)
                    PKGs=${PKGs:+${PKGs} }${PKG}
                    ;;
                *)
                    ;;
            esac
        fi
    done

    if [ -z "${PKGs}" ]; then
        return 1
    fi

    echo ${PKGs}
}

# Usage: GetConfPackages
ShowSettings()
{
    echo -e "SquashfsFile = ${SquashfsFile}"
    echo -e "VDisk = ${VDisk}"
    echo -e "RootDir = ${RootDir}"
    echo -e "CacheDir = ${CacheDir}"
    echo -e "ProfilesDir = ${ProfilesDir}"
    echo -e "RootfsPackage = ${RootfsPackage}"
    echo -e "ReplaceFiles = ${ReplaceFiles}"
    echo -e "AptUrl = ${AptUrl}"
    echo -e "Encoding = ${Encoding}"
    echo -e "Language = ${Language}"
    echo -e "Locales = ${Locales}"
    echo -e "BootloaderID = ${BootloaderID}"
    echo -e "AccountUsername = ${AccountUsername}"
    echo -e "AccountPassword = ${AccountPassword}"
}

# Usage: LoadSettings <ConfigFile>
LoadSettings()
{
    [ $# -eq 1 ] || (echo -e "Usage: LoadSettings <ConfigFile>" && return 1)
    local ConfigFile=$1

    SquashfsFile=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings SquashfsFile)
    VDisk=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings VDisk)
    RootDir=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings RootDir)
    CacheDir=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings CacheDir)
    ProfilesDir=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings ProfilesDir)
    ExtPackageDir=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings ExtPackageDir)
    RootfsPackage=${WorkDir}/$(ConfGetValue ${ConfigFile} Settings RootfsPackage)
    Packages=$(GetConfPackages ${ConfigFile} Packages)
    PackagesExtra=$(GetConfPackages ${ConfigFile} PackagesExtra)
    ReplaceFiles=$(ConfGetValues ${ConfigFile} Replaces)

    AptUrl=$(ConfGetValue ${ConfigFile} Settings AptUrl)
    Encoding=$(ConfGetValue ${ConfigFile} Settings Encoding)
    Language=$(ConfGetValue ${ConfigFile} Settings Language)
    Locales=$(ConfGetValue ${ConfigFile} Settings Locales)
    BootloaderID=$(ConfGetValue ${ConfigFile} Settings BootloaderID)
    AccountUsername=$(ConfGetValue ${ConfigFile} Settings AccountUsername)
    AccountPassword=$(ConfGetValue ${ConfigFile} Settings AccountPassword)
}