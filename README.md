# Conty

[![Conty CI](https://github.com/Kron4ek/Conty/actions/workflows/conty.yml/badge.svg)](https://github.com/Kron4ek/Conty/actions/workflows/conty.yml) [![Utils CI](https://github.com/Kron4ek/Conty/actions/workflows/utils.yml/badge.svg)](https://github.com/Kron4ek/Conty/actions/workflows/utils.yml)

This is an easy to use compressed unprivileged Linux container packed into a single executable that works on most Linux distros. You can use it to run any applications, including games ([Vulkan](https://en.wikipedia.org/wiki/Vulkan) and [OpenGL](https://en.wikipedia.org/wiki/OpenGL)).

## Features

* A single executable - download (or create) and run, nothing else is required. And it's portable, you can put it anywhere (even on a usb stick).
* Works on most Linux distros, even very old ones and even without glibc (such as Alpine or Void or Gentoo with musl).
* Works on Steam Deck.
* Root rights are **not required**.
* Compressed (with [squashfs](https://en.wikipedia.org/wiki/SquashFS) or dwarfs), so it takes a lot less disk space than uncompressed containers and can provide faster filesystem access in some cases.
* Contains many packages and libraries, it can run almost everything, and you don't need to install anything on your main (host) system. **You can even run 32-bit applications on pure 64-bit systems**.
* Based on [Arch Linux](https://en.wikipedia.org/wiki/Arch_Linux), contains modern software (including fresh videodrivers).
* Almost completely seamless experience. All applications that you run with Conty read and store their configs in your $HOME directory as if you weren't using the container at all.
* No performance overhead. Since it's just a container, there is virtually no performance overhead, all applications will run at full speed. Regarding memory usage, Conty uses a bit more memory due to compression and because applications from the container can't share libraries with your system apps.
* Supports Xorg, Wayland and XWayland.
* Supports filesystem and X11 sandboxing (thanks to bubblewrap and [xephyr](https://en.wikipedia.org/wiki/Xephyr)).
* Supports Chaotic-AUR and ALHP repositories. AUR is also supported.

In its default release, it includes, among others, these apps:
[Wine-Proton](https://en.wikipedia.org/wiki/Proton_(software)),
[Steam](https://en.wikipedia.org/wiki/Steam_(service)),
[Lutris](https://en.wikipedia.org/wiki/Lutris),
[PlayOnLinux](https://en.wikipedia.org/wiki/PlayOnLinux),
[GameHub](https://github.com/tkashkin/GameHub),
[Minigalaxy](https://sharkwouter.github.io/minigalaxy),
[Legendary](https://github.com/derrod/legendary),
[Bottles](https://usebottles.com),
[Faugus Launcher](https://github.com/Faugus/faugus-launcher),
[PrismLauncher](https://prismlauncher.org),
[MangoHud](https://github.com/flightlessmango/MangoHud),
[Gamescope](https://github.com/ValveSoftware/gamescope),
[RetroArch](https://www.retroarch.com),
[DuckStation](https://www.duckstation.org/),
[PCSX2 PlayStation 2 emulator](https://pcsx2.net),
[Sunshine](https://github.com/LizardByte/Sunshine),
[Genymotion](https://www.genymotion.com/),
[OBS Studio](https://obsproject.com/),
[OpenJDK](https://en.wikipedia.org/wiki/OpenJDK),
[Firefox](https://en.wikipedia.org/wiki/Firefox)

The full list can be read in the [latest release's pkg_list.txt](https://github.com/Kron4ek/Conty/releases/latest/download/pkg_list.txt).

If these applications are not enough, you can install additional applications or run external binaries from, for example, your home directory.

## Navigate

<details><summary>Expand</summary><p>

  * [Getting Started](#getting-started)
    + [Download](#download)
    + [Requirements](#requirements)
  * [Usage](#usage)
    + [GUI](#gui)
    + [CLI](#cli)
  * [Managing](#managing)
    + [Install Conty](#install-conty)
    + [How to update](#how-to-update)
  * [How to create your own Conty executables](#how-to-create-your-own-conty-executables)
    + [Manual](#manual)
    + [Automated (GitHub Actions)](#automated-github-actions)
  * [Useful Tips](#useful-tips)
    + [Sandbox](#sandbox)
    + [About Wine](#about-wine)
  * [Known issues](#known-issues)
  * [Main used projects](#main-used-projects)

<small><i><a href='http://ecotrust-canada.github.io/markdown-toc/'>Table of contents generated with markdown-toc</a></i></small>

</p></details>

## Getting Started

### Download

You can download a ready-to-use release from the [**releases**](https://github.com/Kron4ek/Conty/releases) page or create your own (the instructions are [below](#how-to-create-your-own-conty-executables)). Make it executable via `chmod` or your file manager's Properties option (right-click or Alt+Enter) before running.

```
$ chmod +x conty.sh
```

Chmod only need to be executed once (per file). You can now [start using Conty](#usage).

Or you can install from [gentoo-zh overlay](https://github.com/microcai/gentoo-zh/tree/master/games-emulation/conty).

###  Requirements

The only requirements are `fuse3` (or `fuse2`) and `coreutils` (or other POSIX compliant basic utilities). And your `/tmp` directory should allow files execution (which it does by default on most distros).

Your Linux kernel must be at least version 4.4 and should support unprivileged user namespaces. On some Linux distros this feature is disabled by default and can be enabled with sysfs:

```
# sysctl kernel.unprivileged_userns_clone=1
```

On Ubuntu 24.04+ (and maybe some other distros with apparmor enabled) it is needed to disable `kernel.apparmor_restrict_unprivileged_userns` sysctl option.

```
# sysctl kernel.apparmor_restrict_unprivileged_userns=0
```

Even if unprivileged user namespaces are not supported by your kernel, you can still use Conty if you have bubblewrap with the SUID bit installed on your system, in this case just tell Conty to use system-wide utils instead of the builtin ones.

```
$ export USE_SYS_UTILS=1
$ ./conty.sh command command_arguments
```

If you plan to run 32-bit applications, your kernel must be compiled with **CONFIG_IA32_EMULATION** and **CONFIG_COMPAT_32BIT_TIME** options enabled. Kernels in most Linux distributions have these options enabled by default.

## Usage

### CLI

Conty can be run from a terminal emulator. To run a program inside Conty, simply put the path to `conty.sh` as a prefix and then insert the program's binary name or the full path to it and launch arguments (if needed).
```
$ ./conty.sh [command] [command_arguments]
```
Examples:
```
$ ./conty.sh steam
$ ./conty.sh bottles
$ ./conty.sh /usr/bin/steam
$ ./conty.sh mangohud glxgears
$ WINEPREFIX=$HOME/wine-conty ./conty.sh gamescope -f -- wine ./game.exe
```

### GUI

Running Conty from a terminal emulator is not strictly required, if your file manager allows running executables, you can also run Conty from it in which case it will show its graphical interface. You can also manually invoke the GUI from terminal with `conty.sh -g`.

![gui](https://github.com/Kron4ek/Conty/assets/13851877/05856085-1925-47fa-a2ad-4f6165562d8b)

Currently, to check the binaries / commands in Conty, you can use "Select File" and browsing to the `/usr/bin` directory, or by using `ls /usr/bin` using the "Open a terminal" option.

However, the GUI will not notify you about errors, so i recommend running Conty from a terminal emulator to see if there are any errors, at least if you've never used Conty before.

---
There are many packages and usecases that are included in the default `conty.sh` from the releases page, such as:

<details><summary>File manager</summary><p>

It has a builtin file manager (pcmanfm):

```
$ ./conty.sh pcmanfm
```

You can also install your own file manager if you want to, but note that file manager will browse the root inside of Conty except for directories that are mounted from the user's root. `/home` is mounted by Conty to allow access to the user's home files.

</p></details>

<details><summary>Checking hardware acceleration</summary><p>

To check if hardware acceleration (OpenGL and Vulkan) works, you can use these tools:

```
$ ./conty.sh glxinfo -B
$ ./conty.sh glxgears
$ ./conty.sh vulkaninfo
$ ./conty.sh vkcube
```

</p></details>

<details><summary>Using Conty as build environment</summary><p>

You can even use Conty for compilation:

```
$ ./conty.sh gcc src.c
$ ./conty.sh git clone https://something.git
$ cd something && ./conty.sh ./configure
$ ./conty.sh make
```

</p></details>

<details><summary>Listing binaries inside Conty</summary><p>

There are many more integrated programs. You can list all of them with:

```
$ ./conty.sh ls /usr/bin
$ ./conty.sh ls /opt
```

</p></details>

<details><summary>Executing user's binaries </summary><p>

It is also possible to run binaries from your storage. For example, if you want to run an application that resides on your HOME, run something like:

```
$ ./conty.sh /home/username/SomeApplication/binaryfile
```

Note that you cannot run AppImage from Conty (this includes AppImage installed from AUR through Conty's package manager) except for extracting the AppImage's content, after which you may use the manually extracted content.

</p></details>

There are many other features, see the internal help for more information.

```
$ ./conty.sh -h
```

<details><summary>Help Content</summary><p>

```
Usage: conty.sh [COMMAND] [ARGUMENTS]


Arguments:
  -e    Extract the image

  -h    Display this text

  -H    Display bubblewrap help

  -g    Run the Conty's graphical interface

  -l    Show a list of all installed packages

  -d    Export desktop files from Conty into the application menu of
        your desktop environment.
        Note that not all applications have desktop files, and also that
        desktop files are tied to the current location of Conty, so if
        you move or rename it, you will need to re-export them.
        To remove the exported files, use this argument again.

  -m    Mount/unmount the image
        The image will be mounted if it's not, unmounted otherwise.
        Mount point can be changed with the BASE_DIR env variable
        (the default is /tmp).

  -o    Show the image offset

  -u    Update all packages inside the container
        This requires a rebuild of the image, which may take quite
        a lot of time, depending on your hardware and internet speed.
        Additional disk space (about 6x the size of the current file)
        is needed during the update process.

  -v    Display version of this script

  -V    Display version of the image

Arguments that don't match any of the above will be passed directly to
bubblewrap, so all bubblewrap arguments are supported as well.


Environment variables:
  BASE_DIR          Sets a custom directory where Conty will extract its
                    builtin utilities and mount the image.
                    The default is /tmp.

  DISABLE_NET       Disables network access.

  DISABLE_X11       Disables access to X server.

                    Note: Even with this variable enabled applications
                    can still access your X server if it doesn't use
                    XAUTHORITY and listens to the abstract socket. This
                    can be solved by enabling XAUTHORITY, disabling the
                    abstract socket or by disabling network access.

  HOME_DIR          Sets the home directory to a custom location.
                    For example: HOME_DIR="/home/user/custom_home"
                    Note: If this variable is set the home directory
                    inside the container will still appear as /home/user,
                    even though the custom directory is used.

  QUIET_MODE        Disables all non-error Conty messages.
                    Doesn't affect the output of applications.

  SANDBOX           Enables a sandbox.
                    To control which files and directories are available
                    inside the container, you can use the --bind and
                    --ro-bind launch arguments.
                    (See bubblewrap help for more info).

  SANDBOX_LEVEL     Controls the strictness of the sandbox.
                    Available levels:
                      1: Isolates all user files.
                      2: Additionally disables dbus and hides all
                         running processes.
                      3: Additionally disables network access and
                         isolates X11 server with Xephyr.
                    The default is 1.

  USE_OVERLAYFS     Mounts a writable unionfs-fuse filesystem on top
                    of the read-only squashfs/dwarfs image, allowing to
                    modify files inside it.
                    Overlays are stored in ~/.local/share/Conty. If you
                    want to undo any changes, delete the entire
                    directory from there.

  NVIDIA_HANDLER    Fixes issues with graphical applications on Nvidia
                    GPUs with the proprietary driver. Enable this only
                    if you are using an Nvidia GPU, the proprietary
                    driver and encountering issues running graphical
                    applications. At least 2 GB of free disk space is
                    required. This function is enabled by default.

  USE_SYS_UTILS     Tells the script to use squashfuse/dwarfs and bwrap
                    installed on the system instead of the builtin ones.

  XEPHYR_SIZE       Sets the size of the Xephyr window. The default is
                    800x600.

  CUSTOM_MNT        Sets a custom mount point for the Conty. This allows
                    Conty to be used with already mounted filesystems.
                    Conty will not mount its image on this mount point,
                    but it will use files that are already present
                    there.

Additional notes:
System directories/files will not be available inside the container if
you set the SANDBOX variable but don't bind (mount) any items or set
HOME_DIR. A fake temporary home directory will be used instead.

If the executed script is a symlink with a different name, said name
will be used as the command name.
For instance, if the script is a symlink with the name "wine" it will
automatically run wine during launch.

Running Conty without any arguments from a graphical interface (for
example, from a file manager) will automatically launch the Conty's
graphical interface.

Besides updating all packages, you can also install and remove packages
using the same -u argument. To install packages add them as additional
arguments, to remove add a minus sign (-) before their names.
  To install: conty.sh -u pkgname1 pkgname2 pkgname3 ...
  To remove: conty.sh -u -pkgname1 -pkgname2 -pkgname3 ...
In this case Conty will update all packages and additionally install
and/or remove specified packages.

If you are using an Nvidia GPU, please read the following:
https://github.com/Kron4ek/Conty#known-issues
```

</p></details>

## Managing

### Install Conty

Much like an AppImage, there is no need to install Conty. However, many distribution includes `$HOME/.local/bin` as part of their `PATH` should the folder exists. You may put Conty there, so that it can be accessed from terminal using `conty.sh` without inputting the full path.

<details><summary>Checking and adding PATH</summary><p>

To check if you have the directory inside your `PATH`, first create the folder, and then use `echo $PATH`. If your distribution does not include the directory, you can add it by adding `export PATH=$PATH:$HOME/.local/bin` somewhere inside the `~/.bashrc` file.

</p></details>

In addition, Conty can batch export all .desktop files inside Conty's `/usr/share/applications` to user's `$XDG_DATA_HOME/applications/Conty`  folder (typically means `~/.local/share/applications/Conty`) so that the applications installed in Conty can be accessed from user's application launcher.

To do so, open the terminal, and type:

```
$ ./conty.sh -d
```

This command will create the folder and export the files there, append `Conty` to all exported application's name and .desktop filename, and insert Conty's path to the executable path as a prefix. In addition, it will also export all environment variables and arguments relating to Conty, such as [sandboxing options](#sandbox).

<details><summary>Example</summary><p>

Conty is located in `$HOME/.local/bin/conty.sh`. Then, you ran the following command:

```
$ HOME_DIR=$HOME/Documents/Conty conty.sh --bind $HOME/.steam $HOME/.steam
```

Firefox (and other apps) will be exported to `~/.local/share/applications/Conty` as `firefox-conty.desktop`, it will show up in your menu as `Firefox (Conty)`, and the `Exec=` line inside the exported file will be changed from `env UBUNTU_MENUPROXY=0 /usr/lib/firefox/firefox` to `env HOME_DIR="/home/$USER/Documents/Conty" "/home/$USER/.local/bin/conty.sh" --bind /home/$USER/.steam /home/$USER/.steam env UBUNTU_MENUPROXY=0 /usr/lib/firefox/firefox`.

</p></details>

If `$XDG_DATA_HOME/applications/Conty` already exists, `conty.sh -d` will instead delete the folder. If you have modified any .desktop files inside that folder, it is recommended for you to move or back it up to a different folder.

### How to update

There are a few ways to update Conty and get the latest packages, use whichever works best for you.

* First of all, you can simply download latest release from the [releases page](https://github.com/Kron4ek/Conty/releases), i usually upload a new release about every month.
* You can manually create a Conty executable with latest packages inside, read the [How to create your own Conty executables](#how-to-create-your-own-conty-executables) section below.
* You can clone the repository and [use GitHub Actions](#automated-github-actions) to get new Conty file according your specifications, every week (see Automated section below).

## How to create your own Conty executables

### Manual

1. Obtain Arch Linux bootstrap by using `create-arch-bootstrap.sh`. Before running it, you can edit variables in `settings.sh` if you want, for example, to include a different set of packages inside the container, or to include additional locales. Make sure you have enough free disk space, i recommend at least 10 GB of free space. Root rights are required for this step.

    ```
    # ./create-arch-bootstrap.sh
    ```
2. After that you can use `enter-chroot.sh` to chroot into the bootstrap and do some manual modifications (for instance, modify some files, install/remove packages, etc.). Root rights are needed for this step too. This is an optional step, which you can skip if you wish.

    ```
    # ./enter-chroot.sh
    ```
3. Now use `create-conty.sh` to create a SquashFS (or DwarFS) image and create a ready-to-use Conty executable. Root rights are not needed for this step. By default a SquashFS image with zstd compression (level 19) will be created, however, if you want, you can edit variables in `settings.sh` and enable DwarFS, select a different compression algorithm and/or compression level.

    ```
    $ ./create-conty.sh
    ```

For the sake of convenience, there are pre-compiled binaries (utils.tar.gz) of bwrap, squashfuse and dwarfs and their dependencies uploaded in this repo, `create-conty.sh` uses them by default. If you want, you can compile your own binaries by using `create-utils.sh`, it will compile all needed programs and create utils.tar.gz.

### Automated (GitHub Actions)

This repository has GitHub workflows that allows you to make GitHub automatically generate a new Conty binary of your specification, every week or at any time you want.

To start, first fork this repository. Then, you may edit the `settings.sh` inside the new repository, to build the packages you want & change compression settings. Then go to the Actions tab.

In the Actions tab, go to the Conty CI section in the left-hand menu. Choose "Run Workflow". This will make GitHub make you a new Conty binary. [By default](https://github.com/Kron4ek/Conty/blob/master/.github/workflows/conty.yml#L5), it will also generate a new Conty binary every Friday (you can use a [cron time expression](https://crontab.cronhub.io/) to change the schedule).

<details><summary>Illustration</summary><p>

![image](https://github.com/bayazidbh/Conty/assets/26621899/c80d08b7-5c4d-41b1-8eab-90178eed7b96)

![image](https://github.com/bayazidbh/Conty/assets/26621899/5cdd837a-d3cd-4c11-ad6b-bb6480ae8183)

![image](https://github.com/bayazidbh/Conty/assets/26621899/c065f6c2-f75a-4cf2-9c3d-cf151112ca50)

![image](https://github.com/bayazidbh/Conty/assets/26621899/6a18f7db-e6f2-44e3-9acf-1aee9af855a6)

</p></details>

## Useful Tips

### Sandbox

Conty uses bubblewrap and thus supports filesystem sandboxing, X11 isolation is also supported (via Xephyr). By default
sandbox is disabled and almost all directories and files on your system are available (visible and accessible) for the container.

Here are the environment variables that you can use to control the sandbox:
* **SANDBOX** - enables the sandbox feature itself. Isolates all user files and directories, creates a fake temporary home directory (in RAM), which is destroyed after closing the container.
* **SANDBOX_LEVEL** - controls the strictness of the sandbox. There are 3 available levels, the default is 1. Level 1 isolates all user files; Level 2 isolates all user files, disables dbus and hides all running processes; Level 3 does the same as the level 2, but additionally disables network access and isolates X11 server with Xephyr.
* **DISABLE_NET** - completely disables internet access.
* **HOME_DIR** - sets a custom home directory. If you set this, HOME inside the container will still appear as /home/username, but actually a custom directory will be used for it.

And launch arguments:
* `--bind SRC DEST` - binds (mounts) a file or directory to a destination, so it becomes visible inside the container. SRC is what you want to mount, DEST is where you want it to be mounted. This argument can be specified multiple times to mount multiple files/dirs.
* `--ro-bind SRC DEST` - same as above but mounts files/dirs as read-only.

Other bubblewrap arguments are supported too, read the bubblewrap help or manual for more information.

Note that when **SANDBOX** is enabled, none of user files are accessible or visible, for any application that you run in this mode your home directory will be seen as completely empty. If you want to allow access to some files or directories, use the aforementioned `--bind` or `--ro-bind` arguments.

Also note that `--bind`, `--ro-bind`, **HOME_DIR** and **DISABLE_NET** can be used even if **SANDBOX** is disabled.

For even more security you can run Conty under a separate user account. An example of how to run applications under a separate user can be seen, for instance, [here](https://wiki.archlinux.org/title/wine#Running_Wine_under_a_separate_user_account).

<details><summary>Example</summary><p>
Example 1

```
$ SANDBOX=1 ./conty.sh firefox
```

Example 2
```
$ export SANDBOX=1
$ export SANDBOX_LEVEL=2
$ ./conty.sh --bind ~/.steam ~/.steam --bind ~/.local/share/Steam ~/.local/share/Steam steam
```

Example 3:
```
$ mkdir "/home/username/custom_home_dir"
$ export DISABLE_NET=1
$ export SANDBOX=1
$ export HOME_DIR="/home/username/custom_home_dir"
$ ./conty.sh lutris
```

</p></details>

These options (and any Conty-related arguments and variables exported in `env` at the time) will be exported by `conty.sh -d` into part of all exported apps .desktop files in `$XDG_DATA_HOME/applications/Conty`. If you want multiple options, you can export it once with a specific config, rename the `Conty` folder, and then export a different set of .desktop files.

If you just want a sandboxing functionality but don't need a container with a full-size Linux distro inside (which is what Conty mainly is), i recommend to take a look directly at these projects: [bubblewrap](https://github.com/containers/bubblewrap) and [firejail](https://github.com/netblue30/firejail). Sandboxing is a good additional feature of Conty, but is not its main purpose.

### About Wine

Conty releases from the releases page include `Wine-Proton`, and if you build your own Conty you will get `Wine-Staging` by default (but you can change that).

As for prefix management, it's the same as with any other Wine build, the container does not affect it. The default prefix is `~/.wine`, but you can specify a custom prefix path with the `WINEPREFIX` environment variable.

`DXVK` and `vkd3d-proton` are not installed by default (unless they are already in your prefix), but can be easily installed, for example, via `winetricks` if you need them:

```
$ ./conty.sh winetricks dxvk vkd3d
```

As already mentioned in the [Usage](#usage) section, Windows applications can be launched like this:

```
$ ./conty.sh wine someapplication.exe
```

If you have new enough Linux kernel (5.16 or newer), it's a good idea to enable `FSYNC` to improve Wine performance:

```
$ WINEFSYNC=1 ./conty.sh wine someapplication.exe
```

## Known issues

* Some Windows applications running under Wine complain about lack of free disk space. This is because under Conty root partition is seen as full and read-only, so some applications think that there is no free space, even though you might have plenty of space in your HOME. The solution is simple, just run `winecfg`,  move to "Drives" tab and add your `/home` as an additional drive (for example, `D:`), and then install applications to that drive. More info [here](https://github.com/Kron4ek/Conty/issues/67#issuecomment-1460257910).
* AppImages do not work under Conty. This is because bubblewrap, which is used in Conty, does not allow SUID bit (for security reasons), which is needed to mount AppImages. The solution is to extract an AppImage application before running it with Conty. Some AppImages support `--appimage-extract-and-run` argument, which you can also use.
* Application may show errors (warnings) about locale, like "Unsupported locale setting" or "Locale not supported by C library". This happens because Conty has a limited set of generated locales inside it, and if your host system uses locale that is not available in Conty, applications may show such warnings. This is usually not a critical problem, most applications will continue to work without issues despite showing the errors. But if you want, you can [create](https://github.com/Kron4ek/Conty#how-to-create-your-own-conty-executables) a Conty executable and include any locales you need.
* Conty may have problems interfacing with custom url protocols (such as `steam://` and `sgdb://`), apps that uses Native Host Messengers (such as browser extensions for Plasma Host Integration / KDE Connect, KeePassXC, and download managers), and login token exchange (such as trying to log-in a natively-installed GitHub Desktop app with a browser inside Conty) if there is packages that handle such protocols installed (for example, `plasma-browser-integration` for KDE Plasma extension inside browser).
* Steam can't make screenshots when running directly under gamescope. The solution is to first run gamescope separately and then attach Steam client to it, like this:
    ```
    termA $ ./conty.sh gamescope -w 1920 -h 1080
    termB $ DISPLAY=:1 ./conty.sh steam
    ```
    `DISPLAY=:1` can have another number - get it from the `gamescope` output:

    > wlserver: [xwayland/server.c:108] Starting Xwayland on :1

    Solution from https://www.reddit.com/r/linux_gaming/comments/1ds1ei3/steam_input_not_working_under_gamescope/lb10mmf/

* The game is not starting or starting only when you disable your additional displays (for example Armies of Exigo): use Gamescope - see previous point.

## Main used projects

* [bubblewrap](https://github.com/containers/bubblewrap)
* [squashfuse](https://github.com/vasi/squashfuse)
* [dwarfs](https://github.com/mhx/dwarfs)
* [unionfs-fuse](https://github.com/rpodgorny/unionfs-fuse)
* [zstd](https://github.com/facebook/zstd)
* [busybox](https://busybox.net/)
* [bash](https://www.gnu.org/software/bash/)
* [archlinux](https://archlinux.org/)
* [chaotic-aur](https://aur.chaotic.cx/)
* [alhp](https://somegit.dev/ALHP/ALHP.GO)
