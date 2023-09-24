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

find_and_delete_trash_folders() {
	print_message "Cleaning .Trash folders..."
	mounted_devices=$(df -h | awk 'NR > 1 {print $NF}')
	while read -r mount_point; do
		sudo rm -rfv "${mount_point}"/.Trash-*
	done <<<"$mounted_devices"
}

# Print a message before cleaning temporary directories
print_message "Cleaning temporary directories..."

# Clean up temporary directories
sudo rm -rfv /tmp/*
sudo rm -rfv /var/log/*
sudo rm -rfv /var/tmp/*
sudo rm -rfv ~/.local/share/Trash/info/*
sudo rm -rfv ~/.local/share/Trash/files/*
sudo rm -rfv /root/.local/share/Trash/info/*
sudo rm -rfv /root/.local/share/Trash/files/*

find_and_delete_trash_folders

# Clean up package cache if paccache command exists
if command_exists paccache; then
	print_message "Cleaning package cache..."
	sudo paccache -r
	sudo paccache -ruk0
fi

# Clean up thumbnail cache
print_message "Cleaning thumbnail cache..."
rm -rfv ~/.cache/thumbnails/*

# Remove orphaned packages if pacman command exists
if command_exists pacman; then
	print_message "Removing orphaned packages..."
	sudo pacman -Rns $(pacman -Qdtq)
	sudo pacman -Rns $(pacman -Qdtq)
	yes | sudo pacman -Scc
fi

# Vacuum journal logs if journalctl command exists
if command_exists journalctl; then
	print_message "Vacuuming journal logs..."
	sudo journalctl --vacuum-time=7d
	sudo journalctl --flush
fi

# Clean up using pamac if pamac command exists
if command_exists pamac; then
	print_message "Cleaning with pamac..."
	sudo pamac clean --keep 0 --no-confirm
fi

# Clean up npm and yarn caches if npm and yarn commands exist
if command_exists npm; then
	print_message "Cleaning npm cache..."
	npm cache clean -f
	rm -rfv ~/.npm/
	sudo npm cache clean -f
	sudo rm -rfv /root/.npm
fi

if command_exists yarn; then
	print_message "Cleaning yarn cache..."
	yarn cache clean
fi

# Update the file database for locate command if updatedb command exists
if command_exists updatedb; then
	print_message "Updating locate database..."
	sudo updatedb
fi

# Display disk space usage
print_message "Disk space usage:"
df -h
