# Sys Sweep

![Magic](./nice.jpg)

Welcome to the **SysSweep**! This is a powerful bash script that helps you clean up temporary files, caches, and reclaim disk space on your Linux system. Say goodbye to digital clutter and hello to a cleaner, faster system.

## Features

- Removes temporary files and directories
- Cleans package cache
- Purges thumbnail cache
- Removes orphaned packages
- Vacuum journal logs
- Cleans npm and yarn caches (if you're a Node.js wizard)
- Updates the locate database
- Displays disk space usage summary

## Usage

1. Clone this repository to your Linux system.

   ```bash
   git clone https://github.com/mlibre/SysSweep
   cd SysSweep
   ```

2. Make the script executable.

   ```bash
   chmod +x SysSweep.bash
   ```

3. Run the script with root privileges (use `sudo`).

   ```bash
   sudo ./SysSweep.bash
   ```

4. Watch the magic happen as it cleans up your system!

## Requirements

- A Linux-based operating system
- Depending on the package manager used, certain functions may require specific packages (e.g., `paccache` for Pacman-based systems)

## Contribution

Contributions and improvements to this spell are welcome! Feel free to fork this repository and submit pull requests.

## License

This project is licensed under the CC0

Happy spellcasting and enjoy your squeaky clean Linux system!
