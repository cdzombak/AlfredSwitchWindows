# CI/CD Setup for AlfredSwitchWindows

This document describes the CI/CD pipeline setup for building, codesigning, and releasing the Swift Window Switcher Alfred workflow.

## Overview

The CI pipeline:
1. Builds the `EnumWindows` universal binary (arm64 + x86_64) using Xcode
2. Codesigns the binary with a Developer ID certificate (for releases)
3. Packages the Alfred workflow (.alfredworkflow)
4. Creates a notarized DMG for releases
5. Publishes releases to GitHub

## Prerequisites

### Apple Developer Account

You need an Apple Developer account with:
- A **Developer ID Application** certificate for codesigning
- Access to App Store Connect for notarization

### Creating the Developer ID Certificate

1. Go to [Apple Developer Certificates](https://developer.apple.com/account/resources/certificates/list)
2. Click the "+" button to create a new certificate
3. Select **Developer ID Application**
4. Follow the instructions to create a Certificate Signing Request (CSR) using Keychain Access
5. Download the certificate and install it in your keychain

### Exporting the Certificate as .p12

1. Open **Keychain Access**
2. Find your "Developer ID Application" certificate
3. Right-click and select **Export**
4. Save as `.p12` format with a strong password
5. Base64-encode the .p12 file:
   ```bash
   base64 -i certificate.p12 | pbcopy
   ```

### Getting Your Certificate ID

The certificate ID is the SHA-1 fingerprint of your signing certificate. Find it with:

```bash
security find-identity -v -p codesigning
```

Look for your "Developer ID Application" certificate and copy the 40-character hex string.

### App-Specific Password for Notarization

1. Go to [Apple ID Account](https://appleid.apple.com/account/manage)
2. Sign in with your Apple ID
3. Under "Sign-In and Security", select **App-Specific Passwords**
4. Generate a new password for "GitHub Actions Notarization"
5. Save this password securely

### Getting Your Team ID

Find your Team ID at [Apple Developer Membership](https://developer.apple.com/account/#!/membership) - it's listed as "Team ID".

## GitHub Repository Secrets

Configure these secrets in your repository settings (**Settings > Secrets and variables > Actions**):

| Secret Name | Description |
|-------------|-------------|
| `DEVID_SIGNING_CERT` | Base64-encoded .p12 certificate file |
| `DEVID_SIGNING_CERT_PASS` | Password for the .p12 certificate |
| `DEVID_SIGNING_CERT_ID` | SHA-1 fingerprint of the signing certificate (40 hex chars) |
| `KEYCHAIN_PASS` | A random password for the temporary CI keychain (generate with `openssl rand -base64 32`) |
| `NOTARIZATION_APPLE_ID` | Your Apple ID email address |
| `NOTARIZATION_TEAM_ID` | Your Apple Developer Team ID |
| `NOTARIZATION_PASS` | App-specific password for notarization |

## Workflow Triggers

The CI workflow runs on:
- **Push to `master`**: Builds and uploads artifacts (no codesigning/release)
- **Pull requests to `master`**: Builds and uploads artifacts (no codesigning/release)
- **Version tags** (e.g., `v1.0.0`): Full build, codesign, notarize, and release

### Version Tag Format

- **Release**: `v1.0.0`, `v1.2.3`
- **Pre-release**: `v1.0.0-alpha`, `v1.0.0-beta.1`, `v1.0.0-rc.1`

Pre-releases are marked as such on GitHub.

## Creating a Release

1. Ensure all changes are committed and pushed to `master`
2. Update the version in `AlfredWorkflow/info.plist` if needed (the CI will use the git tag)
3. Create and push a version tag:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```
4. The CI will automatically:
   - Build the universal binary
   - Codesign with your Developer ID
   - Package the .alfredworkflow
   - Create and notarize a DMG
   - Create a GitHub release with the DMG attached

## Local Development

### Building Locally

```bash
# Build the universal binary
make build

# Package the workflow (requires binary to be built first)
make package

# Clean build artifacts
make clean

# Do everything
make all
```

### Testing the Workflow

After running `make package`, install the workflow:

```bash
open "out/AlfredSwitchWindows-$(./.version.sh).alfredworkflow"
```

## Troubleshooting

### Codesigning Fails

- Verify your certificate is valid and not expired
- Check that `DEVID_SIGNING_CERT_ID` matches your certificate's fingerprint
- Ensure the base64 encoding of the .p12 is correct (no extra whitespace)

### Notarization Fails

- Verify your Apple ID and app-specific password are correct
- Check that your Team ID is correct
- Ensure your Developer ID certificate is valid
- Review the notarization log in the GitHub Actions output

### Build Fails

- Ensure Xcode command-line tools are installed locally
- Check that the Xcode project builds successfully in Xcode.app
- Review the build log for specific errors

