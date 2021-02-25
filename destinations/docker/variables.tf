variable "mount_path" {
  type = string
  description = "Path on host to mount microbedb to share with jobs"
}

variable "key_path" {
  type = string
  default = ""
  description = "Path on host to microbedb CVMFS repository pub key"
}