#!/bin/bash

[ -n "${ScriptDir}" ] || ScriptDir=$(cd $(dirname ${BASH_SOURCE}); pwd)
[ -n "${FunctionsDir}" ] || FunctionsDir=${ScriptDir}/Functions

source ${FunctionsDir}/Color.sh

CheckPrivilege()
{
    if [ $UID -ne 0 ]; then
        echo -e  "Please run this script with ${C_HR}root${C_CLR} privileges."
        return 1
    else
        return 0
    fi
}

# USAGE: CheckBuildEnvironment <Required Utils List>
CheckBuildEnvironment()
{
    for Util in $@
    do
        if ! which ${Util} >/dev/null 2>&1; then
            echo -e "Please install [${C_RED}${Util}${C_CLR}] first"
            return 1
        fi
    done

    return 0
}