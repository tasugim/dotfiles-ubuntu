#!/usr/bin/env bash

set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

readonly DOTDIR="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd -P
)"

readonly BASE16_DIR="${HOME}/.config/base16-shell"
readonly BASE16_REPOSITORY="https://github.com/chriskempson/base16-shell.git"

# trueにするとEmacs用PPAを追加する。
# Ubuntu標準のEmacsでよければfalseに変更する。
readonly ENABLE_EMACS_PPA="${ENABLE_EMACS_PPA:-true}"

log() {
  printf '[dotfiles] %s\n' "$*"
}

error() {
  printf '[dotfiles] ERROR: %s\n' "$*" >&2
}

on_error() {
  local exit_code=$?
  error "Installation failed at line ${BASH_LINENO[0]} (exit code: ${exit_code})"
  exit "$exit_code"
}

trap on_error ERR

require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    error "Required command not found: ${command_name}"
    return 1
  fi
}

check_prerequisites() {
  require_command git
  require_command curl
  require_command sudo
  require_command dpkg-query

  if ! sudo -n true >/dev/null 2>&1; then
    error "Passwordless sudo is required."
    return 1
  fi
}

backup_existing_path() {
  local path="$1"
  local timestamp
  local backup_path

  timestamp="$(date '+%Y%m%d-%H%M%S')"
  backup_path="${path}.pre-dotfiles.${timestamp}.$$"

  log "Backing up existing path:"
  log "  ${path}"
  log "  -> ${backup_path}"

  mv -- "$path" "$backup_path"
}

create_dotfile_link() {
  local source_path="$1"
  local dotfile_name
  local target_path
  local current_link

  dotfile_name="$(basename -- "$source_path")"
  target_path="${HOME}/${dotfile_name}"

  case "$dotfile_name" in
    .git | .gitignore | .gitattributes | .gitmodules | .github)
      log "Skipping repository metadata: ${dotfile_name}"
      return 0
      ;;
  esac

  # 期待するリンクがすでに存在する場合は何もしない。
  if [[ -L "$target_path" ]]; then
    current_link="$(readlink -- "$target_path")"

    if [[ "$current_link" == "$source_path" ]]; then
      log "Link already exists: ${target_path}"
      return 0
    fi
  fi

  # 通常ファイル、ディレクトリ、異なるリンクは削除せずバックアップする。
  if [[ -e "$target_path" || -L "$target_path" ]]; then
    backup_existing_path "$target_path"
  fi

  log "Creating link: ${target_path} -> ${source_path}"
  ln --symbolic -- "$source_path" "$target_path"
}

create_dotfile_links() {
  local dotfile_path

  log "START create dotfile links"

  while IFS= read -r -d '' dotfile_path; do
    create_dotfile_link "$dotfile_path"
  done < <(
    find "$DOTDIR" \
      -mindepth 1 \
      -maxdepth 1 \
      -name '.*' \
      -print0
  )

  log "END create dotfile links"
}

package_is_installed() {
  local package="$1"

  dpkg-query \
    --show \
    --showformat='${db:Status-Abbrev}' \
    "$package" 2>/dev/null \
    | grep --quiet '^ii '
}

configure_emacs_repository() {
  if [[ "$ENABLE_EMACS_PPA" != "true" ]]; then
    log "Emacs PPA is disabled"
    return 0
  fi

  if grep \
      --recursive \
      --silent \
      --fixed-strings \
      "ppa.launchpadcontent.net/ubuntuhandbook1/emacs" \
      /etc/apt/sources.list \
      /etc/apt/sources.list.d 2>/dev/null; then
    log "Emacs PPA is already configured"
    return 0
  fi

  if ! command -v add-apt-repository >/dev/null 2>&1; then
    error "add-apt-repository is not installed."
    error "Install software-properties-common in the Dockerfile."
    return 1
  fi

  log "Adding Emacs PPA"

  sudo -n env DEBIAN_FRONTEND=noninteractive \
    add-apt-repository \
    --yes \
    ppa:ubuntuhandbook1/emacs
}

install_apt_packages() {
  local packages=(
    git
    tig
    tmux
    vim
    emacs-nox
    stow
  )

  local missing_packages=()
  local package

  for package in "${packages[@]}"; do
    if package_is_installed "$package"; then
      log "Package already installed: ${package}"
    else
      missing_packages+=("$package")
    fi
  done

  if (( ${#missing_packages[@]} == 0 )); then
    log "All required apt packages are already installed"
    return 0
  fi

  log "Updating apt package index"

  sudo -n env DEBIAN_FRONTEND=noninteractive \
    apt-get update

  log "Installing packages: ${missing_packages[*]}"

  sudo -n env DEBIAN_FRONTEND=noninteractive \
    apt-get install \
    --yes \
    --no-install-recommends \
    "${missing_packages[@]}"
}

download_file() {
  local url="$1"
  local destination="$2"
  local destination_dir
  local temporary_file

  destination_dir="$(dirname -- "$destination")"
  mkdir -p "$destination_dir"

  temporary_file="$(mktemp "${destination}.tmp.XXXXXX")"

  log "Downloading: ${url}"
  log "Destination: ${destination}"

  if ! curl \
      --fail \
      --location \
      --show-error \
      --silent \
      --retry 3 \
      --retry-delay 2 \
      --connect-timeout 15 \
      --max-time 120 \
      --output "$temporary_file" \
      "$url"; then
    rm -f -- "$temporary_file"
    error "Download failed: ${url}"
    return 1
  fi

  if [[ ! -s "$temporary_file" ]]; then
    rm -f -- "$temporary_file"
    error "Downloaded file is empty: ${url}"
    return 1
  fi

  chmod 0644 "$temporary_file"
  mv -- "$temporary_file" "$destination"
}

install_git_helpers() {
  download_file \
    "https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash" \
    "${HOME}/.git-completion.sh"

  download_file \
    "https://raw.githubusercontent.com/git/git/master/contrib/completion/git-prompt.sh" \
    "${HOME}/.git-prompt.sh"
}

install_vim_plug() {
  download_file \
    "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" \
    "${HOME}/.vim/autoload/plug.vim"
}

install_or_update_git_repository() {
  local repository="$1"
  local destination="$2"

  if [[ -d "${destination}/.git" ]]; then
    log "Updating Git repository: ${destination}"

    # ローカル変更がある場合は、安全のためpullを実行しない。
    if [[ -n "$(git -C "$destination" status --porcelain)" ]]; then
      error "Local changes found in ${destination}"
      error "Repository update was skipped."
      return 0
    fi

    git -C "$destination" fetch --prune

    if git -C "$destination" rev-parse '@{upstream}' >/dev/null 2>&1; then
      git -C "$destination" merge --ff-only '@{upstream}'
    else
      log "No upstream branch is configured for ${destination}"
      log "Fetch completed, but merge was skipped"
    fi

    return 0
  fi

  if [[ -e "$destination" ]]; then
    error "${destination} exists but is not a Git repository."
    error "Move or remove it before running this script again."
    return 1
  fi

  log "Cloning Git repository: ${repository}"
  mkdir -p "$(dirname -- "$destination")"

  git clone \
    -- \
    "$repository" \
    "$destination"
}

install_base16_shell() {
  install_or_update_git_repository \
    "$BASE16_REPOSITORY" \
    "$BASE16_DIR"
}

main() {
  log "Dotfiles installation started"

  check_prerequisites
  create_dotfile_links

  configure_emacs_repository
  install_apt_packages

  install_git_helpers
  install_vim_plug
  install_base16_shell

  log "Dotfiles installation completed successfully"
}

main "$@"
