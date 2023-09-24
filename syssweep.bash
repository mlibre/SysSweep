#!/bin/bash

# Function to check if a command exists
command_exists() {
	type "$1" &>/dev/null
}

sudo rm -rf /tmp/*
sudo rm -rf /var/log/*
sudo rm -rf /var/tmp/*
sudo rm -rf ~/.local/share/Trash/info/*
sudo rm -rf ~/.local/share/Trash/files/*
sudo rm -rf /root/.local/share/Trash/info/*
sudo rm -rf /root/.local/share/Trash/files/*

# Clean up package cache if paccache command exists
if command_exists paccache; then
	sudo paccache -r
	sudo paccache -ruk0
fi

# Clean up thumbnail cache
rm -rf ~/.cache/thumbnails/*

# Remove orphaned packages if pacman command exists
if command_exists pacman; then
	sudo pacman -Rns $(pacman -Qdtq)
	sudo pacman -Rns $(pacman -Qdtq)
	yes | sudo pacman -Scc
fi

# Vacuum journal logs if journalctl command exists
if command_exists journalctl; then
	sudo journalctl --vacuum-time=7d
	sudo journalctl --flush
fi

# Clean up using pamac if pamac command exists
if command_exists pamac; then
	sudo pamac clean --keep 0 --no-confirm
fi

# Clean up npm and yarn caches if npm and yarn commands exist
if command_exists npm; then
	npm cache clean -f
	rm -r ~/.npm/
	sudo npm cache clean -f
	sudo rm -r /root/.npm
fi

if command_exists yarn; then
	yarn cache clean
fi

# Update the file database for locate command if updatedb command exists
if command_exists updatedb; then
	sudo updatedb
fi

# Display disk space usage
df -h
