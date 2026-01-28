# Install instructions

First, clone the repo with the completion scripts:
```sh
git clone https://github.com/capezotte/s6-shell-completion
```

## Bash

Add `. "$path_to/s6-shell-completion/bash/s6-rc.bash"` the end of your .bashrc.

## Zsh

```sh
mkdir -p ~/.local/share/zsh/functions
ln -s "$PWD/zsh/"* ~/.local/share/zsh/functions/s6-rc
```

and restart zsh.

# Will it work on distro X?

Tested on a stock Artix s6 configuration, and a Gentoo install with a custom
s6 repository.

This scripts goes quite far to ensure it is distribution-agnostic and respects
compiled-in distro defaults with as few assumptions as possible.
