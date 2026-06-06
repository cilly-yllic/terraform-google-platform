module "firebase_platform" {
  source = "../../../modules/firebase-project-platform"

  project_id = "my-minimal-project"
  region     = "asia-northeast1"

  firebase  = true
  firestore = true
}
