#!/usr/bin/env bash

set -Eeuo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_HELPERS_DIR="${HOME}/.local/share/git"
VIM_AUTOLOAD_DIR="${HOME}/.vim/autoload"
BASE16_DIR="${HOME}/.config/base16-shell"

log() {
  printf '[dotfiles] %s\n' "$*"
}

backup_path() {
  local path="$1"
  local timestamp
  local backup

  timestamp="$(date '+%Y%m%d-%H%M%S')"
  backup="${path}.pre-dotfiles.${timestamp}.$$"

  log "Backing up existing path:"
  log "  ${path}"
  log "  -> ${backup}"

  mv "$path" "$backup"
}

link_dotfile() {
  local relative_path="$1"
  local source_path="${DOTFILES_DIR}/${relative_path}"
  local destination_path="${HOME}/${relative_path}"
  local destination_parent

  destination_parent="$(dirname "$destination_path")"

  if [[ ! -e "$source_path" ]]; then
    log "Source does not exist; skipping: ${source_path}"
    return 0
  fi

  mkdir -p "$destination_parent"

  # すでに正しいリンクなら何もしない
  if [[ -L "$destination_path" ]] &&
     [[ "$(readlink -f "$destination_path")" == "$(readlink -f "$source_path")" ]]; then
    log "Link already exists: ${destination_path}"
    return 0
  fi

  # 通常ファイル、ディレクトリ、または別のリンクが存在する場合
  if [[ -e "$destination_path" || -L "$destination_path" ]]; then
    backup_path "$destination_path"
  fi

  log "Creating link: ${destination_path} -> ${source_path}"
  ln -s "$source_path" "$destination_path"
}

download_if_changed() {
  local url="$1"
  local destination="$2"
  local destination_parent
  local temporary_file

  destination_parent="$(dirname "$destination")"
  mkdir -p "$destination_parent"

  temporary_file="$(mktemp "${destination}.tmp.XXXXXX")"

  log "Downloading: ${url}"
  log "Destination: ${destination}"

  if ! curl --fail --silent --show-error --location \
    "$url" \
    --output "$temporary_file"; then
    rm -f "$temporary_file"
    log "Download failed: ${url}"
    return 1
  fi

  if [[ -f "$destination" ]] &&
     cmp --silent "$temporary_file" "$destination"; then
    rm -f "$temporary_file"
    log "Already up to date: ${destination}"
    return 0
  fi

  chmod 0644 "$temporary_file"
  mv "$temporary_file" "$destination"

  log "Updated: ${destination}"
}

install_dotfile_links() {
  log "START create dotfile links"

  # リポジトリから直接管理するファイルだけを明示する。
  # ダウンロード生成するファイルはここに含めない。
  local dotfiles=(
    ".bashrc"
    ".vimrc"
    ".tmux.conf"
  )

  local dotfile

  for dotfile in "${dotfiles[@]}"; do
    link_dotfile "$dotfile"
  done

  log "END create dotfile links"
}

install_git_helpers() {
  mkdir -p "$GIT_HELPERS_DIR"

  download_if_changed \
    "https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash" \
    "${GIT_HELPERS_DIR}/git-completion.bash"

  download_if_changed \
    "https://raw.githubusercontent.com/git/git/master/contrib/completion/git-prompt.sh" \
    "${GIT_HELPERS_DIR}/git-prompt.sh"
}

install_vim_plug() {
  download_if_changed \
    "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" \
    "${VIM_AUTOLOAD_DIR}/plug.vim"
}

install_base16_shell() {
  mkdir -p "$(dirname "$BASE16_DIR")"

  if [[ -d "${BASE16_DIR}/.git" ]]; then
    log "Updating Git repository: ${BASE16_DIR}"
    git -C "$BASE16_DIR" pull --ff-only
  elif [[ -e "$BASE16_DIR" ]]; then
    log "Path exists but is not a Git repository: ${BASE16_DIR}"
    log "Skipping base16-shell installation"
  else
    log "Cloning base16-shell: ${BASE16_DIR}"
    git clone \
      "https://github.com/chriskempson/base16-shell.git" \
      "$BASE16_DIR"
  fi
}

main() {
  log "Dotfiles installation started"

  install_dotfile_links
  install_git_helpers
  install_vim_plug
  install_base16_shell

  log "Dotfiles installation completed successfully"
}

main "$@"
