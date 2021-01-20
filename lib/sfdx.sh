#!/usr/bin/env bash

invokeCmd() {
  debug "CMD: $1"
  eval $1
}

# <DIR> <SFDX_AUTH_URL> <d|s> <alias>
auth() {
  local SFDX_AUTH_URL_FILE="$1"
  if [ ! "$2" == "" ]; then
    echo "$2" > "$SFDX_AUTH_URL_FILE"
  fi
  invokeCmd "sfdx force:auth:sfdxurl:store -f $SFDX_AUTH_URL_FILE -$3 -a $4"
}

# <BUILD DIR>
install_sfdx_cli() {
  local BUILD_DIR="$1"
  log "Downloading Salesforce CLI tarball ..."
  mkdir sfdx && curl --silent --location "https://developer.salesforce.com/media/salesforce-cli/sfdx-cli/channels/stable/sfdx-cli-linux-x64.tar.xz" | tar xJ -C sfdx --strip-components 1

  log "Copying Salesforce CLI binary ..."

  rm -rf "$BUILD_DIR/vendor/sfdx"
  mkdir -p "$BUILD_DIR/vendor/sfdx"
  cp -r sfdx "$BUILD_DIR/vendor/sfdx/cli"
  chmod -R 755  "$BUILD_DIR/vendor/sfdx/cli"
}

# <BUILD DIR>
install_jq() {
  local BUILD_DIR="$1"

  log "Downloading jq ..."
  mkdir -p "$BUILD_DIR/vendor/sfdx/jq"
  cd "$BUILD_DIR/vendor/sfdx/jq"
  wget --quiet -O jq https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
  chmod +x jq
}

setup_paths() {
  local BUILD_DIR="$1"
  export PATH="$BUILD_DIR/vendor/sfdx/cli/bin:$PATH"
  export PATH="$BUILD_DIR/vendor/sfdx/jq:$PATH"

  debug "SFDX version: $(sfdx version)"
  debug "Plugins: $(sfdx plugins --core)"
}
