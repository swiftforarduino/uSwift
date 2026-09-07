#! /bin/bash -x
function get_compiler_zip {

  echo "Downloading ${1}..."

  mkdir -p "$2"

  ZIP="${2}/${1}.zip"
  REQUEST="requested_filename=${1}.zip"

  if [ -f "$ZIP" ]
  then
    # Remember the modification time before curl.
    MTIME_BEFORE=$(stat -f %m "$ZIP")
    CURL_TIME="-z $ZIP"
  else
    MTIME_BEFORE=""
    CURL_TIME=""
  fi

  HTTP_CODE=$(curl -R -Ljb cookies.txt \
    $CURL_TIME \
    "${COMPILERS}${REQUEST}" \
    -o "$ZIP" \
    -w '%{http_code}')
  CURL_STATUS=$?

  echo "  HTTP status: ${HTTP_CODE}"

  if [ $CURL_STATUS -ne 0 ]
  then
    echo "  Download failed (curl status ${CURL_STATUS})."
    exit 99
  fi

  MTIME_AFTER=$(stat -f %m "$ZIP")

  if [ "$MTIME_BEFORE" != "$MTIME_AFTER" ]
  then
    echo "  New file downloaded; extracting..."
    pushd "$2"
    unzip -o "${1}.zip" || exit 99
    cp -a "${1}"/* ./
    rm -rf "${1}"

  else
    echo "  Local file unchanged; no extraction required."
  fi
}

if get_compiler_zip swift-6.5 "$1"
then
  echo retrieving swift 6.5 compiler complete
else
  echo retrieving swift 6.5 compiler failed
  exit 1
fi
