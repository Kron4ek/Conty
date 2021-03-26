## Conty

This is an easy to use non-root container compressed into squashfs and packed 
into a single executable that runs (or at least should run) on most Linux distros.

You can use it to run any applications, including games (Vulkan and OpenGL).

Besides, due to bubblewrap, Conty also supports true filesystem sandboxing, so you can even use it to sandbox
your applications.

In other words, it's a portable Arch Linux distro packed into a single executable that can be used to run any applications. Conty combines benefits of
flatpak and AppImage.

It uses two technologies:
* SuqashFS (using squashfuse)
* Linux namespaces (using bubblewrap)

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

The only requirements are **bash**, **fuse2** and **tar**. And your /tmp directory
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

For example, if you want to run an application from your HOME directory run:

```
./conty.sh /home/username/App/application_binary
```

Conty also contains Steam, Lutris, Wine-Staging and much more.

```
./conty.sh steam
./conty.sh lutris
./conty.sh wine app.exe
```

Want to check if graphics acceleration works? Run glxinfo and glxgears:

```
./conty.sh glxinfo | grep direct
./conty.sh glxgears
```

List all built-in binaries with:

```
./conty.sh ls /usr/bin
```

## Sandbox

Conty uses bubblewrap and thus supports filesystem sandboxing. By default
it's disabled and all directories on your system are available for the container. 

You can enable sandboxing with the **SANDBOX** environment variable. You can allow 
access to directories you want with the **WHITELIST_DIRS** variable. And it's 
also possible to disable network with the **DISABLE_NET**. For example:

```
export DISABLE_NET=1
export SANDBOX=1
export WHITELIST_DIRS="/home/username/.cache /opt /home/username/Downloads"
./conty.sh command
```

## How to create your own Conty executables

If you want to create Arch-based container then use the **create-arch-bootstrap.sh** script. Root rights
are required for this step, because chrooting is used here.

```
./create-arch-bootstrap.sh
```

You can edit the script, if you want to include different set of packages inside
the container.

If you want to use some other distro then you need to manually obtain it from somewhere.

When distro bootsrap is obtained, use the **create-conty.sh** script to pack
everything into a single executable.

```
./create-conty.sh
```

Done!
