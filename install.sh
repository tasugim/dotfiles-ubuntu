#!/bin/bash -e

# Install dotfiles

IGNORE_PATTERN="^\.(git)"
DOTDIR="$( cd "$( dirname "$0" )" && pwd )"

echo "START create dotfile links."
for dotfilepath in $DOTDIR/.??*; do
    DOTFILE="$(basename $dotfilepath)"
    [[ $DOTFILE =~ $IGNORE_PATTERN ]] && continue
    ln -snfv "$dotfilepath" "$HOME/$DOTFILE"
done
echo "END create dotfile links."

# Install apt packages
apt-install() {
  echo "Install $@"
  sudo apt install -y "$@"
}

sudo add-apt-repository -y ppa:ubuntuhandbook1/emacs
sudo apt update && sudo apt upgrade -y

apt-install git
apt-install tig
apt-install tmux
apt-install vim
apt-install emacs-nox
apt-install stow
# apt-install emacs-nox
# apt-install emacs-common

# git-completion and git-prompt
curl -o ~/.git-completion.sh \
    https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash
curl -o ~/.git-prompt.sh \
    https://raw.githubusercontent.com/git/git/master/contrib/completion/git-prompt.sh

# Vim
curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

# colorscheme (base16)
BASE16_DIR="$HOME/.config/base16-shell"
BASE16_REPOSITORY="https://github.com/chriskempson/base16-shell.git"

if [ -d "$BASE16_DIR/.git" ]; then
  echo "Update base16-shell"
  git -C "$BASE16_DIR" pull --ff-only
elif [ -e "$BASE16_DIR" ]; then
  echo "ERROR: $BASE16_DIR exists but is not a Git repository." >&2
  exit 1
else
  echo "Clone base16-shell"
  mkdir -p "$(dirname "$BASE16_DIR")"
  git clone "$BASE16_REPOSITORY" "$BASE16_DIR"
fi

# Rust tools
#apt-install cargo
#apt-install cmake # need to build starship
#cargo install --version 1.20.1 starship # ~>1.21.0 needs rust v1.80.0 or newer
