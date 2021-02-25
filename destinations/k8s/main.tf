module "cvmfs" {
  source = "github.com/brinkmanlab/cloud_recipes.git//util/k8s/cvmfs"
  cvmfs_keys = {
    "microbedb.brinkmanlab.ca" = file(var.key_path == "" ? "${abspath(path.module)}/../../microbedb.brinkmanlab.ca.pub" : var.key_path)
  }
  servers = ["http://stratum-1.sfu.brinkmanlab.ca/cvmfs/@fqrn@", "http://stratum-1.cedar.brinkmanlab.ca/cvmfs/@fqrn@"]
}