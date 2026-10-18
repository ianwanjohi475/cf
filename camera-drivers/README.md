Ready-made live-camera drivers for WSL kernels, one folder per `uname -r`.

`phone.sh start` loads the folder matching your kernel automatically. If your
kernel isn't here, `./setup-camera.sh` builds the same files on your PC.

Built from Microsoft's WSL2-Linux-Kernel source at the matching
`linux-msft-wsl-<version>` tag with its `config-wsl`, plus
[v4l2loopback](https://github.com/umlaeute/v4l2loopback) (GPL-2.0).
