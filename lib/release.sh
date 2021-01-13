#!/usr/bin/env bash

START_TIME=$SECONDS

# set -x
set -o errexit      # always exit on error
set -o pipefail     # don't ignore exit codes when piping output
unset GIT_DIR       # Avoid GIT_DIR leak from previous build steps

TARGET_SCRATCH_ORG_ALIAS=${1:-}
SFDX_PACKAGE_VERSION_ID=${2:-}

vendorDir="vendor/sfdx"

source "$vendorDir"/common.sh
source "$vendorDir"/sfdx.sh
source "$vendorDir"/stdlib.sh

: ${SFDX_BUILDPACK_DEBUG:="false"}

header "Running release.sh"

# Setup local paths
log "Setting up paths ..."

setup_dirs "."

log "Config vars ..."
debug "SFDX_DEV_HUB_AUTH_URL: $SFDX_DEV_HUB_AUTH_URL"
debug "SFDX_BUILDPACK_DEBUG: $SFDX_BUILDPACK_DEBUG"
debug "HEROKU_TEST_RUN_BRANCH: $HEROKU_TEST_RUN_BRANCH"
debug "HEROKU_TEST_RUN_COMMIT_VERSION: $HEROKU_TEST_RUN_COMMIT_VERSION"
debug "HEROKU_TEST_RUN_ID: $HEROKU_TEST_RUN_ID"
debug "STACK: $STACK"
debug "SOURCE_VERSION: $SOURCE_VERSION"
debug "TARGET_SCRATCH_ORG_ALIAS: $TARGET_SCRATCH_ORG_ALIAS"
debug "SFDX_INSTALL_PACKAGE_VERSION: $SFDX_INSTALL_PACKAGE_VERSION"
debug "SFDX_CREATE_PACKAGE_VERSION: $SFDX_CREATE_PACKAGE_VERSION"
debug "SFDX_PACKAGE_NAME: $SFDX_PACKAGE_NAME"
debug "SFDX_PACKAGE_VERSION_ID: $SFDX_PACKAGE_VERSION_ID"

whoami=$(whoami)
debug "WHOAMI: $whoami"

log "Parse sfdx.yml values ..."

# Parse sfdx.yml file into env
#BUG: not parsing arrays properly
eval $(parse_yaml sfdx.yml)

debug "scratch-org-def: $scratch_org_def"
debug "assign-permset: $assign_permset"
debug "permset-name: $permset_name"
debug "delete-test-org: $delete_test_org"
debug "delete-scratch-org: $delete_scratch_org"
debug "show_scratch_org_url: $show_scratch_org_url"
debug "open-path: $open_path"
debug "data-plans: $data_plans"

if [ "$SFDX_SOURCE_PUSH" == "" ]; then
  # Auth to scratch org, from file stored in vendor dir from prior compile
  auth "$vendorDir/$TARGET_SCRATCH_ORG_ALIAS" "" s "$TARGET_SCRATCH_ORG_ALIAS"

  log "Pushing source to scratch org ${TARGET_SCRATCH_ORG_ALIAS}..."
  invokeCmd "sfdx force:source:push -u $TARGET_SCRATCH_ORG_ALIAS"

  # Show scratch org URL
  if [ "$show_scratch_org_url" == "true" ]; then
    if [ ! "$open_path" == "" ]; then
      invokeCmd "sfdx force:org:open -r -p $open_path"
    else
      invokeCmd "sfdx force:org:open -r"
    fi
  fi

fi

if [ "$SFDX_PROMOTE_PACKAGE_VERSION" == "true" ]; then
  # Auth to Dev Hub
  auth "$vendorDir/sfdxurl" "$SFDX_DEV_HUB_AUTH_URL" d huborg

  log "Set package version as released ..."
  invokeCmd "sfdx force:package:version:promote --package \"$SFDX_PACKAGE_VERSION_ID\" --noprompt"
fi

if [ "$SFDX_INSTALL_PACKAGE_VERSION" == "true" ]; then
  # Auth to scratch org, from file stored in vendor dir from prior compile
  auth "$vendorDir/$TARGET_SCRATCH_ORG_ALIAS" "" s "$TARGET_SCRATCH_ORG_ALIAS"

  pkgVersionInstallScript=bin/package-install.sh
  if [ ! -f "$pkgVersionInstallScript" ]; then
    log "Installing package version $SFDX_PACKAGE_NAME ..."
    invokeCmd "sfdx force:package:install --noprompt --package \"$SFDX_PACKAGE_VERSION_ID\" -u \"$TARGET_SCRATCH_ORG_ALIAS\" --wait 1000 --publishwait 1000"

  else

    log "Calling $pkgVersionInstallScript"
    sh "$pkgVersionInstallScript" "$TARGET_SCRATCH_ORG_ALIAS" "$STAGE"

  fi

  if [ "$SFDX_BUILDPACK_DEBUG" == "true" ] ; then
    invokeCmd "sfdx force:package:installed:list -u \"$TARGET_SCRATCH_ORG_ALIAS\""
  fi

fi

postSetupScript=bin/post-setup.sh
# run post-setup script
if [ -f "$postSetupScript" ]; then

  debug "Calling $postSetupScript $TARGET_SCRATCH_ORG_ALIAS $STAGE"
  sh "$postSetupScript" "$TARGET_SCRATCH_ORG_ALIAS" "$STAGE"
fi

header "DONE! Completed in $(($SECONDS - $START_TIME))s"
exit 0
