# Software Factory installer bootstrap

This public repository contains only the bootstrap script. The Software Factory application remains in the private `mta-tech/software-factory` repository.

Prerequisites: Git, SSH, and GitHub CLI signed in with access to the private repository. Install Claude Code first if using `--claude`.

```sh
gh auth login
bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/mta-tech/software-factory-install/v0.4.1/install.sh | sh -s -- --claude'
```

Omit `--claude` for CLI-only installation. The bootstrap installs uv if needed, selects managed Python 3.11 for the CLI and local verification, and optionally installs the Claude plugin. Open a new terminal after installation.

Worker access uses your existing VPN and ordinary SSH. The installer does not configure cloud accounts, VPN routes, SSH aliases, provider credentials, or Factory run state.

After installation:

```sh
factory --help
factory list
factory get RUN_ID
factory resume RUN_ID --follow
```

Claude commands include `/herdr-factory:init`, `/herdr-factory:work`, `/herdr-factory:jobs`, and `/herdr-factory:resume RUN_ID`. Reconnect currently requires the original computer's local state root and actor. Remote coding can continue while the client is disconnected; local review, verification, and cleanup resume when the developer returns. Cross-computer recovery codes are future work. Isolated candidate verification currently requires macOS; Linux verification fails closed.

The application source is fetched through authenticated GitHub CLI requests pinned to the private v0.4.1 tag. Tokens are not put into installer command arguments. No application code or credentials are published in this repository.
