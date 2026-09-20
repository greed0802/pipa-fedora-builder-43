# Building images

You need Docker, roughly 20 GiB free disk, and (on x86_64) working binfmt for
aarch64. A mid-range laptop takes about 20 minutes.

### Clone this repo

```bash
git clone https://github.com/rr1111/pipa-fedora-builder-43
cd pipa-fedora-builder-43
```

### One-shot build

```bash
./scripts/build-image.sh plasma
```

Flavors: `tty`, `gnome`, `plasma` (default), `plasma-mobile`, `custom`.
Images land in `images/` as a directory plus a zip (`boot.img` + `root.img`).

### Manual docker commands

```bash
docker build -t pipa-fedora-builder .
docker run --privileged --rm \
  -v "$(pwd)"/images:/build/images \
  -v /dev:/dev \
  pipa-fedora-builder <desktop-arg>
```

`--privileged` and `/dev` are required for loop devices. Drop `--rm` if you
want to keep the container. An invalid or missing flavor defaults to `plasma`.

On non-aarch64 hosts install `qemu-user-static` (the Dockerfile already does
this inside the build container).

### Building custom images

- Add packages in `mkosi.profiles/custom.conf`
- Or use a group like `@cosmic-desktop-environment`
- Pass `custom` as the desktop argument
- If packages enable their own services, the image should boot to a GUI

### After the build

- Singleboot: `./scripts/flash.sh singleboot --boot images/.../boot.img --root images/.../root.img`
- Dualboot: [DUALBOOT.md](./DUALBOOT.md) then `./scripts/flash.sh dualboot ...`

[Installation guide](./INSTALL.md)
