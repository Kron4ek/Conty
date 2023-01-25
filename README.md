## Conty

This is an easy to use compressed unprivileged Linux container packed into a single executable that works on most Linux distros. It's designed to be as simple and user-friendly as possible. You can use it to run any applications, including games (Vulkan and OpenGL).

In its default configuration it includes, among others, these apps: `Wine-GE, Steam, Lutris, PlayOnLinux, GameHub, Minigalaxy, Legendary, Bottles, MultiMC, MangoHud, Gamescope, RetroArch, PPSSPP, PCSX2, OBS Studio, OpenJDK, Firefox`. If these applications are not enough, you can install additional applications or run external binaries from, for example, your home directory.

Besides, Conty supports true filesystem and X11 sandboxing, so you can even use it to isolate applications.

## Features

* A single executable - download (or create) and run, nothing else is required. And it's portable, you can put it anywhere (even on a usb stick).
* Works on most Linux distros, even very old ones and even without glibc (such as Alpine or Void with musl).
* Root rights are **not required**.
* Compressed (with squashfs or dwarfs), so it takes a lot less disk space than uncompressed containers and may provide faster filesystem access in some cases.
* Contains many libraries and packages so it can run almost everything. And you don't need to install anything on your main (host) system. **You can even run 32-bit applications on pure 64-bit systems**.
* Based on Arch Linux, contains latest software (including latest videodrivers).
* Almost completely seamless experience. All applications that you run with Conty read and store their configs in your HOME directory as if you weren't using the container at all.
* No performance overhead. Since it's just a container, there is virtually no performance overhead, thus all applications will run at full speed. Regarding memory usage, Conty uses a bit more memory due to compression and because applications from the container can't share libraries with your system apps.
* Supports Xorg, Wayland and XWayland.
* Supports filesystem and X11 sandboxing (thanks to bubblewrap and xephyr).

## Requirements

The only requirements are **bash**, **fuse2** (or **fuse3**), **tar**, **gzip** and **coreutils**. And your /tmp directory
should allow files execution (which it does by default on most distros).

Your Linux kernel must be at least version 4.4 and should support unprivileged user namespaces. On some
Linux distros this feature is disabled by default and can be enabled with sysfs:

```
# sysctl kernel.unprivileged_userns_clone=1
```

Even if unprivileged user namespaces are not supported by your kernel, you can still use Conty if you have bubblewrap with the SUID bit installed on your system, in this case just tell Conty to use system-wide utils instead of the builtin ones.

```
$ export USE_SYS_UTILS=1
$ ./conty.sh command command_arguments
```

## Usage

Either download a ready-to-use release from the [**releases**](https://github.com/Kron4ek/Conty/releases) page or create your
own (the instructions are below). Make it executable before run.

```
$ chmod +x conty.sh
$ ./conty.sh command command_arguments
```

Conty contains Steam, Lutris, PlayOnLinux, Bottles, Wine-GE and many more.

```
$ ./conty.sh steam
$ ./conty.sh lutris
$ ./conty.sh playonlinux4
$ ./conty.sh bottles
$ ./conty.sh wine someapplication.exe
```

It has a builtin file manager (pcmanfm):

```
$ ./conty.sh pcmanfm
```

To check if hardware acceleration (OpenGL and Vulkan) works, you can use these tools:

```
$ ./conty.sh glxinfo -B
$ ./conty.sh glxgears
$ ./conty.sh vulkaninfo
$ ./conty.sh vkcube
```

You can even use Conty for compilation:

```
$ ./conty.sh gcc src.c
$ ./conty.sh git clone https://something.git
$ cd something && ./conty.sh ./configure
$ ./conty.sh make
```

There are many more integrated programs. You can list all of them with:

```
$ ./conty.sh ls /usr/bin
```

It is also possible to run binaries from your storage. For example, if you want to run an application that resides on your HOME, run something like:

```
$ ./conty.sh /home/username/SomeApplication/binaryfile
```

There are some other features, see the internal help for more information.

```
$ ./conty.sh --help
```

## About Wine

Conty releases from the releases page include `Wine-GE`, and if you build your own Conty you will get `Wine-Staging` by default (but you can change that).

As for prefix management, it's the same as with any other Wine build, the container does not affect it. The default prefix is `~/.wine`, but you can specify a custom prefix path with the `WINEPREFIX` environment variable.

`DXVK` and `vkd3d-proton` are not installed by default (unless they are already in your prefix), but can be easily installed, for example, via `winetricks` if you need them:

```
$ ./conty.sh winetricks dxvk vkd3d
```

As already mentioned in the [Usage](https://github.com/Kron4ek/Conty#usage) section, Windows applications can be launched like this:

```
$ ./conty.sh wine someapplication.exe
```

If you have new enough Linux kernel (5.16 or newer), it's a good idea to enable `FSYNC` to improve Wine performance:

```
$ WINEFSYNC=1 ./conty.sh wine someapplication.exe
```

## Sandbox

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

Example:
```
$ export SANDBOX=1
$ export SANDBOX_LEVEL=2
$ ./conty.sh --bind ~/.steam ~/.steam --bind ~/.local/share/Steam ~/.local/share/Steam steam
```
Another example:
```
$ mkdir "/home/username/custom_home_dir"
$ export DISABLE_NET=1
$ export SANDBOX=1
$ export HOME_DIR="/home/username/custom_home_dir"
$ ./conty.sh lutris
```

If you just want a sandboxing functionality but don't need a container with a full-size Linux distro inside (which is what Conty mainly is), i recommend to take a look directly at these projects: [bubblewrap](https://github.com/containers/bubblewrap) and [firejail](https://github.com/netblue30/firejail). Sandboxing is a good additional feature of Conty, but is not its main purpose.

## Known issues

Nvidia users with the proprietary driver will experience graphics acceleration problems (probably graphical applications won't work at all) if their Nvidia kernel module version mismatches the version of the Nvidia libraries inside Conty. This applies only to the proprietary driver, Nouveau should work fine without any additional actions (of course, if your GPU is supported by it).

For example, if the version of your Nvidia kernel module is 460.56 and the libraries inside the container are from 460.67 version, then graphics acceleration will not work.

There are two solutions to this problem:
* The first and probably the easiest solution is to install the same driver version as included inside Conty, which is usually the latest non-beta version. You can see the exact driver version in pkg_list.txt attached to each Conty release. Of course if your GPU is not supported by new drivers, this is not an option for you.
* The second solution is to (re)build Conty and include the same driver version as installed on your system. Read the "**How to create your own Conty executables**" section below, you will need to edit the **create-arch-bootstrap.sh** script or use the **enter-chroot.sh** script to include a different driver version. For instance, if you want to include legacy 470xx or 390xx drivers, edit the **create-arch-bootstrap.sh** script and replace `nvidia-utils` and `lib32-nvidia-utils` with `nvidia-470xx-utils` and `lib32-nvidia-470xx-utils` (replace 470xx with 390xx if you need 390xx drivers) in the `video_pkgs` variable, and then build Conty following the instructions.

## How to update

There are three main ways to update Conty and get the latest packages, use whichever works best for you.

* First of all, you can simply download latest release from the [releases page](https://github.com/Kron4ek/Conty/releases), i usually upload a new release about every three weeks.
* You can use the self-update feature (`./conty.sh -u`) integrated into Conty, it will update all integrated packages and will rebuild the squashfs/dwarfs image. Read the internal help for more information about it.
* You can manually create a Conty executable with latest packages inside, read the "**How to create your own Conty executables**" section below.

## How to create your own Conty executables

If you want to create an Arch-based container, use the **create-arch-bootstrap.sh** script, it will download latest Arch Linux bootstrap and will install latest packages into it. If you want to use any other distro, then you need to manually obtain it from somewhere. Root rights are required for this step, because chroot is used here.
```
# ./create-arch-bootstrap.sh
```
You can edit the script if you want to include different set of packages inside
the container.

When distro is obtained, you can use the **enter-chroot.sh** script to chroot
into the bootstrap and do some manual modifications (for instance, modify some
files, install/remove packages, etc.). This step is optional and you can
skip it if you don't need it.

After that use the **create-conty.sh** script to create a squashfs (or dwarfs) image and pack everything needed into a single executable.
```
$ ./create-conty.sh
```
By default it uses the lz4 algorithm for the squashfs compression, but you can edit it and choose zstd to get better compression ratio (keep in mind though that your squashfs-tools should support zstd for that to work).

Done!

For the sake of convenience, there are compiled binaries (**utils.tar.gz**) of bwrap, squashfuse and dwarfs and their dependencies uploaded in this repo, **create-conty.sh** uses them by default. However, you can easily compile your own binaries by using the **create-utils.sh**, it will compile bwrap, squashfuse and dwarfs and will create utils.tar.gz. If you are going to use your own utils.tar.gz, make sure to set the correct size for it in the **conty-start.sh**.

## Main used projects

* [bubblewrap](https://github.com/containers/bubblewrap)
* [squashfuse](https://github.com/vasi/squashfuse)
* [dwarfs](https://github.com/mhx/dwarfs)
* [archlinux](https://archlinux.org/)
* [chaotic-aur](https://aur.chaotic.cx/)
