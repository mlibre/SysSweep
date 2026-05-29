#!/bin/bash

set -euo pipefail

# ============================================================================
# SysSweep — Safe Linux system cleanup script
# ============================================================================

VERSION="2.0.0"
LOG_DIR="${HOME}/.local/share"
LOG_FILE="${LOG_DIR}/syssweep.log"
REAL_USER="${SUDO_USER:-$USER}"
DRY_RUN=false
SKIPPED=()
TOTAL_FREED=0

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
                     Available: temp, trash, journal, flatpak, docker,
                     pacman, pamac, apt, python, npm, yarn, cargo,
                     go, snap, mesa, fontconfig, coredumps, electron,
                     buildtools, oldlogs, swaps, tex, locate
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
	type "$1" &>/dev/null
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
	local msg="$1"
	echo -e ""
	echo -e "\e[1;36m══════════════════════════════════════════════════════\e[0m"
	echo -e "\e[1;36m  ${msg}\e[0m"
	echo -e "\e[1;36m══════════════════════════════════════════════════════\e[0m"
	echo -e ""
}

print_status() {
	local msg="$1"
	local type="${2:-info}"
	case "$type" in
	ok) echo -e "  \e[32m✓\e[0m $msg" ;;
	warn) echo -e "  \e[33m⚠\e[0m $msg" ;;
	err) echo -e "  \e[31m✗\e[0m $msg" ;;
	skip) echo -e "  \e[90m○\e[0m $msg (skipped)" ;;
	dry) echo -e "  \e[35mpreview>\e[0m $msg" ;;
	esac
}

size_of() {
	local path="$1" result
	result=$( (du -sh "$path" 2>/dev/null || true) | head -1 | awk '{print $1}' )
	echo "${result:-0}"
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

	local count=0
	local size=""

	if $DRY_RUN; then
		print_status "/tmp — would remove ~$(size_of /tmp)" dry
		print_status "/var/tmp — would remove ~$(size_of /var/tmp)" dry
	else
		# Clean /tmp — only files older than 1 day to avoid breaking running processes
		local tmp_before tmp_size
		tmp_size=$(size_of /tmp)
		tmp_before=$( (find /tmp -mindepth 1 -maxdepth 1 -mtime +1 2>/dev/null || true) | wc -l)
		if [[ "$tmp_before" -gt 0 ]]; then
			sudo find /tmp -mindepth 1 -maxdepth 1 -mtime +1 -exec rm -rf {} + 2>/dev/null || true
			print_status "Removed old files from /tmp (~${tmp_size})" ok
			log "Removed ${tmp_before} old files from /tmp"
		else
			print_status "/tmp — nothing old enough to remove" ok
		fi

		# Clean /var/tmp
		local vartmp_size vartmp_before
		vartmp_size=$(size_of /var/tmp)
		vartmp_before=$( (find /var/tmp -mindepth 1 -maxdepth 1 -mtime +1 2>/dev/null || true) | wc -l)
		if [[ "$vartmp_before" -gt 0 ]]; then
			sudo find /var/tmp -mindepth 1 -maxdepth 1 -mtime +1 -exec rm -rf {} + 2>/dev/null || true
			print_status "Removed old files from /var/tmp (~${vartmp_size})" ok
			log "Removed ${vartmp_before} old files from /var/tmp"
		else
			print_status "/var/tmp — nothing old enough to remove" ok
		fi

		# Clean user trash
		for trash_dir in \
			"/home/${REAL_USER}/.local/share/Trash/files" \
			"/home/${REAL_USER}/.local/share/Trash/info" \
			"/root/.local/share/Trash/files" \
			"/root/.local/share/Trash/info"; do
			if [[ -d "$trash_dir" ]]; then
				count=$(find "$trash_dir" -mindepth 1 2>/dev/null | wc -l)
				if [[ $count -gt 0 ]]; then
					sudo rm -rf "${trash_dir:?}"/* 2>/dev/null || true
					print_status "Cleared ${trash_dir}" ok
					log "Cleared ${trash_dir}"
				fi
			fi
		done

		# Clean npm cache
		for npm_dir in "/home/${REAL_USER}/.npm" "/root/.npm"; do
			if [[ -d "$npm_dir" ]]; then
				local npm_size
				npm_size=$(size_of "$npm_dir")
				sudo rm -rf "${npm_dir:?}" 2>/dev/null || true
				print_status "Removed ${npm_dir} (~${npm_size})" ok
				log "Removed ${npm_dir}"
			fi
		done

		# Clean KDE thumbnail caches
		for cache_dir in "/home/${REAL_USER}/.cache/ksycoca5*" "/root/.cache/ksycoca5*"; do
			# Use find to handle glob safely
			while IFS= read -r -d '' dir; do
				sudo rm -rf "${dir}" 2>/dev/null || true
				print_status "Removed ${dir}" ok
				log "Removed ${dir}"
			done < <(find /home/${REAL_USER}/.cache /root/.cache -maxdepth 1 -name 'ksycoca5*' -print0 2>/dev/null)
		done

		# Clean thumbnail cache
		local thumb_size
		thumb_size=$(size_of "/home/${REAL_USER}/.cache/thumbnails")
		if [[ -n "$thumb_size" && "$thumb_size" != "0" ]]; then
			sudo rm -rf "/home/${REAL_USER}/.cache/thumbnails/"* 2>/dev/null || true
			print_status "Cleared thumbnail cache (~${thumb_size})" ok
			log "Cleared thumbnail cache"
		fi
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
		# Skip special filesystems
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
					local s
					s=$(size_of "$trash_dir")
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

		# Clean package cache completely
		sudo pacman -Scc --noconfirm 2>/dev/null || true
		print_status "Cleaned full package cache" ok
		log "Pacman cache cleanup completed"
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

clean_python_cache() {
	if is_skipped "python"; then
		print_status "Python/pip" skip
		return
	fi

	print_header "Cleaning Python caches"
	log "Starting Python cache cleanup"

	if $DRY_RUN; then
		# Check pip cache
		if command_exists pip; then
			local user_pip root_pip
			user_pip=$(sudo -u "$REAL_USER" pip cache dir 2>/dev/null || echo "/home/${REAL_USER}/.cache/pip")
			root_pip=$(pip cache dir 2>/dev/null || echo "/root/.cache/pip")
			print_status "User pip cache (~$(size_of "$user_pip")) would be purged" dry
			print_status "Root pip cache (~$(size_of "$root_pip")) would be purged" dry
		fi

		# Check __pycache__ dirs
		local pycache_count
		pycache_count=$(find /home/${REAL_USER} -name '__pycache__' -type d 2>/dev/null | wc -l)
		if [[ $pycache_count -gt 0 ]]; then
			print_status "${pycache_count} __pycache__ directories would be removed" dry
		fi
	else
		if command_exists pip; then
			sudo -u "$REAL_USER" pip cache purge 2>/dev/null || true
			print_status "Purged pip cache (user)" ok
			pip cache purge 2>/dev/null || true
			print_status "Purged pip cache (root)" ok
			log "Purged pip cache (user + root)"
		fi

		# Remove __pycache__ dirs in user space
		local pycache_count
		pycache_count=$(find /home/${REAL_USER} -name '__pycache__' -type d 2>/dev/null | wc -l)
		if [[ $pycache_count -gt 0 ]]; then
			find /home/${REAL_USER} -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
			print_status "Removed ${pycache_count} __pycache__ directories" ok
			log "Removed ${pycache_count} __pycache__ directories"
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

	# Clean npm cache for real user
	if $DRY_RUN; then
		local user_cache root_cache
		user_cache=$(sudo -u "$REAL_USER" npm config get cache 2>/dev/null || echo "/home/${REAL_USER}/.npm")
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
		local user_yarn root_yarn
		user_yarn=$(sudo -u "$REAL_USER" yarn cache dir 2>/dev/null || echo "/home/${REAL_USER}/.cache/yarn")
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

	local user_cargo="/home/${REAL_USER}/.cargo"
	local root_cargo="/root/.cargo"

	if $DRY_RUN; then
		if [[ -d "${user_cargo}/registry" ]]; then
			print_status "User Cargo registry (~$(size_of "${user_cargo}/registry")) would be cleaned" dry
		fi
		if [[ -d "${root_cargo}/registry" ]]; then
			print_status "Root Cargo registry (~$(size_of "${root_cargo}/registry")) would be cleaned" dry
		fi
	else
		# Clean user cargo cache
		if [[ -d "${user_cargo}/registry/cache" ]]; then
			sudo rm -rf "${user_cargo}/registry/cache/"* 2>/dev/null || true
			print_status "Cleaned Cargo cache (user)" ok
		fi
		# Clean root cargo cache
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
		local user_go="/home/${REAL_USER}/.cache/go-build"
		local root_go="/root/.cache/go-build"
		if [[ -d "$user_go" ]]; then
			print_status "User Go build cache (~$(size_of "$user_go")) would be cleaned" dry
		fi
		if [[ -d "$root_go" ]]; then
			print_status "Root Go build cache (~$(size_of "$root_go")) would be cleaned" dry
		fi
	else
		# Clean user go cache
		sudo -u "$REAL_USER" go clean -cache 2>/dev/null || true
		print_status "Cleaned Go build cache (user)" ok
		# Clean root go cache
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
		print_status "Would remove snap Thumbnails and logs" dry
	else
		# Clean snap thumbnails
		sudo rm -rf /var/snapd/cache/*.snap 2>/dev/null || true
		# Clean snap thumbnails user cache
		sudo rm -rf "/home/${REAL_USER}/snap/"*/common/.cache/thumbnails/* 2>/dev/null || true
		# Clean old snap revisions (keep current)
		local current_snap
		current_snap=$(snap list 2>/dev/null | awk 'NR>1{print $1, $3}' || true)
		print_status "Cleaned snap cache" ok
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
		"/home/${REAL_USER}/.cache/mesa_shader_cache"
		"/root/.cache/mesa_shader_cache"
	)

	for dir in "${mesa_dirs[@]}"; do
		if [[ -d "$dir" ]]; then
			if $DRY_RUN; then
				print_status "${dir} (~$(size_of "$dir")) would be cleaned" dry
			else
				local s
				s=$(size_of "$dir")
				sudo rm -rf "${dir:?}"/* 2>/dev/null || true
				print_status "Cleared ${dir} (~${s})" ok
				log "Cleared ${dir}"
			fi
		fi
	done
}

clean_fontconfig_cache() {
	if is_skipped "fontconfig"; then
		print_status "Fontconfig cache" skip
		return
	fi

	print_header "Cleaning fontconfig cache"
	log "Starting fontconfig cache cleanup"

	local fontconfig_dirs=(
		"/home/${REAL_USER}/.cache/fontconfig"
		"/root/.cache/fontconfig"
	)

	for dir in "${fontconfig_dirs[@]}"; do
		if [[ -d "$dir" ]]; then
			if $DRY_RUN; then
				print_status "${dir} (~$(size_of "$dir")) would be cleaned" dry
			else
				local s
				s=$(size_of "$dir")
				sudo rm -rf "${dir:?}"/* 2>/dev/null || true
				print_status "Cleared ${dir} (~${s})" ok
				log "Cleared ${dir}"
			fi
		fi
	done

	# Rebuild font cache
	if ! $DRY_RUN && command_exists fc-cache; then
		fc-cache -f 2>/dev/null || true
		print_status "Rebuilt font cache" ok
	fi
}

clean_core_dumps() {
	if is_skipped "coredumps"; then
		print_status "Core dumps" skip
		return
	fi

	print_header "Cleaning core dumps"
	log "Starting core dump cleanup"

	# systemd coredumps
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

	# /var/crash (Debian/Ubuntu)
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
		["VSCode"]="${HOME}/.cache/vscode"
		["Discord"]="${HOME}/.cache/discord"
		["Slack"]="${HOME}/.cache/Slack"
		["Spotify"]="${HOME}/.cache/spotify"
		["Element"]="${HOME}/.cache/element"
		["Signal"]="${HOME}/.cache/Signal"
	)

	# Also check legacy ~/.config locations
	local -A electron_apps_config=(
		["VSCode"]="${HOME}/.config/Code"
		["Discord"]="${HOME}/.config/discord"
		["Slack"]="${HOME}/.config/Slack"
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
		["Gradle"]="${HOME}/.gradle/caches"
		["Gradle wrapper"]="${HOME}/.gradle/wrapper/dists"
		["Maven"]="${HOME}/.m2/repository"
		["Ccache"]="${HOME}/.cache/ccache"
		["CMake"]="${HOME}/.cache/CMakeCache"
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

	# Also run ccache -C if available
	if command_exists ccache; then
		if ! $DRY_RUN; then
			ccache -C 2>/dev/null || true
			print_status "Reset ccache statistics" ok
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

	# Clean old dpkg logs (Debian/Ubuntu)
	if [[ -d /var/log/dpkg ]]; then
		if $DRY_RUN; then
			print_status "DPKG logs older than 90 days would be removed" dry
		else
			sudo find /var/log/dpkg -name 'dpkg.log.*.gz' -mtime +90 -delete 2>/dev/null || true
			print_status "Cleaned old DPKG logs" ok
		fi
	fi

	# Clean old apt logs (Debian/Ubuntu)
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
		vim_count=$(find "${HOME}" -maxdepth 5 \( -name '.*.swp' -o -name '.*.swo' \) -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | wc -l)
		emacs_count=$(find "${HOME}" -maxdepth 5 \( -name '\#*\#' -o -name '.\#*' \) -not -path '*/node_modules/*' 2>/dev/null | wc -l)
		nano_count=$(find "${HOME}" -maxdepth 5 -name '*~' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | wc -l)

		[[ $vim_count -gt 0 ]] && print_status "${vim_count} Vim swap files would be removed" dry
		[[ $emacs_count -gt 0 ]] && print_status "${emacs_count} Emacs auto-save files would be removed" dry
		[[ $nano_count -gt 0 ]] && print_status "${nano_count} Nano backup files would be removed" dry
	else
		local total=0

		# Vim swap files
		local vim_count
		vim_count=$(find "${HOME}" -maxdepth 5 \( -name '.*.swp' -o -name '.*.swo' \) -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | wc -l)
		if [[ $vim_count -gt 0 ]]; then
			find "${HOME}" -maxdepth 5 \( -name '.*.swp' -o -name '.*.swo' \) -not -path '*/node_modules/*' -not -path '*/.git/*' -delete 2>/dev/null || true
			total=$((total + vim_count))
		fi

		# Emacs auto-save files
		local emacs_count
		emacs_count=$(find "${HOME}" -maxdepth 5 \( -name '\#*\#' -o -name '.\#*' \) -not -path '*/node_modules/*' 2>/dev/null | wc -l)
		if [[ $emacs_count -gt 0 ]]; then
			find "${HOME}" -maxdepth 5 \( -name '\#*\#' -o -name '.\#*' \) -not -path '*/node_modules/*' -delete 2>/dev/null || true
			total=$((total + emacs_count))
		fi

		# Nano backup files
		local nano_count
		nano_count=$(find "${HOME}" -maxdepth 5 -name '*~' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | wc -l)
		if [[ $nano_count -gt 0 ]]; then
			find "${HOME}" -maxdepth 5 -name '*~' -not -path '*/node_modules/*' -not -path '*/.git/*' -delete 2>/dev/null || true
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
		"${HOME}/.cache/texmf"
		"${HOME}/.texlive"
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

	# Rebuild TeX filename database
	if ! $DRY_RUN && command_exists mktexlsr; then
		mktexlsr 2>/dev/null || true
		print_status "Rebuilt TeX filename database" ok
	fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
	parse_args "$@"
	ensure_root "$@"

	# Ensure log directory exists
	mkdir -p "$LOG_DIR" 2>/dev/null || true
	log "SysSweep v${VERSION} started (user: ${REAL_USER}, dry-run: ${DRY_RUN})"

	echo -e "\e[1;35m"
	echo "  ╔═══════════════════════════════════════════════════╗"
	echo "  ║          SysSweep v${VERSION}                     ║"
	echo "  ║        Linux System Cleanup Tool                 ║"
	echo "  ╚═══════════════════════════════════════════════════╝"
	echo -e "\e[0m"

	if $DRY_RUN; then
		echo -e "\e[1;33m  ⚡ DRY RUN MODE — nothing will be deleted\e[0m"
		echo ""
	fi

	# Show disk usage before
	echo -e "\e[1;34mDisk usage before cleanup:\e[0m"
	df -h / | tail -1 | awk '{printf "  Used: %s / %s (%s)\n", $3, $2, $5}'
	echo ""

	# Confirmation
	if ! $DRY_RUN; then
		if ! confirm "This will clean system caches and temporary files. Continue?"; then
			echo -e "\e[33mAborted.\e[0m"
			exit 0
		fi
		echo ""
	fi

	# Run all cleanup functions
	clean_temp_directories
	clean_trash_folders
	clean_journal_logs
	clean_flatpak_cache
	clean_docker
	clean_pacman_cache
	clean_pamac_cache
	clean_apt_cache
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

	# Show disk usage after
	echo ""
	echo -e "\e[1;34mDisk usage after cleanup:\e[0m"
	df -h / | tail -1 | awk '{printf "  Used: %s / %s (%s)\n", $3, $2, $5}'
	echo ""

	# Update locate database
	if command_exists updatedb; then
		if ! $DRY_RUN; then
			print_header "Updating locate database"
			sudo updatedb 2>/dev/null || true
			print_status "Locate database updated" ok
		fi
	fi

	echo ""
	echo -e "\e[1;32m══════════════════════════════════════════════════════\e[0m"
	echo -e "\e[1;32m  Cleanup complete! Log saved to: ${LOG_FILE}\e[0m"
	echo -e "\e[1;32m══════════════════════════════════════════════════════\e[0m"
	echo ""

	log "SysSweep completed"
}

main "$@"
