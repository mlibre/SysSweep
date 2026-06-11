#!/bin/bash

set -uo pipefail

# ============================================================================
# SysSweep — Safe Linux system cleanup script
# ============================================================================

VERSION="2.1.1"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR=$(eval echo "~$REAL_USER")
LOG_DIR="${HOME_DIR}/.local/share"
LOG_FILE="${LOG_DIR}/syssweep.log"
DRY_RUN=false
SKIPPED=()

# ===== Output helpers =====

print_section() {
    echo
    echo "══════════════════════════════════════════════════════"
    echo "  $1"
    echo "══════════════════════════════════════════════════════"
}

# ── Root check ───────────────────────────────────────────────────────────────

ensure_root() {
	if [[ "$EUID" -ne 0 ]]; then
		echo -e "\e[33mThis script needs root privileges. Re-running with sudo...\e[0m"
		exec sudo "$0" "$@"
	fi
}

# ── CLI ──────────────────────────────────────────────────────────────────────

show_help() {
	cat <<EOF
SysSweep v${VERSION} — Safe Linux system cleanup

Usage: sudo ./syssweep.bash [OPTIONS]

Options:
  --dry-run          Show what would be deleted without deleting
  --skip <function>  Skip a cleanup function (repeatable)
                     Available: temp, trash, dangling, tmpfiles, journal,
                                flatpak, docker, dockerbuilder, pacman, pamac, apt,
                                pkgcache, kernels, python, npm, yarn, cargo,
                                go, snap, mesa, fontconfig, coredumps, electron,
                                buildtools, oldlogs, swaps, tex, locate,
                                browser, pnpm, bun, deno, ruby, composer,
                                poetry, pipenv, conda, wine, gitgc, apport,
                                firefox, debpartial, sysdcache
  --help             Show this help message
  --version          Show version

Examples:
  sudo ./syssweep.bash                     # Run all cleanups
  sudo ./syssweep.bash --dry-run           # Preview only
  sudo ./syssweep.bash --skip docker       # Skip Docker cleanup
  sudo ./syssweep.bash --skip pacman --skip apt  # Skip multiple
EOF
	exit 0
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--dry-run)
			DRY_RUN=true
			shift
			;;
		--skip)
			if [[ -z "${2:-}" ]]; then
				echo "Error: --skip requires a function name" >&2
				echo "Run with --help for available functions" >&2
				exit 1
			fi
			SKIPPED+=("$2")
			shift 2
			;;
		--help) show_help ;;
		--version)
			echo "SysSweep v${VERSION}"
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			echo "Run with --help for usage" >&2
			exit 1
			;;
		esac
	done
}

# ── Helpers ──────────────────────────────────────────────────────────────────

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

is_skipped() {
	local fn="$1"
	for s in "${SKIPPED[@]+"${SKIPPED[@]}"}"; do
		[[ "$s" == "$fn" ]] && return 0
	done
	return 1
}

log() {
	local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
	echo "$msg" >>"$LOG_FILE"
}

print_header() {
	print_section "$1"
}

print_status() {
    case "$2" in
        ok)   echo "  ✓ $1" ;;
        warn) echo "  ⚠ $1" ;;
        err)  echo "  ✗ $1" ;;
        info) echo "  • $1" ;;
        skip) echo "  ⏭ $1 (skipped)" ;;
        dry)  echo "  🔍 $1 (would delete)" ;;
    esac
}

size_of() {
	local path="$1" result
	result=$( (du -sh "$path" 2>/dev/null || true) | head -1 | awk '{print $1}' )
	echo "${result:-0}"
}

disk_used_kb() {
	df -Pk "$1" | awk 'NR==2 {print $3}'
}

format_bytes() {
	local kb="${1:-0}"
	if (( kb >= 1073741824 )); then
		awk -v kb="$kb" 'BEGIN { printf "%.1f TiB", kb/1073741824 }'
	elif (( kb >= 1048576 )); then
		awk -v kb="$kb" 'BEGIN { printf "%.1f GiB", kb/1048576 }'
	elif (( kb >= 1024 )); then
		awk -v kb="$kb" 'BEGIN { printf "%.1f MiB", kb/1024 }'
	else
		printf "%s KiB" "$kb"
	fi
}

confirm() {
	local prompt="${1:-Continue?}"
	if $DRY_RUN; then
		return 0
	fi
	echo -en "\e[1;33m${prompt} [Y/n]: \e[0m"
	read -r reply
	[[ -z "$reply" || "$reply" =~ ^[Yy] ]]
}

# ── Cleanup Functions ────────────────────────────────────────────────────────

clean_temp_directories() {
	if is_skipped "temp"; then
		print_status "Temporary directories" skip
		return
	fi

	print_header "Cleaning temporary directories"
	log "Starting temp directory cleanup"

	if $DRY_RUN; then
		print_status "/tmp — would remove ~$(size_of /tmp)" dry
		print_status "/var/tmp — would remove ~$(size_of /var/tmp)" dry
	else
		# Clean /tmp — only files older than 1 day
		local tmp_size=$(size_of /tmp)
		local tmp_before=$( (find /tmp -mindepth 1 -maxdepth 1 -mtime +1 2>/dev/null || true) | wc -l)
		if [[ "$tmp_before" -gt 0 ]]; then
			sudo find /tmp -mindepth 1 -maxdepth 1 -mtime +1 -exec rm -rf {} + 2>/dev/null || true
			print_status "Removed old files from /tmp (~${tmp_size})" ok
			log "Removed ${tmp_before} old files from /tmp"
		else
			print_status "/tmp — nothing old enough to remove" ok
		fi

		# Clean /var/tmp
		local vartmp_size=$(size_of /var/tmp)
		local vartmp_before=$( (find /var/tmp -mindepth 1 -maxdepth 1 -mtime +1 2>/dev/null || true) | wc -l)
		if [[ "$vartmp_before" -gt 0 ]]; then
			sudo find /var/tmp -mindepth 1 -maxdepth 1 -mtime +1 -exec rm -rf {} + 2>/dev/null || true
			print_status "Removed old files from /var/tmp (~${vartmp_size})" ok
			log "Removed ${vartmp_before} old files from /var/tmp"
		else
			print_status "/var/tmp — nothing old enough to remove" ok
		fi

		# Clean user & root trash
		for trash_dir in \
			"${HOME_DIR}/.local/share/Trash/files" \
			"${HOME_DIR}/.local/share/Trash/info" \
			"/root/.local/share/Trash/files" \
			"/root/.local/share/Trash/info"; do
			if [[ -d "$trash_dir" ]]; then
				local count=$(find "$trash_dir" -mindepth 1 2>/dev/null | wc -l)
				if [[ $count -gt 0 ]]; then
					sudo rm -rf "${trash_dir:?}"/* 2>/dev/null || true
					print_status "Cleared ${trash_dir}" ok
					log "Cleared ${trash_dir}"
				fi
			fi
		done

		# Clean npm cache directories (both user and root)
		for npm_dir in "${HOME_DIR}/.npm" "/root/.npm"; do
			if [[ -d "$npm_dir" ]]; then
				local npm_size=$(size_of "$npm_dir")
				sudo rm -rf "${npm_dir:?}" 2>/dev/null || true
				print_status "Removed ${npm_dir} (~${npm_size})" ok
				log "Removed ${npm_dir}"
			fi
		done

		# Clean KDE thumbnail caches
		while IFS= read -r -d '' dir; do
			sudo rm -rf "${dir}" 2>/dev/null || true
			print_status "Removed ${dir}" ok
			log "Removed ${dir}"
		done < <(find "${HOME_DIR}"/.cache /root/.cache -maxdepth 1 -name 'ksycoca5*' -print0 2>/dev/null)

		# Clean thumbnail cache (user)
		local thumb_size=$(size_of "${HOME_DIR}/.cache/thumbnails")
		if [[ -n "$thumb_size" && "$thumb_size" != "0" ]]; then
			sudo rm -rf "${HOME_DIR}/.cache/thumbnails/"* 2>/dev/null || true
			print_status "Cleared thumbnail cache (~${thumb_size})" ok
			log "Cleared thumbnail cache"
		fi
	fi
}

# FIXED 1: safe dangling symlink cleanup
clean_dangling_symlinks() {
	if is_skipped "dangling"; then
		print_status "Dangling symlinks" skip
		return
	fi

	print_header "Cleaning dangling symlinks"
	log "Starting dangling symlink cleanup"

	local total=0
	local search_paths=("${HOME_DIR}" "/root")

	for spath in "${search_paths[@]}"; do
		[[ -d "$spath" ]] || continue

		local count=$(find "$spath" -maxdepth 6 -xtype l 2>/dev/null | wc -l)
		if [[ $count -gt 0 ]]; then
			if $DRY_RUN; then
				print_status "${count} dangling symlinks would be removed from ${spath}" dry
			else
				find "$spath" -maxdepth 6 -xtype l -delete 2>/dev/null || true
				print_status "Removed ${count} dangling symlinks from ${spath}" ok
				log "Removed ${count} dangling symlinks from ${spath}"
			fi
			total=$((total + count))
		fi
	done

	if [[ $total -eq 0 ]]; then
		print_status "No dangling symlinks found in user directories" ok
	fi
}

clean_systemd_tmpfiles() {
	if is_skipped "tmpfiles"; then
		print_status "systemd tmpfiles" skip
		return
	fi

	if ! command_exists systemd-tmpfiles; then
		print_status "systemd-tmpfiles not found" warn
		return
	fi

	print_header "Cleaning systemd tmpfiles"
	log "Starting systemd tmpfiles cleanup"

	if $DRY_RUN; then
		print_status "systemd-tmpfiles --clean would be run" dry
	else
		systemd-tmpfiles --clean 2>/dev/null || true
		print_status "Cleaned systemd tmpfiles" ok
		log "Cleaned systemd tmpfiles"
	fi
}

clean_trash_folders() {
	if is_skipped "trash"; then
		print_status ".Trash folders" skip
		return
	fi

	print_header "Cleaning .Trash folders on mounted devices"
	log "Starting .Trash cleanup"

	local mounted_devices
	mounted_devices=$(df -h | awk 'NR > 1 {print $NF}')

	while IFS= read -r mount_point; do
		[[ "$mount_point" == /proc || "$mount_point" == /sys || "$mount_point" == /dev ]] && continue
		[[ "$mount_point" == /run* ]] && continue

		local trash_count=0
		for trash_dir in "${mount_point}"/.Trash-*; do
			[[ -d "$trash_dir" ]] || continue
			trash_count=$((trash_count + 1))
		done

		if [[ $trash_count -gt 0 ]]; then
			if $DRY_RUN; then
				for trash_dir in "${mount_point}"/.Trash-*; do
					[[ -d "$trash_dir" ]] || continue
					print_status "${trash_dir} (~$(size_of "$trash_dir"))" dry
				done
			else
				for trash_dir in "${mount_point}"/.Trash-*; do
					[[ -d "$trash_dir" ]] || continue
					local s=$(size_of "$trash_dir")
					sudo rm -rf "${trash_dir:?}" 2>/dev/null || true
					print_status "Removed ${trash_dir} (~${s})" ok
					log "Removed ${trash_dir}"
				done
			fi
		fi
	done <<<"$mounted_devices"
}

clean_journal_logs() {
	if is_skipped "journal"; then
		print_status "Journal logs" skip
		return
	fi

	if ! command_exists journalctl; then
		print_status "journalctl not found" warn
		return
	fi

	print_header "Cleaning journal logs"
	log "Starting journal cleanup"

	if $DRY_RUN; then
		local current_size
		current_size=$(journalctl --disk-usage 2>/dev/null | grep -oP '[\d.]+[GMK]' || echo "?")
		print_status "Current journal size: ${current_size} — would vacuum to 3 days" dry
	else
		local before_size
		before_size=$(journalctl --disk-usage 2>/dev/null | grep -oP '[\d.]+[GMK]' || echo "0")
		sudo journalctl --flush --vacuum-time=3d 2>/dev/null || true
		journalctl --user --flush --vacuum-time=3d 2>/dev/null || true
		local after_size
		after_size=$(journalctl --disk-usage 2>/dev/null | grep -oP '[\d.]+[GMK]' || echo "0")
		print_status "Journal: ${before_size} → ${after_size}" ok
		log "Journal vacuumed: ${before_size} → ${after_size}"
	fi
}

clean_flatpak_cache() {
	if is_skipped "flatpak"; then
		print_status "Flatpak" skip
		return
	fi

	if ! command_exists flatpak; then
		print_status "flatpak not found" warn
		return
	fi

	print_header "Cleaning Flatpak"
	log "Starting Flatpak cleanup"

	if $DRY_RUN; then
		local unused
		unused=$(flatpak uninstall --unused --dry-run 2>/dev/null | grep -c "Will be removed" || echo "0")
		print_status "${unused} unused Flatpak runtimes would be removed" dry
	else
		flatpak uninstall --unused -y 2>/dev/null || true
		print_status "Removed unused Flatpak runtimes" ok
		log "Cleaned Flatpak unused runtimes"
	fi
}

clean_docker() {
	if is_skipped "docker"; then
		print_status "Docker" skip
		return
	fi

	if ! command_exists docker; then
		print_status "docker not found" warn
		return
	fi

	print_header "Cleaning Docker"
	log "Starting Docker cleanup"

	if $DRY_RUN; then
		local dangling
		dangling=$(docker images -f "dangling=true" -q 2>/dev/null | wc -l)
		print_status "${dangling} dangling images would be removed" dry
		dangling=$(docker volume ls -f "dangling=true" -q 2>/dev/null | wc -l)
		print_status "${dangling} dangling volumes would be removed" dry
	else
		docker system prune -af 2>/dev/null || true
		docker volume prune -f 2>/dev/null || true
		print_status "Pruned Docker images, containers, networks, and volumes" ok
		log "Docker system prune completed"
	fi
}

clean_docker_builder_cache() {
	if is_skipped "dockerbuilder"; then
		print_status "Docker builder cache" skip
		return
	fi

	if ! command_exists docker; then
		print_status "docker not found" warn
		return
	fi

	if ! docker info >/dev/null 2>&1; then
		print_status "Docker daemon is not reachable" warn
		return
	fi

	print_header "Cleaning Docker builder cache"
	log "Starting Docker builder cache cleanup"

	if $DRY_RUN; then
		print_status "docker builder prune --all --force would be run" dry
	else
		docker builder prune --all --force 2>/dev/null || true
		print_status "Cleaned Docker builder cache" ok
		log "Cleaned Docker builder cache"
	fi
}

clean_pacman_cache() {
	if is_skipped "pacman"; then
		print_status "Pacman cache" skip
		return
	fi

	if ! command_exists paccache; then
		print_status "paccache not found (not Arch-based?)" warn
		return
	fi

	print_header "Cleaning Pacman cache"
	log "Starting Pacman cache cleanup"

	if $DRY_RUN; then
		print_status "Would remove all cached packages except latest 2" dry
		print_status "Would remove all cached packages for uninstalled versions" dry
		local orphan_list
		orphan_list=$(pacman -Qdtq 2>/dev/null || true)
		if [[ -n "$orphan_list" ]]; then
			local orphan_count
			orphan_count=$(echo "$orphan_list" | wc -l)
			print_status "${orphan_count} orphaned packages would be removed: $(echo "$orphan_list" | tr '\n' ' ')" dry
		else
			print_status "No orphaned packages found" ok
		fi
	else
		# Keep latest 2 versions of installed packages
		sudo paccache -r 2>/dev/null || true
		print_status "Removed cached packages (kept latest 2)" ok

		# Remove ALL cached versions of uninstalled packages
		sudo paccache -ruk0 2>/dev/null || true
		print_status "Removed all cached versions of uninstalled packages" ok

		# Remove orphaned packages
		local orphans
		orphans=$(pacman -Qdtq 2>/dev/null || true)
		if [[ -n "$orphans" ]]; then
			echo "$orphans" | sudo pacman -Rns - 2>/dev/null || true
			print_status "Removed orphaned packages" ok
			log "Removed orphaned packages"
		else
			print_status "No orphaned packages found" ok
		fi
	fi
}

clean_pamac_cache() {
	if is_skipped "pamac"; then
		print_status "Pamac" skip
		return
	fi

	if ! command_exists pamac; then
		print_status "pamac not found" warn
		return
	fi

	print_header "Cleaning Pamac cache"
	log "Starting Pamac cleanup"

	if $DRY_RUN; then
		print_status "Would clean Pamac cache" dry
	else
		sudo pamac clean --keep 0 --no-confirm 2>/dev/null || true
		print_status "Cleaned Pamac cache" ok
		log "Pamac cache cleaned"
	fi
}

clean_apt_cache() {
	if is_skipped "apt"; then
		print_status "APT cache" skip
		return
	fi

	if ! command_exists apt && ! command_exists apt-get; then
		print_status "apt/apt-get not found (not Debian-based?)" warn
		return
	fi

	print_header "Cleaning APT cache"
	log "Starting APT cache cleanup"

	if $DRY_RUN; then
		print_status "APT cache (~$(size_of /var/cache/apt/archives)) would be cleaned" dry
	else
		if command_exists apt; then
			sudo apt autoremove --purge -y 2>/dev/null || true
			sudo apt clean 2>/dev/null || true
			print_status "Cleaned apt cache" ok
		fi

		if command_exists apt-get; then
			sudo apt-get autoremove --purge -y 2>/dev/null || true
			sudo apt-get clean 2>/dev/null || true
			sudo apt-get autoclean 2>/dev/null || true
			print_status "Cleaned apt-get cache" ok
		fi

		log "APT cache cleanup completed"
	fi
}

clean_package_manager_caches() {
	if is_skipped "pkgcache"; then
		print_status "Package manager caches" skip
		return
	fi

	print_header "Cleaning package manager caches"
	log "Starting package manager cache cleanup"

	local cleaned=0

	if command_exists dnf; then
		if $DRY_RUN; then
			print_status "dnf clean all would be run" dry
		else
			sudo dnf clean all 2>/dev/null || true
			print_status "Cleaned DNF cache" ok
			log "Cleaned DNF cache"
		fi
		cleaned=$((cleaned + 1))
	fi

	if command_exists zypper; then
		if $DRY_RUN; then
			print_status "zypper clean --all would be run" dry
		else
			sudo zypper clean --all 2>/dev/null || true
			print_status "Cleaned Zypper cache" ok
			log "Cleaned Zypper cache"
		fi
		cleaned=$((cleaned + 1))
	fi

	if command_exists apk; then
		if $DRY_RUN; then
			print_status "apk cache clean would be run" dry
		else
			sudo apk cache clean 2>/dev/null || true
			print_status "Cleaned Alpine package cache" ok
			log "Cleaned Alpine package cache"
		fi
		cleaned=$((cleaned + 1))
	fi

	if command_exists brew; then
		if $DRY_RUN; then
			print_status "brew cleanup would be run" dry
		else
			brew cleanup 2>/dev/null || true
			print_status "Cleaned Homebrew cache" ok
			log "Cleaned Homebrew cache"
		fi
		cleaned=$((cleaned + 1))
	fi

	if [[ $cleaned -eq 0 ]]; then
		print_status "No extra package manager caches found" ok
	fi
}

clean_old_kernels() {
	if is_skipped "kernels"; then
		print_status "Old kernels" skip
		return
	fi

	print_header "Cleaning old kernels"
	log "Starting old kernel cleanup"

	if command_exists dpkg-query && command_exists apt-get; then
		local current_kernel current_kernel_stem package suffix packages=()
		current_kernel=$(uname -r)
		current_kernel_stem="${current_kernel%-generic}"

		while IFS= read -r package; do
			[[ -z "$package" ]] && continue

			case "$package" in
			linux-image-unsigned-*)
				suffix="${package#linux-image-unsigned-}"
				;;
			linux-image-*|linux-headers-*)
				suffix="${package#linux-image-}"
				[[ "$suffix" == "$package" ]] && suffix="${package#linux-headers-}"
				;;
			*) continue ;;
			esac

			case "$suffix" in
			generic|generic-*|lowlatency|lowlatency-*|rt-*|aws|aws-*|azure|azure-*|gcp|gcp-*|oracle|oracle-*)
				continue
				;;
			esac

			if [[ "$suffix" != "$current_kernel" && "$suffix" != "$current_kernel_stem" ]]; then
				packages+=("$package")
			fi
		done < <(dpkg-query -W -f='${binary:Package}\n' 'linux-image-*' 'linux-headers-*' 2>/dev/null || true)

		if ((${#packages[@]} > 0)); then
			if $DRY_RUN; then
				print_status "Old kernel packages would be removed: ${packages[*]}" dry
				sudo apt-get --dry-run purge -y "${packages[@]}" 2>/dev/null || true
			else
				sudo apt-get purge -y "${packages[@]}" 2>/dev/null || true
				print_status "Removed ${#packages[@]} old kernel packages" ok
				log "Removed ${#packages[@]} old kernel packages"
			fi
		else
			print_status "No old kernel packages found" ok
		fi
	elif command_exists dnf && command_exists rpm; then
		local old_kernels
		old_kernels=$(dnf repoquery --installonly --latest-limit=2 -q 2>/dev/null || true)

		if [[ -n "$old_kernels" ]]; then
			if $DRY_RUN; then
				print_status "Old kernel packages would be removed: $(echo "$old_kernels" | tr '\n' ' ')" dry
			else
				sudo dnf remove -y $old_kernels 2>/dev/null || true
				print_status "Removed old kernel packages" ok
				log "Removed old kernel packages"
			fi
		else
			print_status "No old kernel packages found" ok
		fi
	elif command_exists zypper; then
		if $DRY_RUN; then
			print_status "zypper remove-old-kernels would be run" dry
		else
			sudo zypper remove-old-kernels 2>/dev/null || true
			print_status "Removed old kernels" ok
			log "Removed old kernels"
		fi
	else
		print_status "Old kernel cleanup not supported on this package manager" warn
	fi
}

clean_python_cache() {
	if is_skipped "python"; then
		print_status "Python/pip" skip
		return
	fi

	print_header "Cleaning Python caches"
	log "Starting Python cache cleanup"

	if $DRY_RUN; then
		if command_exists pip; then
			local user_pip
			user_pip=$(sudo -u "$REAL_USER" pip cache dir 2>/dev/null || echo "${HOME_DIR}/.cache/pip")
			local root_pip
			root_pip=$(pip cache dir 2>/dev/null || echo "/root/.cache/pip")
			print_status "User pip cache (~$(size_of "$user_pip")) would be purged" dry
			print_status "Root pip cache (~$(size_of "$root_pip")) would be purged" dry
		fi

		local pycache_count
		pycache_count=$(find "${HOME_DIR}" -name '__pycache__' -type d 2>/dev/null | wc -l)
		if [[ $pycache_count -gt 0 ]]; then
			print_status "${pycache_count} __pycache__ directories would be removed from ${HOME_DIR}" dry
		fi
		pycache_count=$(find /root -name '__pycache__' -type d 2>/dev/null | wc -l)
		if [[ $pycache_count -gt 0 ]]; then
			print_status "${pycache_count} __pycache__ directories would be removed from /root" dry
		fi
	else
		if command_exists pip; then
			sudo -u "$REAL_USER" pip cache purge 2>/dev/null || true
			print_status "Purged pip cache (user)" ok
			pip cache purge 2>/dev/null || true
			print_status "Purged pip cache (root)" ok
			log "Purged pip cache (user + root)"
		fi

		# Remove __pycache__ dirs in user space and root space
		local pycache_count
		pycache_count=$(find "${HOME_DIR}" -name '__pycache__' -type d 2>/dev/null | wc -l)
		if [[ $pycache_count -gt 0 ]]; then
			find "${HOME_DIR}" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
			print_status "Removed ${pycache_count} __pycache__ directories from ${HOME_DIR}" ok
			log "Removed ${pycache_count} __pycache__ dirs from ${HOME_DIR}"
		fi
		pycache_count=$(find /root -name '__pycache__' -type d 2>/dev/null | wc -l)
		if [[ $pycache_count -gt 0 ]]; then
			find /root -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
			print_status "Removed ${pycache_count} __pycache__ directories from /root" ok
			log "Removed ${pycache_count} __pycache__ dirs from /root"
		fi
	fi
}

clean_npm_cache() {
	if is_skipped "npm"; then
		print_status "npm" skip
		return
	fi

	if ! command_exists npm; then
		print_status "npm not found" warn
		return
	fi

	print_header "Cleaning npm cache"
	log "Starting npm cache cleanup"

	if $DRY_RUN; then
		local user_cache
		user_cache=$(sudo -u "$REAL_USER" npm config get cache 2>/dev/null || echo "${HOME_DIR}/.npm")
		local root_cache
		root_cache=$(npm config get cache 2>/dev/null || echo "/root/.npm")
		print_status "User npm cache (~$(size_of "$user_cache")) would be cleaned" dry
		print_status "Root npm cache (~$(size_of "$root_cache")) would be cleaned" dry
	else
		sudo -u "$REAL_USER" npm cache clean --force 2>/dev/null || true
		print_status "Cleaned npm cache (user)" ok
		npm cache clean --force 2>/dev/null || true
		print_status "Cleaned npm cache (root)" ok
		log "npm cache cleaned (user + root)"
	fi
}

clean_yarn_cache() {
	if is_skipped "yarn"; then
		print_status "yarn" skip
		return
	fi

	if ! command_exists yarn; then
		print_status "yarn not found" warn
		return
	fi

	print_header "Cleaning yarn cache"
	log "Starting yarn cache cleanup"

	if $DRY_RUN; then
		local user_yarn
		user_yarn=$(sudo -u "$REAL_USER" yarn cache dir 2>/dev/null || echo "${HOME_DIR}/.cache/yarn")
		local root_yarn
		root_yarn=$(yarn cache dir 2>/dev/null || echo "/root/.cache/yarn")
		if [[ -d "$user_yarn" ]]; then
			print_status "User yarn cache (~$(size_of "$user_yarn")) would be cleaned" dry
		fi
		if [[ -d "$root_yarn" ]]; then
			print_status "Root yarn cache (~$(size_of "$root_yarn")) would be cleaned" dry
		fi
	else
		sudo -u "$REAL_USER" yarn cache clean 2>/dev/null || true
		print_status "Cleaned yarn cache (user)" ok
		yarn cache clean 2>/dev/null || true
		print_status "Cleaned yarn cache (root)" ok
		log "yarn cache cleaned (user + root)"
	fi
}

clean_cargo_cache() {
	if is_skipped "cargo"; then
		print_status "Cargo" skip
		return
	fi

	if ! command_exists cargo; then
		print_status "cargo not found" warn
		return
	fi

	print_header "Cleaning Cargo cache"
	log "Starting Cargo cache cleanup"

	local user_cargo="${HOME_DIR}/.cargo"
	local root_cargo="/root/.cargo"

	if $DRY_RUN; then
		if [[ -d "${user_cargo}/registry" ]]; then
			print_status "User Cargo registry (~$(size_of "${user_cargo}/registry")) would be cleaned" dry
		fi
		if [[ -d "${root_cargo}/registry" ]]; then
			print_status "Root Cargo registry (~$(size_of "${root_cargo}/registry")) would be cleaned" dry
		fi
	else
		if [[ -d "${user_cargo}/registry/cache" ]]; then
			sudo rm -rf "${user_cargo}/registry/cache/"* 2>/dev/null || true
			print_status "Cleaned Cargo cache (user)" ok
		fi
		if [[ -d "${root_cargo}/registry/cache" ]]; then
			sudo rm -rf "${root_cargo}/registry/cache/"* 2>/dev/null || true
			print_status "Cleaned Cargo cache (root)" ok
		fi
		log "Cargo cache cleaned (user + root)"
	fi
}

clean_go_cache() {
	if is_skipped "go"; then
		print_status "Go" skip
		return
	fi

	if ! command_exists go; then
		print_status "go not found" warn
		return
	fi

	print_header "Cleaning Go cache"
	log "Starting Go cache cleanup"

	if $DRY_RUN; then
		local user_go="${HOME_DIR}/.cache/go-build"
		local root_go="/root/.cache/go-build"
		if [[ -d "$user_go" ]]; then
			print_status "User Go build cache (~$(size_of "$user_go")) would be cleaned" dry
		fi
		if [[ -d "$root_go" ]]; then
			print_status "Root Go build cache (~$(size_of "$root_go")) would be cleaned" dry
		fi
	else
		sudo -u "$REAL_USER" go clean -cache 2>/dev/null || true
		print_status "Cleaned Go build cache (user)" ok
		go clean -cache 2>/dev/null || true
		print_status "Cleaned Go build cache (root)" ok
		log "Go cache cleaned (user + root)"
	fi
}

clean_snap_cache() {
	if is_skipped "snap"; then
		print_status "Snap" skip
		return
	fi

	if ! command_exists snap; then
		print_status "snap not found" warn
		return
	fi

	print_header "Cleaning Snap cache"
	log "Starting Snap cleanup"

	if $DRY_RUN; then
		print_status "Would remove old snap revisions" dry
	else
		# Remove disabled (old) revisions safely
		snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | \
			while read -r snapname revision; do
				sudo snap remove "$snapname" --revision="$revision" 2>/dev/null || true
			done
		print_status "Removed old snap revisions" ok

		# Clean snap thumbnail caches
		sudo rm -rf /var/snapd/cache/*.snap 2>/dev/null || true
		sudo rm -rf "${HOME_DIR}/snap/"*/common/.cache/thumbnails/* 2>/dev/null || true
		log "Snap cache cleaned"
	fi
}

clean_mesa_shader_cache() {
	if is_skipped "mesa"; then
		print_status "Mesa shader cache" skip
		return
	fi

	print_header "Cleaning Mesa shader cache"
	log "Starting Mesa shader cache cleanup"

	local mesa_dirs=(
		"${HOME_DIR}/.cache/mesa_shader_cache"
		"/root/.cache/mesa_shader_cache"
	)

	for dir in "${mesa_dirs[@]}"; do
		if [[ -d "$dir" ]]; then
			if $DRY_RUN; then
				print_status "${dir} (~$(size_of "$dir")) would be cleaned" dry
			else
				local s=$(size_of "$dir")
				sudo rm -rf "${dir:?}"/* 2>/dev/null || true
				print_status "Cleared ${dir} (~${s})" ok
				log "Cleared ${dir}"
			fi
		fi
	done
}

# FIXED 8: fontconfig cache rebuild for both user and root
clean_fontconfig_cache() {
	if is_skipped "fontconfig"; then
		print_status "Fontconfig cache" skip
		return
	fi

	print_header "Cleaning fontconfig cache"
	log "Starting fontconfig cache cleanup"

	local fontconfig_dirs=(
		"${HOME_DIR}/.cache/fontconfig"
		"/root/.cache/fontconfig"
	)

	for dir in "${fontconfig_dirs[@]}"; do
		if [[ -d "$dir" ]]; then
			if $DRY_RUN; then
				print_status "${dir} (~$(size_of "$dir")) would be cleaned" dry
			else
				local s=$(size_of "$dir")
				sudo rm -rf "${dir:?}"/* 2>/dev/null || true
				print_status "Cleared ${dir} (~${s})" ok
				log "Cleared ${dir}"
			fi
		fi
	done

	# Rebuild font cache for real user and root
	if ! $DRY_RUN && command_exists fc-cache; then
		sudo -u "$REAL_USER" fc-cache -f 2>/dev/null || true
		print_status "Rebuilt font cache (user)" ok
		fc-cache -f 2>/dev/null || true
		print_status "Rebuilt font cache (root)" ok
	fi
}

clean_core_dumps() {
	if is_skipped "coredumps"; then
		print_status "Core dumps" skip
		return
	fi

	print_header "Cleaning core dumps"
	log "Starting core dump cleanup"

	local coredump_dir="/var/lib/systemd/coredump"
	if [[ -d "$coredump_dir" ]]; then
		if $DRY_RUN; then
			print_status "Core dumps (~$(size_of "$coredump_dir")) would be removed" dry
		else
			sudo rm -rf "${coredump_dir:?}"/* 2>/dev/null || true
			print_status "Removed systemd core dumps" ok
			log "Removed core dumps"
		fi
	fi

	local crash_dir="/var/crash"
	if [[ -d "$crash_dir" ]]; then
		if $DRY_RUN; then
			print_status "Crash dumps (~$(size_of "$crash_dir")) would be removed" dry
		else
			sudo find "$crash_dir" -type f -mtime +1 -delete 2>/dev/null || true
			print_status "Removed old crash dumps" ok
			log "Removed crash dumps"
		fi
	fi
}

clean_electron_caches() {
	if is_skipped "electron"; then
		print_status "Electron app caches" skip
		return
	fi

	print_header "Cleaning Electron app caches"
	log "Starting Electron cache cleanup"

	local -A electron_apps=(
		["VSCode"]="${HOME_DIR}/.cache/vscode"
		["Discord"]="${HOME_DIR}/.cache/discord"
		["Slack"]="${HOME_DIR}/.cache/Slack"
		["Spotify"]="${HOME_DIR}/.cache/spotify"
		["Element"]="${HOME_DIR}/.cache/element"
		["Signal"]="${HOME_DIR}/.cache/Signal"
	)

	local -A electron_apps_config=(
		["VSCode"]="${HOME_DIR}/.config/Code"
		["Discord"]="${HOME_DIR}/.config/discord"
		["Slack"]="${HOME_DIR}/.config/Slack"
	)

	local all_dirs=()
	for cache_base in "${electron_apps[@]}" "${electron_apps_config[@]}"; do
		if [[ -d "$cache_base" ]]; then
			all_dirs+=("$cache_base")
		fi
	done

	for app_cache in "${all_dirs[@]}"; do
		for cache_subdir in Cache "Code Cache" GPUCache; do
			while IFS= read -r -d '' d; do
				if $DRY_RUN; then
					print_status "${d} (~$(size_of "$d")) would be cleaned" dry
				else
					sudo rm -rf "${d:?}"/* 2>/dev/null || true
					print_status "Cleared ${d}" ok
					log "Cleared ${d}"
				fi
			done < <(find "$app_cache" -maxdepth 3 -type d -name "$cache_subdir" -print0 2>/dev/null)
		done
	done
}

clean_build_tool_caches() {
	if is_skipped "buildtools"; then
		print_status "Build tool caches" skip
		return
	fi

	print_header "Cleaning build tool caches"
	log "Starting build tool cache cleanup"

	local -A build_caches=(
		["User Gradle"]="${HOME_DIR}/.gradle/caches"
		["User Gradle wrapper"]="${HOME_DIR}/.gradle/wrapper/dists"
		["User Maven"]="${HOME_DIR}/.m2/repository"
		["User Ccache"]="${HOME_DIR}/.cache/ccache"
		["User CMake"]="${HOME_DIR}/.cache/CMakeCache"
		["Root Gradle"]="/root/.gradle/caches"
		["Root Gradle wrapper"]="/root/.gradle/wrapper/dists"
		["Root Maven"]="/root/.m2/repository"
		["Root Ccache"]="/root/.cache/ccache"
		["Root CMake"]="/root/.cache/CMakeCache"
	)

	for tool in "${!build_caches[@]}"; do
		local cache_dir="${build_caches[$tool]}"
		if [[ -d "$cache_dir" ]]; then
			if $DRY_RUN; then
				print_status "${tool} (~$(size_of "$cache_dir")) would be cleaned" dry
			else
				sudo rm -rf "${cache_dir:?}"/* 2>/dev/null || true
				print_status "Cleared ${tool} cache" ok
				log "Cleared ${tool} cache"
			fi
		fi
	done

	if command_exists ccache; then
		if ! $DRY_RUN; then
			sudo -u "$REAL_USER" ccache -C 2>/dev/null || true
			print_status "Reset ccache statistics (user)" ok
			ccache -C 2>/dev/null || true
			print_status "Reset ccache statistics (root)" ok
		fi
	fi
}

clean_old_logs() {
	if is_skipped "oldlogs"; then
		print_status "Old rotated logs" skip
		return
	fi

	print_header "Cleaning old rotated logs"
	log "Starting old log cleanup"

	local log_patterns=(
		"/var/log/*.gz"
		"/var/log/*.xz"
		"/var/log/*.Zst"
		"/var/log/*.old"
		"/var/log/*.1"
		"/var/log/*/*.gz"
		"/var/log/*/*.xz"
	)

	if $DRY_RUN; then
		local count=0
		for pattern in "${log_patterns[@]}"; do
			while IFS= read -r -d '' f; do
				count=$((count + 1))
			done < <(find /var/log -maxdepth 2 -name "${pattern##*/}" -mtime +90 -print0 2>/dev/null)
		done
		if [[ $count -gt 0 ]]; then
			print_status "${count} old rotated logs would be removed" dry
		fi
	else
		local count=0
		for pattern in "${log_patterns[@]}"; do
			while IFS= read -r -d '' f; do
				sudo rm -f "$f" 2>/dev/null || true
				count=$((count + 1))
			done < <(find /var/log -maxdepth 2 -name "${pattern##*/}" -mtime +90 -print0 2>/dev/null)
		done
		if [[ $count -gt 0 ]]; then
			print_status "Removed ${count} old rotated logs" ok
			log "Removed ${count} old rotated logs"
		else
			print_status "No old rotated logs found" ok
		fi
	fi

	if [[ -d /var/log/dpkg ]]; then
		if $DRY_RUN; then
			print_status "DPKG logs older than 90 days would be removed" dry
		else
			sudo find /var/log/dpkg -name 'dpkg.log.*.gz' -mtime +90 -delete 2>/dev/null || true
			print_status "Cleaned old DPKG logs" ok
		fi
	fi

	if [[ -d /var/log/apt ]]; then
		if $DRY_RUN; then
			print_status "APT logs older than 30 days would be removed" dry
		else
			sudo find /var/log/apt -name '*.gz' -mtime +30 -delete 2>/dev/null || true
			print_status "Cleaned old APT logs" ok
		fi
	fi
}

clean_editor_swap_files() {
	if is_skipped "swaps"; then
		print_status "Editor swap files" skip
		return
	fi

	print_header "Cleaning editor swap/backup files"
	log "Starting editor swap file cleanup"

	if $DRY_RUN; then
		local vim_count emacs_count nano_count
		vim_count=$(find "${HOME_DIR}" -maxdepth 5 \( -name '.*.swp' -o -name '.*.swo' \) -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | wc -l)
		emacs_count=$(find "${HOME_DIR}" -maxdepth 5 \( -name '\#*\#' -o -name '.\#*' \) -not -path '*/node_modules/*' 2>/dev/null | wc -l)
		nano_count=$(find "${HOME_DIR}" -maxdepth 5 -name '*~' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | wc -l)

		[[ $vim_count -gt 0 ]] && print_status "${vim_count} Vim swap files would be removed" dry
		[[ $emacs_count -gt 0 ]] && print_status "${emacs_count} Emacs auto-save files would be removed" dry
		[[ $nano_count -gt 0 ]] && print_status "${nano_count} Nano backup files would be removed" dry
	else
		local total=0

		local vim_count
		vim_count=$(find "${HOME_DIR}" -maxdepth 5 \( -name '.*.swp' -o -name '.*.swo' \) -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | wc -l)
		if [[ $vim_count -gt 0 ]]; then
			find "${HOME_DIR}" -maxdepth 5 \( -name '.*.swp' -o -name '.*.swo' \) -not -path '*/node_modules/*' -not -path '*/.git/*' -delete 2>/dev/null || true
			total=$((total + vim_count))
		fi

		local emacs_count
		emacs_count=$(find "${HOME_DIR}" -maxdepth 5 \( -name '\#*\#' -o -name '.\#*' \) -not -path '*/node_modules/*' 2>/dev/null | wc -l)
		if [[ $emacs_count -gt 0 ]]; then
			find "${HOME_DIR}" -maxdepth 5 \( -name '\#*\#' -o -name '.\#*' \) -not -path '*/node_modules/*' -delete 2>/dev/null || true
			total=$((total + emacs_count))
		fi

		local nano_count
		nano_count=$(find "${HOME_DIR}" -maxdepth 5 -name '*~' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | wc -l)
		if [[ $nano_count -gt 0 ]]; then
			find "${HOME_DIR}" -maxdepth 5 -name '*~' -not -path '*/node_modules/*' -not -path '*/.git/*' -delete 2>/dev/null || true
			total=$((total + nano_count))
		fi

		if [[ $total -gt 0 ]]; then
			print_status "Removed ${total} editor swap/backup files" ok
			log "Removed ${total} editor swap files"
		else
			print_status "No editor swap files found" ok
		fi
	fi
}

clean_tex_cache() {
	if is_skipped "tex"; then
		print_status "TeX cache" skip
		return
	fi

	if ! command_exists kpsewhich; then
		print_status "TeX not installed" warn
		return
	fi

	print_header "Cleaning TeX cache"
	log "Starting TeX cache cleanup"

	local tex_dirs=(
		"${HOME_DIR}/.cache/texmf"
		"${HOME_DIR}/.texlive"
	)

	for dir in "${tex_dirs[@]}"; do
		if [[ -d "$dir" ]]; then
			if $DRY_RUN; then
				print_status "${dir} (~$(size_of "$dir")) would be cleaned" dry
			else
				sudo rm -rf "${dir:?}"/* 2>/dev/null || true
				print_status "Cleared ${dir}" ok
				log "Cleared ${dir}"
			fi
		fi
	done

	if ! $DRY_RUN && command_exists mktexlsr; then
		mktexlsr 2>/dev/null || true
		print_status "Rebuilt TeX filename database" ok
	fi
}

# ── New Cleanup Functions (v2.1.1) ───────────────────────────────────────────

clean_browser_caches() {
	if is_skipped "browser"; then
		print_status "Browser caches" skip
		return
	fi

	print_header "Cleaning browser caches"
	log "Starting browser cache cleanup"

	local user_home="${HOME_DIR}"
	local found=0

	# Chromium-based browsers
	local -A chromium_browsers=(
		["Google Chrome"]="${user_home}/.cache/google-chrome"
		["Chromium"]="${user_home}/.cache/chromium"
		["Brave"]="${user_home}/.cache/BraveSoftware/Brave-Browser"
		["Microsoft Edge"]="${user_home}/.cache/microsoft-edge"
		["Vivaldi"]="${user_home}/.cache/vivaldi"
		["Opera"]="${user_home}/.cache/opera"
		["Thorium"]="${user_home}/.cache/thorium"
	)

	for browser in "${!chromium_browsers[@]}"; do
		local cache_dir="${chromium_browsers[$browser]}"
		[[ -d "$cache_dir" ]] || continue
		found=$((found + 1))
		local s=$(size_of "$cache_dir")
		if $DRY_RUN; then
			print_status "${browser} cache (~${s}) would be cleaned" dry
		else
			while IFS= read -r -d '' d; do
				sudo rm -rf "${d:?}"/* 2>/dev/null || true
			done < <(find "$cache_dir" -maxdepth 4 -type d \( \
				-name "Cache" -o -name "Code Cache" -o \
				-name "GPUCache" -o -name "ShaderCache" -o \
				-name "DawnCache" -o -name "BlobStorage" \) -print0 2>/dev/null)
			print_status "Cleared ${browser} cache (~${s})" ok
			log "Cleared ${browser} cache"
		fi
	done

	[[ $found -eq 0 ]] && print_status "No Chromium-based browser caches found" ok
}


# NEW: clean partial .deb downloads
clean_deb_partial() {
	if is_skipped "debpartial"; then
		print_status "Partial .deb downloads" skip
		return
	fi

	local partial_dir="/var/cache/apt/archives/partial"
	if [[ ! -d "$partial_dir" ]]; then
		return  # not Debian/Ubuntu or doesn't exist
	fi

	print_header "Cleaning partial .deb downloads"
	log "Starting partial .deb cleanup"

	local count=$(find "$partial_dir" -type f 2>/dev/null | wc -l)
	if [[ $count -gt 0 ]]; then
		local s=$(size_of "$partial_dir")
		if $DRY_RUN; then
			print_status "${count} partial .deb files (~${s}) would be removed" dry
		else
			sudo rm -rf "${partial_dir:?}"/* 2>/dev/null || true
			print_status "Removed ${count} partial .deb files (~${s})" ok
			log "Removed ${count} partial .deb files from ${partial_dir}"
		fi
	else
		print_status "No partial .deb files found" ok
	fi
}

# NEW: clean systemd user cache
clean_systemd_user_cache() {
	if is_skipped "sysdcache"; then
		print_status "Systemd user cache" skip
		return
	fi

	local sysd_cache="${HOME_DIR}/.cache/systemd"
	if [[ ! -d "$sysd_cache" ]]; then
		return
	fi

	print_header "Cleaning systemd user cache"
	log "Starting systemd user cache cleanup"

	local s=$(size_of "$sysd_cache")
	if $DRY_RUN; then
		print_status "Systemd user cache (~${s}) would be cleaned" dry
	else
		sudo rm -rf "${sysd_cache:?}"/* 2>/dev/null || true
		print_status "Cleared systemd user cache (~${s})" ok
		log "Cleared ${sysd_cache}"
	fi
}

clean_pnpm_cache() {
	if is_skipped "pnpm"; then
		print_status "pnpm" skip
		return
	fi

	if ! command_exists pnpm; then
		print_status "pnpm not found" warn
		return
	fi

	print_header "Cleaning pnpm store"
	log "Starting pnpm cache cleanup"

	if $DRY_RUN; then
		local user_store
		user_store=$(sudo -u "$REAL_USER" pnpm store path 2>/dev/null || echo "${HOME_DIR}/.local/share/pnpm/store")
		local root_store
		root_store=$(pnpm store path 2>/dev/null || echo "/root/.local/share/pnpm/store")
		print_status "User pnpm store (~$(size_of "$user_store")) would be pruned" dry
		print_status "Root pnpm store (~$(size_of "$root_store")) would be pruned" dry
	else
		sudo -u "$REAL_USER" pnpm store prune 2>/dev/null || true
		print_status "Pruned pnpm store (user)" ok
		pnpm store prune 2>/dev/null || true
		print_status "Pruned pnpm store (root)" ok
		log "pnpm store pruned (user + root)"
	fi
}

clean_bun_cache() {
	if is_skipped "bun"; then
		print_status "Bun" skip
		return
	fi

	if ! command_exists bun; then
		print_status "bun not found" warn
		return
	fi

	print_header "Cleaning Bun cache"
	log "Starting Bun cache cleanup"

	local user_bun_cache="${HOME_DIR}/.bun/install/cache"
	local root_bun_cache="/root/.bun/install/cache"
	local found=0

	for bun_cache in "$user_bun_cache" "$root_bun_cache"; do
		[[ -d "$bun_cache" ]] || continue
		found=$((found + 1))
		if $DRY_RUN; then
			print_status "Bun install cache (~$(size_of "$bun_cache")) would be cleared" dry
		else
			local s=$(size_of "$bun_cache")
			sudo rm -rf "${bun_cache:?}"/* 2>/dev/null || true
			print_status "Cleared Bun install cache (~${s})" ok
			log "Cleared Bun install cache: ${bun_cache}"
		fi
	done

	[[ $found -eq 0 ]] && print_status "No Bun cache found" ok
}

clean_deno_cache() {
	if is_skipped "deno"; then
		print_status "Deno" skip
		return
	fi

	if ! command_exists deno; then
		print_status "deno not found" warn
		return
	fi

	print_header "Cleaning Deno cache"
	log "Starting Deno cache cleanup"

	local user_deno_dir="${HOME_DIR}/.cache/deno"
	local env_deno_dir
	env_deno_dir=$(sudo -u "$REAL_USER" printenv DENO_DIR 2>/dev/null || true)
	[[ -n "$env_deno_dir" ]] && user_deno_dir="$env_deno_dir"

	local root_deno_dir="/root/.cache/deno"
	local env_root_deno_dir
	env_root_deno_dir=$(printenv DENO_DIR 2>/dev/null || true)
	[[ -n "$env_root_deno_dir" ]] && root_deno_dir="$env_root_deno_dir"

	local found=0
	for deno_dir in "$user_deno_dir" "$root_deno_dir"; do
		[[ -d "$deno_dir" ]] || continue
		found=$((found + 1))
		if $DRY_RUN; then
			print_status "Deno cache (~$(size_of "$deno_dir")) would be cleaned" dry
		else
			local s=$(size_of "$deno_dir")
			for subdir in deps gen npm registries; do
				[[ -d "${deno_dir}/${subdir}" ]] && sudo rm -rf "${deno_dir:?}/${subdir}" 2>/dev/null || true
			done
			print_status "Cleared Deno cache (~${s})" ok
			log "Cleared Deno cache: ${deno_dir}"
		fi
	done

	[[ $found -eq 0 ]] && print_status "No Deno cache found" ok
}

clean_ruby_cache() {
	if is_skipped "ruby"; then
		print_status "Ruby/Gems" skip
		return
	fi

	if ! command_exists gem; then
		print_status "gem not found" warn
		return
	fi

	print_header "Cleaning Ruby gem cache"
	log "Starting Ruby gem cleanup"

	local user_gem_dir root_gem_dir user_gem_cache root_gem_cache
	user_gem_dir=$(sudo -u "$REAL_USER" gem environment gemdir 2>/dev/null || echo "${HOME_DIR}/.gem")
	root_gem_dir=$(gem environment gemdir 2>/dev/null || echo "/root/.gem")
	user_gem_cache="${user_gem_dir}/cache"
	root_gem_cache="${root_gem_dir}/cache"

	if $DRY_RUN; then
		local user_count root_count
		if [[ -d "$user_gem_cache" ]]; then
			user_count=$(find "$user_gem_cache" -name '*.gem' 2>/dev/null | wc -l)
			print_status "User cached .gem files: ${user_count} (~$(size_of "$user_gem_cache")) would be removed" dry
		fi
		if [[ -d "$root_gem_cache" ]]; then
			root_count=$(find "$root_gem_cache" -name '*.gem' 2>/dev/null | wc -l)
			print_status "Root cached .gem files: ${root_count} (~$(size_of "$root_gem_cache")) would be removed" dry
		fi
		print_status "Old gem versions would be removed via gem cleanup" dry
	else
		sudo -u "$REAL_USER" gem cleanup 2>/dev/null || true
		print_status "Removed old gem versions (user)" ok
		gem cleanup 2>/dev/null || true
		print_status "Removed old gem versions (root)" ok
		log "Removed old gem versions (user + root)"

		for gem_cache in "$user_gem_cache" "$root_gem_cache"; do
			if [[ -d "$gem_cache" ]]; then
				local s=$(size_of "$gem_cache")
				sudo rm -rf "${gem_cache:?}"/* 2>/dev/null || true
				print_status "Cleared gem download cache (~${s})" ok
				log "Cleared gem download cache: ${gem_cache}"
			fi
		done

		for bundler_cache in "${HOME_DIR}/.bundle" "/root/.bundle"; do
			if [[ -d "$bundler_cache" ]]; then
				find "$bundler_cache" -name '*.gem' -delete 2>/dev/null || true
				print_status "Cleared Bundler .gem files: ${bundler_cache}" ok
			fi
		done
	fi
}

clean_composer_cache() {
	if is_skipped "composer"; then
		print_status "Composer" skip
		return
	fi

	if ! command_exists composer; then
		print_status "composer not found" warn
		return
	fi

	print_header "Cleaning Composer cache"
	log "Starting Composer cache cleanup"

	if $DRY_RUN; then
		local user_composer_cache root_composer_cache
		user_composer_cache=$(sudo -u "$REAL_USER" composer config --global cache-dir 2>/dev/null \
			|| echo "${HOME_DIR}/.composer/cache")
		root_composer_cache=$(composer config --global cache-dir 2>/dev/null \
			|| echo "/root/.composer/cache")
		print_status "User Composer cache (~$(size_of "$user_composer_cache")) would be cleared" dry
		print_status "Root Composer cache (~$(size_of "$root_composer_cache")) would be cleared" dry
	else
		sudo -u "$REAL_USER" composer clear-cache 2>/dev/null || true
		print_status "Cleared Composer cache (user)" ok
		composer clear-cache 2>/dev/null || true
		print_status "Cleared Composer cache (root)" ok
		log "Composer cache cleared (user + root)"
	fi
}

clean_poetry_cache() {
	if is_skipped "poetry"; then
		print_status "Poetry" skip
		return
	fi

	if ! command_exists poetry; then
		print_status "poetry not found" warn
		return
	fi

	print_header "Cleaning Poetry cache"
	log "Starting Poetry cache cleanup"

	if $DRY_RUN; then
		local user_poetry_cache root_poetry_cache
		user_poetry_cache=$(sudo -u "$REAL_USER" poetry config cache-dir 2>/dev/null \
			|| echo "${HOME_DIR}/.cache/pypoetry")
		root_poetry_cache=$(poetry config cache-dir 2>/dev/null \
			|| echo "/root/.cache/pypoetry")
		print_status "User Poetry cache (~$(size_of "$user_poetry_cache")) would be cleared" dry
		print_status "Root Poetry cache (~$(size_of "$root_poetry_cache")) would be cleared" dry
	else
		sudo -u "$REAL_USER" poetry cache clear --all pypi -n 2>/dev/null || true
		sudo -u "$REAL_USER" poetry cache clear --all PyPI -n 2>/dev/null || true
		poetry cache clear --all pypi -n 2>/dev/null || true
		poetry cache clear --all PyPI -n 2>/dev/null || true
		print_status "Cleared Poetry PyPI download cache (user + root)" ok
		log "Poetry cache cleared (user + root)"
	fi
}

clean_pipenv_cache() {
	if is_skipped "pipenv"; then
		print_status "Pipenv/pip HTTP cache" skip
		return
	fi

	print_header "Cleaning pip HTTP cache"
	log "Starting pip HTTP cache cleanup"

	local found=0

	for pip_base in "${HOME_DIR}/.cache/pip" "/root/.cache/pip"; do
		for hcache in "${pip_base}/http" "${pip_base}/http-v2"; do
			if [[ -d "$hcache" ]]; then
				found=$((found + 1))
				if $DRY_RUN; then
					print_status "pip HTTP cache (~$(size_of "$hcache")) would be cleared" dry
				else
					local s=$(size_of "$hcache")
					sudo rm -rf "${hcache:?}"/* 2>/dev/null || true
					print_status "Cleared pip HTTP cache (~${s})" ok
					log "Cleared pip HTTP cache: ${hcache}"
				fi
			fi
		done
	done

	local pipenv_venv_dir="${HOME_DIR}/.local/share/virtualenvs"
	if [[ -d "$pipenv_venv_dir" ]]; then
		local count
		count=$(find "$pipenv_venv_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
		if [[ $count -gt 0 ]]; then
			print_status "${count} pipenv virtualenvs in ${pipenv_venv_dir} — remove manually if unneeded" warn
		fi
	fi

	[[ $found -eq 0 ]] && print_status "No pip HTTP cache found" ok
}

clean_conda_cache() {
	if is_skipped "conda"; then
		print_status "Conda/Mamba" skip
		return
	fi

	local conda_cmd=""
	for cmd in conda mamba micromamba; do
		if command_exists "$cmd"; then
			conda_cmd="$cmd"
			break
		fi
	done

	if [[ -z "$conda_cmd" ]]; then
		print_status "conda/mamba not found" warn
		return
	fi

	print_header "Cleaning ${conda_cmd} cache"
	log "Starting ${conda_cmd} cache cleanup"

	if $DRY_RUN; then
		print_status "User ${conda_cmd} clean --all would remove tarballs, index cache, and unused packages" dry
		print_status "Root ${conda_cmd} clean --all would remove tarballs, index cache, and unused packages" dry
	else
		sudo -u "$REAL_USER" "$conda_cmd" clean --all -y 2>/dev/null || true
		print_status "Cleaned ${conda_cmd} tarballs, packages, and index cache (user)" ok
		"$conda_cmd" clean --all -y 2>/dev/null || true
		print_status "Cleaned ${conda_cmd} tarballs, packages, and index cache (root)" ok
		log "${conda_cmd} cache cleaned (user + root)"
	fi
}

clean_wine_shader_cache() {
	if is_skipped "wine"; then
		print_status "Wine/Steam shader cache" skip
		return
	fi

	print_header "Cleaning Wine/Steam shader caches"
	log "Starting Wine/Steam shader cache cleanup"

	local user_home="${HOME_DIR}"
	local found=0

	local wine_cache="${user_home}/.cache/wine"
	if [[ -d "$wine_cache" ]]; then
		found=$((found + 1))
		if $DRY_RUN; then
			print_status "Wine shader cache (~$(size_of "$wine_cache")) would be cleaned" dry
		else
			local s; s=$(size_of "$wine_cache")
			sudo rm -rf "${wine_cache:?}"/* 2>/dev/null || true
			print_status "Cleared Wine shader cache (~${s})" ok
			log "Cleared Wine shader cache"
		fi
	fi

	for steam_dir in \
		"${user_home}/.steam/steam/shadercache" \
		"${user_home}/.local/share/Steam/shadercache"; do
		if [[ -d "$steam_dir" ]]; then
			found=$((found + 1))
			if $DRY_RUN; then
				print_status "Steam shader cache (~$(size_of "$steam_dir")) would be cleaned" dry
			else
				local s; s=$(size_of "$steam_dir")
				sudo rm -rf "${steam_dir:?}"/* 2>/dev/null || true
				print_status "Cleared Steam shader cache (~${s})" ok
				log "Cleared Steam shader cache at ${steam_dir}"
			fi
			break
		fi
	done

	local lutris_cache="${user_home}/.cache/lutris"
	if [[ -d "$lutris_cache" ]]; then
		found=$((found + 1))
		if $DRY_RUN; then
			print_status "Lutris cache (~$(size_of "$lutris_cache")) would be cleaned" dry
		else
			local s; s=$(size_of "$lutris_cache")
			sudo rm -rf "${lutris_cache:?}"/* 2>/dev/null || true
			print_status "Cleared Lutris cache (~${s})" ok
			log "Cleared Lutris cache"
		fi
	fi

	[[ $found -eq 0 ]] && print_status "No Wine/Steam caches found" ok
}

clean_git_repos() {
	if is_skipped "gitgc"; then
		print_status "Git garbage collection" skip
		return
	fi

	if ! command_exists git; then
		print_status "git not found" warn
		return
	fi

	print_header "Running Git garbage collection"
	log "Starting Git GC pass"

	local user_home="${HOME_DIR}"
	local -a repos=()

	while IFS= read -r -d '' gitdir; do
		repos+=("${gitdir%/.git}")
	done < <(find "$user_home" -maxdepth 6 \
		-not -path '*/node_modules/*' \
		-not -path '*/.cargo/*' \
		-not -path '*/.rustup/*' \
		-not -path '*/vendor/*' \
		-not -path '*/.gem/*' \
		-not -path '*/site-packages/*' \
		-name '.git' -type d -print0 2>/dev/null)

	if [[ ${#repos[@]} -eq 0 ]]; then
		print_status "No git repositories found in ${user_home}" ok
		return
	fi

	if $DRY_RUN; then
		print_status "${#repos[@]} repositories found — git gc --prune=now would be run on each" dry
		return
	fi

	local gc_count=0
	for repo in "${repos[@]}"; do
		[[ -d "${repo}/.git" ]] || continue
		sudo -u "$REAL_USER" git -C "$repo" gc --prune=now --quiet 2>/dev/null || true
		gc_count=$((gc_count + 1))
	done

	print_status "Ran git gc --prune=now on ${gc_count} repositories" ok
	log "Ran git gc on ${gc_count} repositories"
}

clean_apport_reports() {
	if is_skipped "apport"; then
		print_status "Apport crash reports" skip
		return
	fi

	local crash_dir="/var/crash"
	if [[ ! -d "$crash_dir" ]]; then
		print_status "Apport crash directory not found" warn
		return
	fi

	print_header "Cleaning Apport crash reports"
	log "Starting Apport crash report cleanup"

	local count
	count=$(find "$crash_dir" -maxdepth 1 \( \
		-name '*.crash' -o -name '*.upload' -o -name '*.uploaded' \
		\) 2>/dev/null | wc -l)

	if [[ $count -gt 0 ]]; then
		local s=$(size_of "$crash_dir")
		if $DRY_RUN; then
			print_status "${count} crash report files (~${s}) would be removed" dry
		else
			sudo find "$crash_dir" -maxdepth 1 \( \
				-name '*.crash' -o -name '*.upload' -o -name '*.uploaded' \
				\) -delete 2>/dev/null || true
			print_status "Removed ${count} crash reports (~${s})" ok
			log "Removed ${count} Apport crash reports"
		fi
	else
		print_status "No crash reports found" ok
	fi
}

clean_locate_database() {
	if is_skipped "locate"; then
		print_status "Locate database update" skip
		return
	fi

	if ! command_exists updatedb; then
		print_status "updatedb not found" warn
		return
	fi

	if ! $DRY_RUN; then
		print_header "Updating locate database"
		sudo updatedb 2>/dev/null || true
		print_status "Locate database updated" ok
	fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
	parse_args "$@"
	ensure_root "$@"

	mkdir -p "$LOG_DIR" 2>/dev/null || true
	log "SysSweep v${VERSION} started (user: ${REAL_USER}, dry-run: ${DRY_RUN})"

	echo -e "\e[1;35m"
	echo "  ╔═══════════════════════════════════════════════════╗"
	echo "  ║          SysSweep v${VERSION}                   ║"
	echo "  ║        Linux System Cleanup Tool                 ║"
	echo "  ╚═══════════════════════════════════════════════════╝"
	echo -e "\e[0m"

	if $DRY_RUN; then
		echo -e "\e[1;33m  ⚡ DRY RUN MODE — nothing will be deleted\e[0m"
		echo ""
	fi

	local before_kb=$(disk_used_kb /)

	echo -e "\e[1;34mDisk usage before cleanup:\e[0m"
	printf "  Used: %s\n" "$(format_bytes "$before_kb")"
	echo ""

	if ! $DRY_RUN; then
		if ! confirm "This will clean system caches and temporary files. Continue?"; then
			echo -e "\e[33mAborted.\e[0m"
			exit 0
		fi
		echo ""
	fi

	# ── Original cleanup functions ──
	clean_temp_directories
	clean_dangling_symlinks
	clean_systemd_tmpfiles
	clean_trash_folders
	clean_journal_logs
	clean_flatpak_cache
	clean_docker
	clean_docker_builder_cache
	clean_pacman_cache
	clean_pamac_cache
	clean_apt_cache
	clean_package_manager_caches
	clean_old_kernels
	clean_python_cache
	clean_npm_cache
	clean_yarn_cache
	clean_cargo_cache
	clean_go_cache
	clean_snap_cache
	clean_mesa_shader_cache
	clean_fontconfig_cache
	clean_core_dumps
	clean_electron_caches
	clean_build_tool_caches
	clean_old_logs
	clean_editor_swap_files
	clean_tex_cache

	# ── New cleanup functions (v2.1.1) ──
	clean_browser_caches
	clean_deb_partial
	clean_systemd_user_cache
	clean_pnpm_cache
	clean_bun_cache
	clean_deno_cache
	clean_ruby_cache
	clean_composer_cache
	clean_poetry_cache
	clean_pipenv_cache
	clean_conda_cache
	clean_wine_shader_cache
	clean_git_repos
	clean_apport_reports
	clean_locate_database

	local after_kb=$(disk_used_kb /)

	echo ""
	echo -e "\e[1;34mDisk usage after cleanup:\e[0m"
	printf "  Used: %s\n" "$(format_bytes "$after_kb")"

	if $DRY_RUN; then
		print_status "Estimated freed space: 0 (dry run)" info
	elif (( after_kb <= before_kb )); then
		local freed_kb=$((before_kb - after_kb))
		print_status "Estimated freed space: $(format_bytes "$freed_kb")" ok
	else
		local freed_kb=$((after_kb - before_kb))
		print_status "Estimated freed space: 0 (filesystem usage increased by $(format_bytes "$freed_kb"))" warn
	fi
	echo ""
	echo -e "\e[1;32m══════════════════════════════════════════════════════\e[0m"
	echo -e "\e[1;32m  Cleanup complete! Log saved to: ${LOG_FILE}\e[0m"
	echo -e "\e[1;32m══════════════════════════════════════════════════════\e[0m"
	echo ""

	log "SysSweep completed"
}

main "$@"