# Overview

Packer file to build specific versions of OPNsense:
- in `.qcow2` format
- with a pre-configured root API key
- with `vtnet0` bound to `WAN`
- with `ssh` enabled


## About

This repository provides automated build definitions for creating reproducible OPNsense virtual machine images.

The primary purpose is to provide ready-to-use OPNsense images for development and acceptance testing of [`opnsense-go`](https://github.com/browningluke/opnsense-go) and [`terraform-provider-opnsense`](https://github.com/browningluke/terraform-provider-opnsense).

The generated images are configured for automated API-based testing and can be used with QEMU/KVM. They provide a consistent OPNsense environment for testing provider resources and API integrations without requiring a manually configured OPNsense installation.

The image build is based on the official OPNsense installation media and verifies the downloaded media using the published OPNsense checksums and cryptographic signatures before the image is created.


## Local Image Build

The generated OPNsense image is primarily intended for development and acceptance testing of projects such as [`opnsense-go`](https://github.com/browningluke/opnsense-go) and [`terraform-provider-opnsense`](https://github.com/browningluke/terraform-provider-opnsense).

A local Linux host with QEMU/KVM is recommended. Hardware virtualization is important because the OPNsense installation runs as a complete virtual machine during the Packer build. Without KVM, QEMU falls back to software emulation and the installation can take a significant amount of time.

### Requirements

Install the following tools:

* QEMU
* `qemu-img`
* Packer
* `curl`
* `bzip2`
* OpenSSL
* standard POSIX shell utilities

Verify that KVM is available:

```bash
test -e /dev/kvm && echo "KVM available" || echo "KVM unavailable"
```

A working `/dev/kvm` device is strongly recommended.

Packer's QEMU builder automatically uses KVM when it is available and falls back to software emulation otherwise.

### Build the image

Set the OPNsense mirror and version:

```bash
export PKR_VAR_MIRROR="https://mirror.init7.net/opnsense"
export PKR_VAR_VERSION="26.7"
```

Download and verify the OPNsense installer:

```bash
./get-iso.sh
```

The download process verifies both:

1. the official OPNsense SHA256 checksum of the compressed installer
2. the detached OPNsense OpenSSL signature of the uncompressed ISO

The signing key is stored in the repository under:

```text
keys/OPNsense-26.7.pub
```

Initialize and validate Packer:

```bash
packer init .
packer validate .
```

Build the image:

```bash
PACKER_LOG=1 packer build -e VERSION="26.7" -e ISO_CHECKSUM="<SHA1_CHECKSUM_FROM_DOWNLOAD_PROCESS>"  .
```

The resulting image is:

```text
output/opnsense-26.7.qcow2
```

The generated API credentials are written to:

```text
apikey.txt
```

### Using the image for development

The resulting QCOW2 image can be used as a reproducible OPNsense test instance for API development and acceptance testing.

For example, the same image can be used as the OPNsense backend while developing:

* `opnsense-go`
* `terraform-provider-opnsense`

This provides a known OPNsense version and avoids depending on a manually configured firewall instance.

```bash
qemu-system-x86_64 -m 4096 -smp 2 -hda ./opnsense.qcow2 \
    -accel kvm \
    -netdev user,id=user.0,hostfwd=tcp::8022-:22,hostfwd=tcp::8443-:443 \
    -device virtio-net,netdev=user.0 \
    -chardev socket,path=/tmp/qemu-isa-serial.sock,server=on,wait=off,id=qga0 \
    -device isa-serial,chardev=qga0 \
    -device virtio-serial \
    -chardev socket,path=/tmp/qemu-virtconsole.sock,server=on,wait=off,id=qvt0 \
    -device virtconsole,chardev=qvt0 \
    -chardev socket,path=/tmp/qemu-virtserialport.sock,server=on,wait=off,id=qvsp0 \
    -device virtserialport,chardev=qvsp0,name=org.qemu.guest_agent.0 
```

You can access the shell via `ssh -p 8022 root@127.0.0.1` using the credentials `root:opnsense`.

The web interface is accessible at `https://localhost:8443` using the same credentials.

The credentials for the Web API are stored in `apikey.txt`.

### GitHub Actions

A GitHub Actions workflow is included under:

```text
.github/workflows/build.yml
```

The workflow documents the complete automated build process and can be used as a reference for future CI infrastructure.

The workflow is currently not intended to be used as the normal image build mechanism. The OPNsense installation requires QEMU virtualization, and software-emulated QEMU execution on standard runners results in impractically long build times.

If the upstream project obtains access to suitable GitHub-hosted Linux runners with hardware virtualization, the workflow can be re-enabled and adapted accordingly.

### Security

The generated image is intended for development and acceptance testing only.

The image contains a test-oriented root/API configuration and must not be deployed directly into a production environment.

## License

Distributed under the BSD 2-Clause "Simplified" License. See `LICENSE.txt` for more information.

## Acknowledgements

This project is based on the work of [commure/opnsense-images](https://github.com/commure/opnsense-images), which itself is a modified version of the [openstack images repository](https://gitlab.com/open-images/opnsense). Much appreciation is given to both teams of these repos.
