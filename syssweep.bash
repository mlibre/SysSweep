#!/bin/bash

# Clean up package cache
sudo paccache -r
sudo paccache -ruk0

# Clean up thumbnail cache
rm -rf ~/.cache/thumbnails/*

# Remove orphaned packages
sudo pacman -Rns $(pacman -Qdtq)
sudo pacman -Rns $(pacman -Qdtq)
yes | sudo pacman -Scc

sudo journalctl --vacuum-time=7d
sudo journalctl --flush

sudo rm -rf /tmp/*
sudo rm -rf /var/log/*
sudo rm -rf /var/tmp/*
sudo rm -rf ~/.local/share/Trash/info/*
sudo rm -rf ~/.local/share/Trash/files/*
sudo rm -rf /root/.local/share/Trash/info/*
sudo rm -rf /root/.local/share/Trash/files/*

# Remove old versions of installed packages
sudo pamac clean --keep 0 --no-confirm

npm cache clean -f
rm -r ~/.npm/
sudo npm cache clean -f
sudo rm -r /root/.npm
yarn cache clean

# Update the file database for locate command
sudo updatedb

# Display disk space usage
df -h
