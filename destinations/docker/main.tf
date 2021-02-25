resource "docker_image" "microbedb" {
  name = "cvmfs/service"
}

resource "docker_container" "microbedb" {
  image = docker_image.microbedb.latest
  name = "microbedb"
  restart = "unless-stopped"

  entrypoint = ["cvmfs2", "-d", "-f",  "-o", "allow_other", "-o", "config=/etc/cvmfs/default.d/19-brinkman.conf", "microbedb.brinkmanlab.ca", "/cvmfs/microbedb.brinkmanlab.ca"]

  #security_opts = ["apparmor=unconfined"]
  capabilities {
    add = ["SYS_ADMIN"]
  }
  devices {
    container_path = "/dev/fuse"
    host_path = "/dev/fuse"
    permissions    = "rwm"
  }
  mounts {
    type = "bind"
    target = "/cvmfs/microbedb.brinkmanlab.ca"
    source = var.mount_path
    bind_options {
      propagation = "shared"
    }
    read_only = true
  }
  mounts {
    type = "bind"
    target = "/etc/cvmfs/default.d/19-brinkman.conf"
    source = "${abspath(path.module)}/cvmfs.config"
    read_only = true
  }
  mounts {
    type = "bind"
    target = "/etc/cvmfs/keys/microbedb.brinkmanlab.ca.pub"
    source = var.key_path == "" ? "${abspath(path.module)}/../../microbedb.brinkmanlab.ca.pub" : var.key_path
    read_only = true
  }
}