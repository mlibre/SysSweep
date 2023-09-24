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

# Function to find and delete .Trash folders
find_and_delete_trash_folders() {
	print_message "Cleaning .Trash folders"
	mounted_devices=$(df -h | awk 'NR > 1 {print $NF}')
	while read -r mount_point; do
		sudo rm -rfv "${mount_point}"/.Trash-*
	done <<<"$mounted_devices"
}

# Function to clean temporary directories
clean_temp_directories() {
	print_message "Cleaning temporary directories"
	sudo rm -rfv /tmp/*
	sudo rm -rfv /var/log/*
	sudo rm -rfv /var/tmp/*
	sudo rm -rfv ~/.local/share/Trash/info/*
	sudo rm -rfv ~/.local/share/Trash/files/*
	sudo rm -rfv /root/.local/share/Trash/info/*
	sudo rm -rfv /root/.local/share/Trash/files/*
	sudo rm -rfv ~/.npm/
	sudo rm -rfv /root/.npm
	sudo rm -rfv ~/.cache/ksycoca5*
	sudo rm -rfv /root/.cache/ksycoca5*
}

# Function to clean pacman cache
clean_pacman_cache() {
	if command_exists paccache; then
		print_message "Cleaning pacman cache"
		sudo paccache -r
		sudo paccache -ruk0
		sudo pacman -Rns $(pacman -Qdtq)
		sudo pacman -Rns $(pacman -Qdtq)
		yes | sudo pacman -Scc
	fi
}

# Function to clean thumbnail cache
clean_thumbnail_cache() {
	print_message "Cleaning thumbnail cache"
	rm -rfv ~/.cache/thumbnails/*
}

# Function to vacuum journal logs
clean_journal_logs() {
	if command_exists journalctl; then
		print_message "Cleaning journal logs"
		sudo journalctl --vacuum-time=7d
		sudo journalctl --flush
	fi
}

# Function to clean with pamac
clean_with_pamac() {
	if command_exists pamac; then
		print_message "Cleaning with pamac"
		sudo pamac clean --keep 0 --no-confirm
	fi
}

# Function to clean npm cache
clean_npm_cache() {
	if command_exists npm; then
		print_message "Cleaning npm cache"
		npm cache clean -f
		sudo npm cache clean -f
	fi
}

# Function to clean yarn cache
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
	find_and_delete_trash_folders
	clean_temp_directories
	clean_pacman_cache
	clean_with_pamac
	clean_thumbnail_cache
	vacuum_journal_logs
	clean_npm_cache
	clean_yarn_cache
	update_locate_database

	# Display disk space usage
	print_message "Disk space usage:"
	df -h
}

# Call the main function to execute all cleanup tasks
main
