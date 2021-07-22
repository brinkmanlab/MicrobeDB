data "http" "servers" {
  url = "http://stratum-0.brinkmanlab.ca/cvmfs/info/v1/meta.json"

  request_headers = {
    Accept = "application/json"
  }
}

module "cvmfs" {
  source = "github.com/brinkmanlab/cloud_recipes.git//util/k8s/cvmfs"
  cvmfs_keys = {
    "microbedb.brinkmanlab.ca" = file(var.key_path == "" ? "${abspath(path.module)}/../../microbedb.brinkmanlab.ca.pub" : var.key_path)
  }
  cvmfs_repo_tags = var.tag == null ? null : {
    "microbedb.brinkmanlab.ca" = var.tag
  }
  servers = jsondecode(data.http.servers.body)["recommended-stratum1s"]
}