# NoPhish
 
Another phishing toolkit which provides an docker and noVNC based infrastructure. The whole setup is based on the initial article of [mrd0x](https://mrd0x.com/bypass-2fa-using-novnc/) and [fhlipzero](https://fhlipzero.io/blogs/6_noVNC/noVNC.html).

A detailed description of the setup can be found here - [Another phishing tool](https://powerseb.github.io/posts/Another-phishing-tool/)

## Installation

Install the required python modules:

```console
pip install lz4
```

Install the setup (which will create the required docker images):

```console
setup.sh install
```

## Execution

The setup offers the following parameters:

```console
Usage: ./setup.sh -u No. Users -d Domain -t Target
         -u Number of users - please note for every user a container is spawned so don't go crazy
         -d Domain which is used for phishing
         -t Target website which should be displayed for the user
         -e Export format
         -s true / false if ssl is required - if ssl is set crt and key file are needed
         -c Full path to the crt file of the ssl certificate
         -k Full path to the key file of the ssl certificate
         -a Adjust default user agent string
```

A basic run looks like the following:

```console
./setup.sh -u 4 -t https://accounts.google.com -d hello.local 
```

## CleanUp

During a run the script can be terminated with `ctrl` + `c` - all running docker container will then be deleted. To fully remove the setup run `setup.sh cleanup`.
