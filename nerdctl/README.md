# GHCR Login Script (`ghcr-login.sh`)

This script provides a simple and **secure** way to log in to the GitHub
Container Registry (GHCR) using `nerdctl` on any VPS.

## 🔥 Features

- Automates the `nerdctl login` command so you don't have to remember
    it.
- Securely prompts for your GitHub Personal Access Token (PAT) (hidden
    input).
- Auto-installs required dependencies (`jq`,
    `golang-docker-credential-helpers`).
- Smartly configures a **credential helper**:
  - Uses `secretservice` if a desktop environment and DBus are
        available.
  - Falls back to `store` (works on headless VPS servers).

This ensures your credentials are never stored unencrypted in
`config.json`.

------------------------------------------------------------------------

## 🛠 Requirements

- **nerdctl** must be installed on the VPS.
- A GitHub **Personal Access Token (PAT)** with scopes:
  - `read:packages` → to pull images.
  - `write:packages` → to push images.
  - `delete:packages` → optional, to delete packages.

------------------------------------------------------------------------

## 📦 Installation

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

## 🚀 Usage

Run the script with your GitHub username:

``` bash
./ghcr-login.sh <github-username>
```

Example:

``` bash
./ghcr-login.sh johndoe
```

It will prompt:

```bash
    Enter GitHub Personal Access Token:
```

Your input will remain hidden for security.

------------------------------------------------------------------------

## 🔑 Credential Helper Behavior

- If the system has **DBus + GNOME Keyring**, the script configures:

    ``` json
    "credsStore": "secretservice"
    ```

- If running on a **headless VPS** (no DBus), it configures:

    ``` json
    "credsStore": "store"
    ```

This removes the `WARNING! Your password will be stored unencrypted...`
message.

You can verify the config with:

``` bash
cat ~/.config/nerdctl/config.json
```

------------------------------------------------------------------------

## ✅ Verification

After login, test pulling from GHCR:

``` bash
nerdctl pull ghcr.io/<github-username>/<repository>:<tag>
```

Example:

``` bash
nerdctl pull ghcr.io/johndoe/myapp:latest
```

------------------------------------------------------------------------

## 🔒 Security Notes

- Your token input is hidden when typing.
- Credentials are stored securely via a credential helper
    (`secretservice` or `store`).
- If using on a shared VPS, ensure permissions on
    `~/.config/nerdctl/config.json` are restricted.

------------------------------------------------------------------------

## 📄 License

This script is free to use and modify under the MIT License.
