## Conty

This is an easy to use unprivileged Linux container compressed into squashfs and packed 
into a single executable that works on most Linux distros. It's designed to be as simple and user-friendly as possible.

You can use it to run any applications, including games (Vulkan and OpenGL).

Besides, due to bubblewrap, Conty also supports true filesystem sandboxing, so you can even use it to isolate applications.

It uses two technologies:
* SquashFS (using [squashfuse](https://github.com/vasi/squashfuse))
* Linux namespaces (using [bubblewrap](https://github.com/containers/bubblewrap))

## Features

* Single executable - download (or create) and run, nothing else is required.
* Root rights are **not required**.
* Compressed into squashfs, so it takes much less disk space than
uncompressed containers.
* Contains many libraries and packages so it can run almost everything. And you don't
need to install anything on your main (host) system. **You can even run 32-bit applications
on pure 64-bit systems**.
* Based on Arch Linux, so it contains latest software, including latest
videodrivers.
* Almost completely seamless experience. All applications that you run
with Conty read and store their configs in your HOME directory as if you weren't
using the container at all.
* No performance overhead. Since it's just a container, there is almost no overhead, thus all applications will run at full speed.
* Supports filesystem sandboxing (thanks to bubblewrap).

## Requirements

The only requirements are **bash**, **fuse2** (or **fuse3**), **tar** and **coreutils**. And your /tmp directory
should allow files execution (which it does by default on most distros).

Besides, your Linux kernel should be at least version 4.4 and should support unprivileged user namespaces. On some 
Linux distros this feature is disabled by default and can be enabled with sysfs:

```
sysctl kernel.unprivileged_userns_clone=1
```
or
```
echo 1 > /proc/sys/kernel/unprivileged_userns_clone
```

Even if unprivileged user namespaces are not supported in your kernel, you can still use Conty if you have bwrap with SUID bit in your system, in this case just tell Conty to use system-wide bwrap and squashfuse instead of the builtin ones.

```
export USE_SYS_UTILS=1
./conty.sh command command_arguments
```

## Usage

Either download ready-to-use executable from the [**releases**](https://github.com/Kron4ek/Conty/releases) page or create your
own (the instructions are below). Make it executable before run.

```
chmod +x conty.sh
./conty.sh command command_arguments
```

For example, if you want to run an application from somewhere on your storage run something like:

```
./conty.sh /path/to/a/binary
```

Conty also contains Steam, Lutris, PlayOnLinux, Wine-Staging-TkG and many more.

```
./conty.sh steam
./conty.sh lutris
./conty.sh playonlinux
./conty.sh wine app.exe
```

It has a builtin file manager (pcmanfm):

```
./conty.sh pcmanfm
```

Want to check if graphics acceleration works (OpenGL and Vulkan)? Run glxinfo, glxgears, vulkaninfo and vkcube:

```
./conty.sh glxinfo -B
./conty.sh glxgears
./conty.sh vulkaninfo
./conty.sh vkcube
```

You can even use Conty for compilation:

```
./conty.sh gcc src.c
./conty.sh git clone https://something.git
cd something && ./conty.sh ./configure
./conty.sh make
```

There are many more integrated programs. You can list all of them with:

```
./conty.sh ls /usr/bin
```

Let me know if you want something else to be included in the container.

There are some other features, see the internal help for more information.

```
./conty.sh --help
```

## Sandbox


Conty uses bubblewrap and thus supports filesystem sandboxing. By default
it's disabled and almost all directories on your system are available for the container. 

Here are the environment variables that you can use to control the sandbox:
* **SANDBOX** - enables the sandboxing feature itself. Isolates all directories, creates a fake temporary home directory (in RAM), which is destroyed after closing the container.
* **DISABLE_NET** - completely disables internet access.
* **HOME_DIR** - sets a custom home directory. If you set this, HOME inside the container will still appear as /home/username, but actually a custom directory will be used for it.
* **BIND** - list of files/directories (separated by space) to bind to the container. You can use this variable to allow access to any files or directories.

Example:

```
export SANDBOX=1
export BIND="/home/username/.steam /home/username/.local/share/Steam"
./conty.sh steam
```
Another example:
```
mkdir "/home/username/custom_home_dir"
export DISABLE_NET=1
export SANDBOX=1
export HOME_DIR="/home/username/custom_home_dir"
./conty.sh lutris
```

If you just want a sandboxing functionality but don't need a container with a full-size Linux distro inside (which is what Conty mainly is), i recommend to take a look directly at these projects: [bubblewrap](https://github.com/containers/bubblewrap) and [firejail](https://github.com/netblue30/firejail). Sandboxing is a good additional feature of Conty, but is not its main purpose.

## Known issues

Nvidia users will experience graphics acceleration problems if their Nvidia kernel module version mismatches the version of the Nvidia libraries inside Conty. 

For example, if the version of your Nvidia kernel module is 460.56 and the libraries inside the container are from 460.67 version, then graphics acceleration will not work.

There is an experimental solution for this problem that can be enabled with the **NVIDIA_FIX** variable. If you encounter this problem, please let me know if this feature does or doesn't fix it for you.

```
export NVIDIA_FIX=1
./conty.sh glxgears
```

## How to update

There are three ways to update Conty and get the latest packages, use whichever is more convenient for you.

* First of all, you can simply download latest release from the [releases page](https://github.com/Kron4ek/Conty/releases), i usually upload a new release every week or every two weeks.
* You can use the self-update feature (`./conty.sh -u`) integrated into Conty, it will update all integrated packages and will rebuild the squashfs image. Read the internal help for more information about it.
* You can manually create a Conty executable with latest packages inside, read the "**How to create your own Conty executables**" section below.

## How to create your own Conty executables

If you want to create Arch-based container, use the **create-arch-bootstrap.sh** script, it will download latest Arch Linux bootstrap and will install latest packages into it. If you want to use any other distro, then you need to manually obtain it from somewhere. Root rights are required for this step, because chroot is used here.
```
./create-arch-bootstrap.sh
```
You can edit the script if you want to include different set of packages inside
the container.

When distro is obtained, use the **create-conty.sh** script to create a squashfs image and pack everything needed into a single executable.
```
./create-conty.sh
```
By default it uses the lz4 algorithm for squashfs compression, but you can edit it and set zstd algo to get better compression ratio (keep in mind though that your squashfs-tools should support zstd for that to work).

Done!

For the sake of convenience, there are compiled binaries (**utils.tar**) of bwrap and squashfuse and their dependencies uploaded in this repo, **create-conty.sh** uses them by default. However, you can easily compile your own binaries by using the **create-utils.sh**, it will compile bwrap and squashfuse and will create utils.tar. If you are going to use your own utils.tar, make sure to set the correct size for it in the **conty-start.sh**.
