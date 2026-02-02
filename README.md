# Keycloak Container Image

This repository provides a container image for running Keycloak.
The container is built on Debian 13 and includes OpenJDK 21.
Building different variants based on customer/project needs is supported.

The helm chart is built to run the container with `readOnlyRootFilesystem` enabled and puts `emptyDir`-Volumes where necessary.

## Pipeline Build and Configuration
* The keycloak version can be provided separetely for every variant in the file `variants/<KEYCLOAK_VARIANT>/env` - if the version is not set, the default version provided in `variants/base/env` is used
* Versioning of the releases:
  * A new release can be triggered by pushing to the release branch
  * The new version is generated based on conventional commits and a GitHub release and tag are created automatically
  * Helm chart version: `<git-tag>` (app version is not set)
  * image: `<keycloak-version>-<git-tag>` and `latest`

## Configuration Options

### Build Argument

* **`KEYCLOAK_VARIANT`**: Defines the variant of Keycloak to be used. This refers to a subdirectory in `variants/` which contains an env file and supports adding more files (like themes) to keycloak.
  * `generic` (default): A general-purpose variant suitable for most use cases.
  * Example: `--build-arg KEYCLOAK_VARIANT=custom`

More basic Keycloak configurations can be found at `variants/base/env`.

### Environment Variables

During the build process, environment variables (inlcuding the keycloak version) are loaded from:
* `variants/base/env`: Base environment variables common to all variants.
* `variants/<KEYCLOAK_VARIANT>/env`: Variant-specific environment variables.

These variables are used to configure Keycloak during the build process. Env vars from `base` can also be overwritten by variant env.

### Custom files

Custom files are loaded from
* `variants/base/files`: Base files common to all variants
* `variants/<KEYCLOAK_VARIANT>/files`: Variant-specific files

The files are copied to `/opt/keycloak`.

> [!TIP]
> This feature is used to deploy themes.
> To deploy a theme copy the uncompressed directory to `variants/<KEYCLOAK_VARIANT>/files/themes/<THEME_NAME>`.

## Usage

### Build the Image

To build the container image, use the following command:

```bash
podman build --build-arg KEYCLOAK_VARIANT=generic -f Dockerfile -t keycloak:dev .
```
