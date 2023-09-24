#!/bin/bash

# Function to check if a command exists
command_exists() {
	type "$1" &>/dev/null
}

# Function to print colored messages
print_message() {
	local message="$1"
	local color_code="$2"
	local emoji="☀️"

	# Add some space before and after the message
	echo -e ""
	echo -e "\e[${color_code}m${emoji}  ${message}  ${emoji}\e[0m"
	echo -e ""
}

# Print a message before cleaning temporary directories
print_message "Cleaning temporary directories..." 32 # 32 is the color code for green

# Clean up temporary directories
sudo rm -rf /tmp/*
sudo rm -rf /var/log/*
sudo rm -rf /var/tmp/*
sudo rm -rf ~/.local/share/Trash/info/*
sudo rm -rf ~/.local/share/Trash/files/*
sudo rm -rf /root/.local/share/Trash/info/*
sudo rm -rf /root/.local/share/Trash/files/*

# Clean up package cache if paccache command exists
if command_exists paccache; then
	print_message "Cleaning package cache..." 33 # 33 is the color code for yellow
	sudo paccache -r
	sudo paccache -ruk0
fi

# Clean up thumbnail cache
print_message "Cleaning thumbnail cache..." 34 # 34 is the color code for blue
rm -rf ~/.cache/thumbnails/*

# Remove orphaned packages if pacman command exists
if command_exists pacman; then
	print_message "Removing orphaned packages..." 35 # 35 is the color code for magenta
	sudo pacman -Rns $(pacman -Qdtq)
	sudo pacman -Rns $(pacman -Qdtq)
	yes | sudo pacman -Scc
fi

# Vacuum journal logs if journalctl command exists
if command_exists journalctl; then
	print_message "Vacuuming journal logs..." 36 # 36 is the color code for cyan
	sudo journalctl --vacuum-time=7d
	sudo journalctl --flush
fi

# Clean up using pamac if pamac command exists
if command_exists pamac; then
	print_message "Cleaning with pamac..." 31 # 31 is the color code for red
	sudo pamac clean --keep 0 --no-confirm
fi

# Clean up npm and yarn caches if npm and yarn commands exist
if command_exists npm; then
	print_message "Cleaning npm cache..." 35 # 35 is the color code for magenta
	npm cache clean -f
	rm -r ~/.npm/
	sudo npm cache clean -f
	sudo rm -r /root/.npm
fi

if command_exists yarn; then
	print_message "Cleaning yarn cache..." 36 # 36 is the color code for cyan
	yarn cache clean
fi

# Update the file database for locate command if updatedb command exists
if command_exists updatedb; then
	print_message "Updating locate database..." 31 # 31 is the color code for red
	sudo updatedb
fi

# Display disk space usage
print_message "Disk space usage:" 33 # 33 is the color code for yellow
df -h
