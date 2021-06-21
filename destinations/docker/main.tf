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
  upload {
    file = "/etc/cvmfs/default.d/19-brinkman.conf"
    content = <<EOF
CVMFS_SERVER_URL="http://stratum-1.sfu.brinkmanlab.ca/cvmfs/@fqrn@;http://stratum-1.cedar.brinkmanlab.ca/cvmfs/@fqrn@"
CVMFS_REPOSITORIES=microbedb.brinkmanlab.ca
CVMFS_HTTP_PROXY='DIRECT'
CVMFS_QUOTA_LIMIT='4000'
EOF
  }
  mounts {
    type = "bind"
    target = "/etc/cvmfs/keys/microbedb.brinkmanlab.ca.pub"
    source = var.key_path == "" ? "${abspath(path.module)}/../../microbedb.brinkmanlab.ca.pub" : var.key_path
    read_only = true
  }
}