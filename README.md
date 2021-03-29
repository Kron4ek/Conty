## Conty

This is an easy to use non-root container compressed into squashfs and packed 
into a single executable that runs (or at least should run) on most Linux distros.

You can use it to run any applications, including games (Vulkan and OpenGL).

Besides, due to bubblewrap, Conty also supports true filesystem sandboxing, so you can even use it to sandbox
your applications.

In other words, it's a portable Arch Linux distro packed into a single executable that can be used to run any applications. Conty combines benefits of
flatpak and AppImage.

It uses two technologies:
* SuqashFS (using [squashfuse](https://github.com/vasi/squashfuse))
* Linux namespaces (using [bubblewrap](https://github.com/containers/bubblewrap))

## Benefits

* Single executable - download (or create) and run, nothing else it required.
* Root rights are **not required**.
* Compressed into squashfs, so it takes much less disk space than
unpacked containers.
* Contains many libraries and packages so it can run almost everything. And you don't
need to install anything on your main (host) system. **You can even run 32-bit applications
on pure 64-bit systems**.
* Based on Arch Linux, so it contains latest software, including latest
videodrivers.
* Almost completely seamless experience. All applcations that you run
with Conty store their configs in your HOME directory as if you wouldn't
use container at all.
* Supports filesystem sandboxing.

## Requirements

The only requirements are **bash**, **fuse2**, **tar** and **coreutils**. And your /tmp directory
should allow binaries execution (which it does by default on most distros).

Also, your Linux kernel must support unprivileged user namespaces. On some 
Linux distros this feature is disabled by default and can be enabled with sysfs:

```
sysctl kernel.unprivileged_userns_clone=1
```
or
```
echo 1 > /proc/sys/kernel/unprivileged_userns_clone
```

## Usage

Either download ready-to-use executable from the [**releases**](https://github.com/Kron4ek/Conty/releases) page or create your
own (the instructions are below). Make it executable before run.

```
chmod +x conty.sh
./conty.sh command command_arguments
```

For example, if you want to run an application from your HOME or from somewhere on your storage run something like:

```
./conty.sh /full/path/to/a/binary
```

Conty also contains Steam, Lutris, Wine-Staging and many more.

```
./conty.sh steam
./conty.sh lutris
./conty.sh wine app.exe
```

It has a builtin file manager (pcmanfm):

```
./conty.sh pcmanfm
```

Want to check if graphics acceleration works? Run glxinfo, glxgears, vulkaninfo and vkcube:

```
./conty.sh glxinfo | grep direct
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
it's disabled and all directories on your system are available for the container. 

You can enable sandboxing with the **SANDBOX** environment variable. You can allow 
access to directories and/or files you want with the **BIND** variable. And it's 
also possible to disable network with the **DISABLE_NET**. And you can set custom HOME directory
with the **HOME_DIR** variable. For instance:

```
export DISABLE_NET=1
export SANDBOX=1
export BIND="/home/username/.steam /home/username/.local/share/Steam"
./conty.sh steam
```
Or
```
export DISABLE_NET=1
export SANDBOX=1
export HOME_DIR="/home/username/custom_home_dir"
./conty.sh steam
```

## Known issues

Nvidia users will experience problems if their Nvidia kernel module version mismatches the version of the Nvidia libraries inside Conty. 

For example, if the version of your Nvidia kernel module is 460.56 and the libraries inside the container are from 460.67 version, then graphics acceleration will not work. 

I will try to find a solution for this problem.

## How to create your own Conty executables

If you want to create Arch-based container, then use the **create-arch-bootstrap.sh** script. Root rights
are required for this step, because chrooting is used here.

```
./create-arch-bootstrap.sh
```

You can edit the script if you want to include different set of packages inside
the container.

If you want to use some other distro, then you need to manually obtain it from somewhere.

For the sake of convenience, there are compiled binaries of bwrap and squashfuse and their dependencies (utils.tar) uploaded in this repo, you can use them or you can use your own binaries. Use the **create-utils.sh** script to easily compile your own bwrap and squashfuse. Just make sure to set the correct size of the **utils.tar** in the **squashfs-start.sh**.

```
./create-utils.sh
```

When distro bootsrap and utils.tar are obtained, use the **create-conty.sh** script to pack
everything into a single executable.

```
./create-conty.sh
```

Done!
