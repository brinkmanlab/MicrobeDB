output "storageclasses" {
  value       = module.cvmfs.storageclasses
  description = "Map of kubernetes_storage_class instances, keyed on repo name"
}