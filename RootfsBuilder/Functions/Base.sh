#!/bin/bash

ScriptDir=$(cd $(dirname ${BASH_SOURCE}); pwd)
source ${ScriptDir}/Color.sh

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