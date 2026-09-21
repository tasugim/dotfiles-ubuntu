#!/usr/bin/env bash

set -Eeuo pipefail

readonly DOTDIR="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd -P
)"

readonly BASE16_DIR="${HOME}/.config/base16-shell"
readonly BASE16_REPOSITORY="https://github.com/chriskempson/base16-shell.git"

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
  local commands=(
    curl
    find
    git
    mktemp
    readlink
  )

  local command_name

  for command_name in "${commands[@]}"; do
    require_command "$command_name"
  done
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

  # Gitリポジトリの管理ファイルはリンクしない。
  case "$dotfile_name" in
    .git | .gitignore | .gitattributes | .gitmodules | .github)
      log "Skipping repository metadata: ${dotfile_name}"
      return 0
      ;;
  esac

  # 期待するシンボリックリンクがすでに存在する場合は何もしない。
  if [[ -L "$target_path" ]]; then
    current_link="$(readlink -- "$target_path")"

    if [[ "$current_link" == "$source_path" ]]; then
      log "Link already exists: ${target_path}"
      return 0
    fi
  fi

  # 既存ファイル、ディレクトリ、異なるリンクは削除せず退避する。
  if [[ -e "$target_path" || -L "$target_path" ]]; then
    backup_existing_path "$target_path"
  fi

  log "Creating link: ${target_path} -> ${source_path}"

  ln \
    --symbolic \
    -- \
    "$source_path" \
    "$target_path"
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
      --retry-connrefused \
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

    # ローカル変更がある場合は、上書きせず更新をスキップする。
    if [[ -n "$(git -C "$destination" status --porcelain)" ]]; then
      log "Local changes found in ${destination}"
      log "Repository update was skipped"
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
  install_git_helpers
  install_vim_plug
  install_base16_shell

  log "Dotfiles installation completed successfully"
}

main "$@"
