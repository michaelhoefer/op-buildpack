#!/usr/bin/env bash

set -o errexit    # always exit on error
set -o pipefail   # don't ignore exit codes when piping output
set -o nounset    # fail on unset variables

#################################################################
# Script to setup a fully configured pipeline for Salesforce DX #
#################################################################

if [ "${1:-}" == "" ]; then
  echo Usage: ./setup.sh "<github repo>" "<package name>" "<app name>" "<dev hub alias>" "[heroku team name]"
  exit 0
fi

### Declare values

# Repository with your code
GITHUB_REPO=${1}

# Your package name
PACKAGE_NAME=${2}

# Descriptive name for the Heroku app
SFDX_APP_NAME=${3}

# Alias for your dev hub org
DEV_HUB_USERNAME=${4}

# Name of your team (optional)
HEROKU_TEAM_NAME=${5:-}


# Pipeline Names
HEROKU_PIPELINE_NAME="$SFDX_APP_NAME-pipeline"
#HEROKU_DEV_APP_NAME="$SFDX_APP_NAME-dev"
HEROKU_STAGING_APP_NAME="$SFDX_APP_NAME-staging"
HEROKU_PROD_APP_NAME="$SFDX_APP_NAME-prod"

### Setup

# Support a Heroku team
HEROKU_TEAM_FLAG=""
if [ ! "$HEROKU_TEAM_NAME" == "" ]; then
  HEROKU_TEAM_FLAG="-t $HEROKU_TEAM_NAME"
fi

# Clean up script (in case something goes wrong)
echo "heroku pipelines:destroy $HEROKU_PIPELINE_NAME
#heroku apps:destroy -a $HEROKU_DEV_APP_NAME -c $HEROKU_DEV_APP_NAME
heroku apps:destroy -a $HEROKU_STAGING_APP_NAME -c $HEROKU_STAGING_APP_NAME
heroku apps:destroy -a $HEROKU_PROD_APP_NAME -c $HEROKU_PROD_APP_NAME
rm -- \"destroy$HEROKU_PIPELINE_NAME.sh\"" > destroy$HEROKU_PIPELINE_NAME.sh

echo ""
echo "Run ./destroy$HEROKU_PIPELINE_NAME.sh to remove resources"
echo ""

chmod +x "destroy$HEROKU_PIPELINE_NAME.sh"

# Create three Heroku apps to map to orgs
#heroku apps:create $HEROKU_DEV_APP_NAME $HEROKU_TEAM_FLAG
heroku apps:create $HEROKU_STAGING_APP_NAME $HEROKU_TEAM_FLAG
heroku apps:create $HEROKU_PROD_APP_NAME $HEROKU_TEAM_FLAG

# Turn on debug logging. TODO remove.
heroku config:set SFDX_BUILDPACK_DEBUG=true -a $HEROKU_STAGING_APP_NAME
heroku config:set SFDX_BUILDPACK_DEBUG=true -a $HEROKU_PROD_APP_NAME

# Setup sfdxUrl's for Dev Hub auth
devHubSfdxAuthUrl=$(sfdx force:org:display --verbose -u $DEV_HUB_USERNAME --json | jq -r .result.sfdxAuthUrl)

# Setup dev (parent for review apps)
#heroku config:set SFDX_DEV_HUB_AUTH_URL=$devHubSfdxAuthUrl -a $HEROKU_DEV_APP_NAME
#heroku config:set SFDX_SCRATCH_NAME="$SFDX_APP_NAME" -a $HEROKU_DEV_APP_NAME
#heroku config:set SFDX_PUSH_SOURCE=true -a $HEROKU_DEV_APP_NAME

# Setup staging
heroku config:set SFDX_DEV_HUB_AUTH_URL=$devHubSfdxAuthUrl -a $HEROKU_STAGING_APP_NAME
heroku config:set SFDX_CREATE_PACKAGE_VERSION=true -a $HEROKU_STAGING_APP_NAME
heroku config:set SFDX_PACKAGE_NAME="$PACKAGE_NAME" -a $HEROKU_STAGING_APP_NAME

# Setup prod
heroku config:set SFDX_DEV_HUB_AUTH_URL=$devHubSfdxAuthUrl -a $HEROKU_PROD_APP_NAME
heroku config:set SFDX_PROMOTE_PACKAGE_VERSION=true -a $HEROKU_PROD_APP_NAME

# Add buildpack to apps
heroku buildpacks:add -i 1 https://github.com/michaelhoefer/op-buildpack -a $HEROKU_PROD_APP_NAME
heroku buildpacks:add -i 1 https://github.com/michaelhoefer/op-buildpack -a $HEROKU_STAGING_APP_NAME

echo "Creating $HEROKU_PIPELINE_NAME ..."

# Create Pipeline
#heroku pipelines:create $HEROKU_PIPELINE_NAME -a $HEROKU_DEV_APP_NAME -s development $HEROKU_TEAM_FLAG
#heroku pipelines:add $HEROKU_PIPELINE_NAME -a $HEROKU_STAGING_APP_NAME -s staging
heroku pipelines:create $HEROKU_PIPELINE_NAME -a $HEROKU_STAGING_APP_NAME -s staging $HEROKU_TEAM_FLAG
heroku pipelines:add $HEROKU_PIPELINE_NAME -a $HEROKU_PROD_APP_NAME -s production
HEROKU_PIPELINE_ID=$(heroku pipelines --json | jq -r ".[] | select(.name == \"$HEROKU_PIPELINE_NAME\") | .id")

echo "Configuring CI "
heroku ci:config:set -p $HEROKU_PIPELINE_NAME SFDX_SCRATCH_NAME="$SFDX_APP_NAME"
heroku ci:config:set -p $HEROKU_PIPELINE_NAME SFDX_DEV_HUB_AUTH_URL=$devHubSfdxAuthUrl
heroku ci:config:set -p $HEROKU_PIPELINE_NAME SFDX_PUSH_SOURCE=true
heroku ci:config:set -p $HEROKU_PIPELINE_NAME SFDX_BUILDPACK_DEBUG=true
heroku ci:config -p $HEROKU_PIPELINE_NAME

exit 0

# Setup your pipeline
echo "Connecting github and enabling review apps"
heroku pipelines:connect $HEROKU_PIPELINE_NAME --repo $GITHUB_REPO
heroku reviewapps:enable -p $HEROKU_PIPELINE_NAME

curl -n -X PATCH https://api.heroku.com/pipelines/$HEROKU_PIPELINE_ID/review-app-config \
-d "{
  \"repo\": \"$GITHUB_REPO\",
  \"automatic_review_apps\": true,
  \"wait_for_ci\": true,
  \"destroy_stale_apps\": true,
  \"stale_days\": 4,
  \"base_name\": \"$SFDX_APP_NAME\"
}" -H "Content-Type: application/json" -H "Accept: application/vnd.heroku+json; version=3"

curl -n -X PATCH https://api.heroku.com/pipelines/$HEROKU_PIPELINE_ID/stage/review/config-vars \
-d "{
  \"SFDX_DEV_HUB_AUTH_URL\": \"$devHubSfdxAuthUrl\",
  \"SFDX_SCRATCH_NAME\": \"$SFDX_APP_NAME\",
  \"SFDX_CREATE_SCRATCH_ORG\": \"true\",
  \"SFDX_PUSH_SOURCE\": \"true\"
}" -H "Content-Type: application/json" -H "Accept: application/vnd.heroku+json; version=3"
