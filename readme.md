# Sys Sweep

![image](./nice.jpg)

Welcome to the **SysSweep**! This is a powerful bash script that helps you clean up temporary files, caches, and reclaim disk space on your Linux system. Say goodbye to digital clutter and hello to a cleaner, faster system.

## Features

- Removes temporary files and directories
- Cleans up `.Trash` folders from all mounted devices
- Cleans packages caches and orphaned packages
- Purges thumbnail cache
- Cleans journal logs
- Cleans npm and yarn caches
- Displays disk space usage summary
- Cleans up Flatpak, Docker, pip cache
- Updates the locate database

## Usage

1. Clone this repository to your Linux system.

   ```bash
   git clone https://github.com/mlibre/SysSweep
   cd SysSweep
   ```

2. Make the script executable.

   ```bash
   chmod +x syssweep.bash
   ```

3. Run the script with and without root privileges

   ```bash
   ./syssweep.bash
   sudo ./syssweep.bash
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
