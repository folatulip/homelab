# tflint config, used by CI (tflint --recursive from terraform/).
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
