# Build Scripts

## Dependencies

On Ubuntu :

```sh
sudo apt-get install wget tar make git patch xz-utils gcc bc xxd build-essential bison flex python3 python3-distutils python kmod u-boot-tools
```

## Usage

In the selected folder drop l4t-linux-build.sh and run it.
If needed run `chmod 0755 l4t-linux-build.sh`
```sh
./l4t-linux-build.sh
```

The build files will be stored in the `kernel` directory.
Here's the files you should get after a successfull build:
```txt
uImage
nx-plat.dtimg
modules.tar.gz
```

The rest of the files and directory are kept for later builds.
