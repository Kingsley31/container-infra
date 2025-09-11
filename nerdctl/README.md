# GHCR Login Script (`ghcr-login.sh`)

This script provides a simple and **secure** way to log in to the GitHub
Container Registry (GHCR) using `nerdctl` on any VPS.

## Why use this script?

- Automates the `nerdctl login` command so you don't have to look it
    up each time.
- Securely prompts for your GitHub Personal Access Token (PAT) without
    displaying it on screen.
- Can be reused on any new VPS server via SSH.

------------------------------------------------------------------------

## Requirements

- **nerdctl** must be installed on the VPS.
- A GitHub **Personal Access Token (PAT)** with the following scopes:
  - `read:packages` → if you only want to pull images.
  - `write:packages` → if you also want to push images.
  - `delete:packages` → optional, if you want to delete packages.

------------------------------------------------------------------------

## Installation

1. Copy the script to your VPS:

    ``` bash
    nano ghcr-login.sh
    ```

    Paste the script content, save and exit.

2. Make the script executable:

    ``` bash
    chmod +x ghcr-login.sh
    ```

------------------------------------------------------------------------

## Usage

Run the script with your GitHub username:

``` bash
./ghcr-login.sh <github-username>
```

Example:

``` bash
./ghcr-login.sh johndoe
```

The script will securely prompt you for your GitHub Personal Access
Token:

``` bash
    Enter GitHub Personal Access Token:
```

Your input will remain hidden for security.

------------------------------------------------------------------------

## Verification

After running the script, you can verify login with:

``` bash
nerdctl pull ghcr.io/<github-username>/<repository>:<tag>
```

Example:

``` bash
nerdctl pull ghcr.io/johndoe/myapp:latest
```

------------------------------------------------------------------------

## Security Notes

- The token is not stored in your shell history when using this
    script.
- Credentials are stored in `~/.config/nerdctl/config.json` (for
    rootless) or `/etc/nerdctl/config.json` (for root).
- If using on a shared VPS, make sure the config file is properly
    permissioned.

------------------------------------------------------------------------

## License

This script is free to use and modify under the MIT License.
