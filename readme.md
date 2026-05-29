# SysSweep

![image](./nice.jpg)

A safe Linux system cleanup script that removes temporary files, caches, and reclaimable disk space. Features dry-run mode, skip flags, and automatic sudo escalation.

## Features

### System Cleanup

- **Temporary files** — cleans `/tmp` and `/var/tmp` (files older than 1 day only)
- **Trash folders** — removes `.Trash-*` from all mounted devices
- **Journal logs** — vacuums systemd journal to 3 days
- **Old rotated logs** — removes compressed/rotated logs older than 90 days
- **Core dumps** — cleans systemd coredumps and crash dumps

### Package Managers

- **Pacman** — removes old cached packages, orphans, and unused versions
- **Pamac** — cleans package cache
- **APT** — autoremoves and cleans package cache (Debian/Ubuntu)
- **Flatpak** — removes unused runtimes
- **Snap** — cleans snap cache and thumbnails

### Application Caches

- **Docker** — prunes images, containers, networks, and volumes
- **Electron apps** — clears VSCode, Discord, Slack, Signal, Element caches
- **pip/Python** — purges pip cache and `__pycache__` directories
- **npm** — cleans npm cache
- **Yarn** — cleans yarn cache

### Build Tool Caches

- **Cargo** — cleans Rust registry cache
- **Go** — cleans Go build cache
- **Gradle** — clears Gradle caches and wrapper
- **Maven** — cleans Maven repository
- **Ccache** — resets compiler cache

### Other Caches

- **Mesa shader cache** — clears GPU shader compilation cache
- **Fontconfig cache** — clears font cache and rebuilds it
- **TeX/LaTeX** — clears TeX cache and rebuilds filename database
- **Thumbnail cache** — clears thumbnail cache
- **KDE ksycoca5** — clears KDE system configuration cache

### Editor Artifacts

- **Vim swap files** — removes `.*.swp`, `.*.swo`
- **Emacs auto-save** — removes `\#*#`, `.\#*`
- **Nano backups** — removes `*~` files

### Misc

- **Locate database** — updates `updatedb` after cleanup

## Usage

1. Clone this repository:

   ```bash
   git clone https://github.com/mlibre/SysSweep
   cd SysSweep
   ```

2. Make the script executable:

   ```bash
   chmod +x syssweep.bash
   ```

3. Run the script (sudo is requested automatically):

   ```bash
   ./syssweep.bash
   ```

### Options

| Flag            | Description                                             |
| --------------- | ------------------------------------------------------- |
| `--dry-run`     | Preview what would be deleted without deleting anything |
| `--skip <name>` | Skip a specific cleanup (repeatable)                    |
| `--help`        | Show help message                                       |
| `--version`     | Show version number                                     |

### Examples

```bash
# Preview all cleanups
./syssweep.bash --dry-run

# Skip Docker and Flatpak cleanup
./syssweep.bash --skip docker --skip flatpak

# Skip multiple cleanups
./syssweep.bash --skip pacman --skip apt --skip docker
```

### Skip Names

| Name         | What it skips                                      |
| ------------ | -------------------------------------------------- |
| `temp`       | Temporary directories (`/tmp`, `/var/tmp`)         |
| `trash`      | `.Trash` folders on mounted devices                |
| `journal`    | Systemd journal logs                               |
| `flatpak`    | Flatpak unused runtimes                            |
| `docker`     | Docker images, containers, volumes                 |
| `pacman`     | Pacman package cache                               |
| `pamac`      | Pamac package cache                                |
| `apt`        | APT package cache                                  |
| `python`     | pip cache and `__pycache__`                        |
| `npm`        | npm cache                                          |
| `yarn`       | yarn cache                                         |
| `cargo`      | Cargo/Rust registry cache                          |
| `go`         | Go build cache                                     |
| `snap`       | Snap cache and thumbnails                          |
| `mesa`       | Mesa shader cache                                  |
| `fontconfig` | Fontconfig cache                                   |
| `coredumps`  | Core dumps and crash dumps                         |
| `electron`   | Electron app caches (VSCode, Discord, Slack, etc.) |
| `buildtools` | Gradle, Maven, Ccache, CMake caches                |
| `oldlogs`    | Old rotated log files                              |
| `swaps`      | Editor swap/backup files                           |
| `tex`        | TeX/LaTeX cache                                    |

## Safety

- Only removes files older than 1 day from `/tmp` and `/var/tmp`
- Automatically requests sudo when needed
- Single confirmation prompt before any cleanup
- `--dry-run` mode to preview changes
- All actions logged to `~/.local/share/syssweep.log`
- Skips running applications' caches when detected
- Handles permission errors gracefully

## Contribution

Contributions and improvements are welcome! Feel free to fork this repository and submit pull requests.

## License

This project is licensed under the CC0.

Happy sweeping and enjoy your squeaky clean Linux system!
