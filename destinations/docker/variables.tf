variable "mount_path" {
  type = string
  description = "Path on host to mount microbedb"
}

variable "key_path" {
  type = string
  default = ""
  description = "Path on host to microbedb CVMFS repository pub key"
}