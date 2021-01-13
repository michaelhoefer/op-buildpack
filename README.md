# Heroku Buildpack for One Pipeline

This is the One Pipeline [Heroku buildpack](http://devcenter.heroku.com/articles/buildpacks) for apps built on the Salesforce One Platform.
This buildpack enables various Salesforce specific development operations for CI/CD, configured by simple Heroku app-based **config vars**, 
taking advantage of Heroku Pipelines with Review Apps, and Heroku CI.

Review Apps are used to automatically push code for pull requests to scratch orgs.
Heroku CI is used to test your code and gate code promotion in your repository.
Staging and Production apps in your pipeline automate creation and subsequent promotion of package versions.

This buildpack depends upon [https://github.com/heroku/salesforce-cli-buildpack](https://github.com/heroku/salesforce-cli-buildpack) to download and setup the Salesforce CLI and jq.

To get started, you need a few required configuration files in your Salesforce project, and a simple pipeline defined in your Heroku account, described below.

## Requirements

This One Pipeline buildpack requires the following to be present in the Salesforce app repository you're connecting to the pipeline.

1. **`app.json`**: The `app.json` file provides instructions to this buildpack. In particular, the `app.json` provides information used by review apps that are created when a pull request is initiated.

    - `buildpacks`: Specifies the buildpacks used by the review apps.
      ```
      "buildpacks": [
      {
        "url": "https://github.com/heroku/salesforce-cli-buildpack#v3"
      },
      {
        "url": "https://github.com/heroku/op-buildpack#v1"
      }
      ```

    - `env`: Specifies config vars and the values in the review app.

      ```
      "env": {
        "SFDX_DEV_HUB_AUTH_URL": {
          "required": true
        },
        "SFDX_BUILDPACK_DEBUG": {
          "required": false
        },
        "HEROKU_APP_NAME" : {
          "required": false
        }
      },
      ```

    - `environments`/`tests`/`scripts`: Specifies the scripts used to invoke CI tests. These test scripts are created automatically if they are not found locally.

      ```
      "environments": {
        "test": {
          "scripts": {
            "test-setup": ./bin/test-setup.sh",
            "test": "./bin/test.sh"
          }
        }
      },
      ```

    - `scripts`/`pre-predestroy`: Specifies the script to run when a review app is destroyed. This script is automatically generated by the buildpack, so you don't have to specify anything.

      ```
      "scripts": {
        "pr-predestroy": "./bin/delete-org.sh"
      },
      ```

2. **`sfdx.yml`**: This yaml file also provides information to the buildpack but specifically related to the Salesforce DX project. Here you can specify information related to how your app is configured and setup.

    ```
    scratch-org-def: config/project-scratch-def.json
    assign-permset: false
    permset-name:
    run-apex-tests: true
    apex-test-format: tap
    show-scratch-org-url: false
    open-path: /one/one.app#/setup/home
    import-data: false
    data-plans:
    ```

3. **sfdx-project.json**: If you are using Unlocked Packages, which is the default behavior, you'll need to ensure the required packaging data is in your `sfdx-project.json` file.

    ```
    "packageDirectories": [
    {
      "path": "force-app",
      "default": true,
      "id": "0Hoxxxxxxxxxxxx",
      "versionNumber": "1.0.0.NEXT",
      "versionName": "Release One"
    }
    ```

## Config Vars

The buildpack uses config vars associated with each Heroku App to control the build.

## For any app

- `SFDX_BUILDPACK_DEBUG`: If true, instruct the buildpack to display debug information.
- `SFDX_DEV_HUB_AUTH_URL`: Provides the credentials for connecting to the Dev Hub. You can get this value by running `sfdx force:org:display --verbose --json` against your Dev Hub and grabbing the `sfdxAuthUrl`.

### For Staging

- `SFDX_CREATE_PACKAGE_VERSION`: If true, instructs the buildpack to create a new package version from the source. 

- `SFDX_PACKAGE_NAME`: Provides the full name of the package to create and install, used to derive the package id


### For Production

- `SFDX_PROMOTE_PACKAGE_VERSION`: If true, instructs the build to promote the last built package version

- `SFDX_DEV_HUB_AUTH_URL`: Provides the credentials for connecting to the Dev Hub. You can get this value by running `sfdx force:org:display --verbose --json` against your Dev Hub and grabbing the `sfdxAuthUrl`.
