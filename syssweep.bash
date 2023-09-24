#!/bin/bash

# Function to check if a command exists
command_exists() {
	type "$1" &>/dev/null
}

# Function to print colored messages
print_message() {
	local message="$1"
	local emoji="☀️"
	local color_code=$((31 + RANDOM % 6))

	# Add some space before and after the message
	echo -e ""
	echo -e "\e[${color_code}m${emoji}  ${message}  ${emoji}\e[0m"
	echo -e ""
}

clean_temp_directories() {
	print_message "Cleaning temporary directories"
	sudo rm -rfv /tmp/*
	sudo rm -rfv /var/tmp/*
	sudo rm -rfv /var/log/*
	sudo rm -rfv ~/.local/share/Trash/info/*
	sudo rm -rfv ~/.local/share/Trash/files/*
	sudo rm -rfv /root/.local/share/Trash/info/*
	sudo rm -rfv /root/.local/share/Trash/files/*
	sudo rm -rfv ~/.npm/
	sudo rm -rfv /root/.npm
	sudo rm -rfv ~/.cache/ksycoca5*
	sudo rm -rfv /root/.cache/ksycoca5*
	sudo rm -rfv ~/.cache/thumbnails/*
}

find_and_delete_trash_folders() {
	print_message "Cleaning .Trash folders"
	mounted_devices=$(df -h | awk 'NR > 1 {print $NF}')
	while read -r mount_point; do
		sudo rm -rfv "${mount_point}"/.Trash-*
	done <<<"$mounted_devices"
}

clean_flatpak_cache() {
	if command_exists flatpak; then
		print_message "Cleaning flatpak cache"
		flatpak uninstall --unused -y --force-remove
		sudo flatpak uninstall --unused -y --force-remove
	fi
}

clean_pacman_cache() {
	if command_exists paccache; then
		print_message "Cleaning pacman cache"
		sudo paccache -r
		sudo paccache -ruk0
		yes | sudo pacman -Rns $(pacman -Qdtq)
		yes | sudo pacman -Rns $(pacman -Qdtq)
		yes | sudo pacman -Scc
	fi
}

clean_pamac_cache() {
	if command_exists pamac; then
		print_message "Cleaning with pamac"
		sudo pamac clean --keep 0 --no-confirm
	fi
}

clean_apt_cache() {
	if command_exists apt; then
		print_message "Cleaning pacman cache"
		sudo apt autoremove --purge
		sudo apt clean
		sudo apt -s clean
		sudo apt clean all
	fi
	if command_exists apt-get; then
		print_message "Cleaning pacman cache"
		sudo apt-get autoremove --purge
		sudo apt-get clean
		sudo apt-get -s clean
		sudo apt-get clean all
		sudo apt-get autoclean
	fi
}

clean_journal_logs() {
	if command_exists journalctl; then
		print_message "Cleaning journal logs"
		sudo journalctl --vacuum-time=7d
		sudo journalctl --flush
	fi
}

clean_python_cache() {
	if command_exists pip; then
		print_message "Cleaning pip and Python caches"
		pip cache purge
		sudo pip cache purge
		sudo find /usr/lib/python* -name '__pycache__' -exec rm -r {} +
		sudo find /home/mlibre/.local/lib/python* -name '__pycache__' -exec rm -r {} +
	fi
}

clean_npm_cache() {
	if command_exists npm; then
		print_message "Cleaning npm cache"
		npm cache clean -f
		sudo npm cache clean -f
	fi
}

clean_yarn_cache() {
	if command_exists yarn; then
		print_message "Cleaning yarn cache"
		yarn cache clean
	fi
}

# Function to update locate database
update_locate_database() {
	if command_exists updatedb; then
		print_message "Updating locate database"
		sudo updatedb
	fi
}

# Main function to perform all cleanup tasks
main() {
	clean_temp_directories
	find_and_delete_trash_folders
	clean_flatpak_cache
	clean_pacman_cache
	clean_pamac_cache
	clean_apt_cache
	clean_journal_logs
	clean_python_cache
	clean_npm_cache
	clean_yarn_cache
	update_locate_database

	# Display disk space usage
	print_message "Disk space usage:"
	df -h
}

# Call the main function to execute all cleanup tasks
main
