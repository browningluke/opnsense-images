packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1"
    }
  }
}

source "qemu" "opnsense" {
  boot_wait = "3s"
  boot_steps = [
    ["1", "Boot in multi user mod"],
    ["<wait10m>", "Waiting 10min for guest to start"],
    ["root<enter><wait1s>opnsense<enter><wait3s>", "Login into the firewall"],
    ["1<enter><wait2s>", "Start manual interface assignment"],
    ["N<enter><wait2s>", "Do not configure LAGGs now"],
    ["N<enter><wait2s>", "Do not configure VLANs now"],
    ["vtnet0<enter><wait2s>", "Configure WAN interface"],
    ["<enter><wait2s>", "Skip LAN interface configuration"],
    ["<enter><wait2s>", "Skip Optional interface 1 configuration"],
    ["y<enter><wait2s>", "I want to proceed"],
    ["<wait2m>", "Wait for OPNSense to reload"],
    ["<wait2s>8<enter><wait2s>", "Enter in shell"],
    [
      "curl -o /conf/config.xml http://{{ .HTTPIP }}:{{ .HTTPPort }}/config.xml<enter><wait3s>",
      "Download config.xml"
    ],
    ["opnsense-installer<enter><wait2s>", "Run OPNsense Installer"],
    ["<enter><wait2s>", "Use default keymap"],
    ["<down><enter><wait2s><enter><wait3s>", "Use UFS"],
    ["<enter><wait2s><left><enter><wait20m>", "Select the disk and install OPNsense"],
    ["opnsense<enter><wait1s>opnsense<enter><wait3s>", "Reset the opnsense password"],
    ["<down><enter><wait2s><enter><wait5m>", "Exit installer and wait 5min for guest to start"],
    ["root<enter>opnsense<enter><wait5s>", "Login into the firewall"],
    ["8<enter><wait2s>pkg install -y os-qemu-guest-agent<enter><wait15s>sysrc qemu_guest_agent_enable='YES'<enter><wait1s>", "Install and enable Qemu Guest package"],
    ["pfctl -d<enter><wait2s>", "Disabling firewall"],
  ]
  shutdown_command = "shutdown -p now<enter>"

  disk_size        = "8192M"
  disk_compression = true
  cpus             = 4
  memory           = 4096 # OPNSense require 2G of RAM to install
  http_directory   = "http"
  net_device       = "virtio-net"

  iso_checksum = "${var.ISO_CHECKSUM}"
  iso_urls = [
    "./iso/OPNsense-${var.VERSION}-dvd-amd64.iso",
  ]
  output_directory = "output"
  format           = "qcow2"

  ssh_timeout  = "2m"
  ssh_port     = 22
  ssh_username = "root"
  ssh_password = "opnsense"

  # Setting headless to false open the libvirt gui to actually see
  # the installer is doing
  headless = true

  qemuargs = [
    ["-chardev", "socket,path=${var.SOCKET_DIR}/qemu-isa-serial.sock,server=on,wait=off,id=qga0"],
    ["-device", "isa-serial,chardev=qga0"],
    ["-device", "virtio-serial"],
    ["-chardev", "socket,path=${var.SOCKET_DIR}/qemu-virtconsole.sock,server=on,wait=off,id=qvt0"],
    ["-device", "virtconsole,chardev=qvt0"],
    ["-chardev", "socket,path=${var.SOCKET_DIR}/qemu-virtserialport.sock,server=on,wait=off,id=qvsp0"],
    ["-device", "virtserialport,chardev=qvsp0,name=org.qemu.guest_agent.0"]
  ]

  # You may use this for debug purpose
  # vnc_bind_address = "0.0.0.0"
  # vnc_port_min = 5901
  # vnc_port_max = 5901

  vm_name = "opnsense-${var.VERSION}.qcow2"
}


build {
  sources = ["source.qemu.opnsense"]

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; /bin/sh -c '{{ .Vars }} {{ .Path }} -u root create 2>&1 | tee /tmp/apikey.txt'" # "chmod +x {{ .Path }}; /bin/sh -c '{{ .Vars }} {{ .Path }}'"
    scripts = [
      "scripts/opn-apikey"
    ]
  }

  # Pull the log file back to the host
  provisioner "file" {
    direction = "download"
    source      = "/tmp/apikey.txt"
    destination = "apikey.txt"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; /bin/sh -c '{{ .Vars }} {{ .Path }}'" # "chmod +x {{ .Path }}; /bin/sh -c '{{ .Vars }} {{ .Path }}'"
    scripts = [
      "scripts/post-install.sh"
    ]
  }
}

variable "VERSION" {
  type    = string
  default = "25.7"
  validation {
    condition = can(regex("^\\d{2}\\.\\d$", var.VERSION))
    error_message = "The version should be XX.X. Ex: 25.7."
  }
}

variable "ISO_CHECKSUM" {
  type    = string
  default = "sha1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  validation {
    condition = can(regex("^\\w+:\\w+", var.ISO_CHECKSUM))
    error_message = "The ISO checksum should be <type>:<value>. Ex: sha1:2722ee32814ee722bb565ac0dd83d9ebc1b31ed9."
  }
}

variable "SOCKET_DIR" {
  type    = string
  default = "/tmp" 
}
