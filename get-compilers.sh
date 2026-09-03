#! /bin/bash -x
# This used to use ssh to get large repositories from git using ssh.
# Which was too complicated and unreliable. Now we are directly downloading
# a zip file of each tool from the website.


if ! STAGING="$(mktemp -d compilersXXX)"
then
  echo Failed to make staging directory
  exit 1
fi

function cleanup_staging {
  rm -rf $STAGING 2> /dev/null
}

trap cleanup_staging EXIT

function get_compiler_zip {

  echo "Downloading ${1}..."

  pushd ${STAGING}
  rm -rf * 2> /dev/null

  REQUEST="requested_filename=${1}.zip"
  if (curl -Ljb cookies.txt "${COMPILERS}${REQUEST}" > ${1}.zip) && (unzip ${1}.zip)
  then
    popd
    rm -rf ${2} 2> /dev/null
    mkdir -p ${2}
    cp -a ${STAGING}/${1}/* ${2}/
  else
    popd
    exit 99
  fi
}

if get_compiler_zip swift-6.5 $1
then
  echo retrieving swift 6.5 compiler complete
else
  echo retrieving swift 6.5 compiler failed
  exit 1
fi
