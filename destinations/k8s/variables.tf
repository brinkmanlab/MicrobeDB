variable "key_path" {
  type = string
  default = ""
  description = "Path on host to microbedb CVMFS repository pub key"
}

variable "tag" {
  type = string
  default = null
  description = "CVMFS commit tag to mount"
}