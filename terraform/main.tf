module "api" {
  source = "./apis"
}

module "api" {
  source     = "./resources"
  depends_on = [module.api]
}
