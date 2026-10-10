# authentication.upgrade_to_identity_platform / import_existing の回帰テスト
# (mock provider のみ、認証不要)。
#   cd modules/firebase-project-platform
#   terraform init -backend=false && terraform test
#
# import_existing の import block 自体は root module (dispatch-firebase-platform
# Action のテンプレート) 側にあるため、ここでは module 側の validation のみ検証する。

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project_id = "test-project"
}

run "default_upgrades_to_identity_platform" {
  command = plan

  variables {
    authentication = true
  }

  assert {
    condition     = length(module.auth) == 1
    error_message = "既定 (upgrade_to_identity_platform 未指定) で Identity Platform config が作られていない"
  }
}

run "upgrade_false_skips_config_but_enables_api" {
  command = plan

  variables {
    authentication = {
      upgrade_to_identity_platform = false
    }
  }

  assert {
    condition     = length(module.auth) == 0
    error_message = "upgrade_to_identity_platform = false なのに Identity Platform config が作られている"
  }

  assert {
    condition     = contains(keys(google_project_service.this), "identitytoolkit.googleapis.com")
    error_message = "upgrade_to_identity_platform = false でも identitytoolkit API は有効化する"
  }

  assert {
    condition     = output.auth_config_name == null
    error_message = "config を作らないときは auth_config_name が null"
  }
}

# import block は module 内に無いので、import_existing = true 単体では module の
# plan は通常どおり (config を管理対象にする)。
run "import_existing_keeps_config_managed" {
  command = plan

  variables {
    authentication = {
      import_existing = true
    }
  }

  assert {
    condition     = length(module.auth) == 1
    error_message = "import_existing = true で config が管理対象から外れている"
  }
}

run "upgrade_false_with_import_rejected" {
  command = plan

  variables {
    authentication = {
      upgrade_to_identity_platform = false
      import_existing              = true
    }
  }

  expect_failures = [var.authentication]
}

run "upgrade_false_with_authorized_domains_rejected" {
  command = plan

  variables {
    authentication = {
      upgrade_to_identity_platform = false
      authorized_domains = {
        include_localhost = false
      }
    }
  }

  expect_failures = [var.authentication]
}

run "upgrade_false_with_blocking_functions_rejected" {
  command = plan

  variables {
    authentication = {
      upgrade_to_identity_platform = false
      blocking_functions = {
        before_create = "https://example.com/before-create"
      }
    }
  }

  expect_failures = [var.authentication]
}

run "non_bool_flag_rejected" {
  command = plan

  variables {
    authentication = {
      import_existing = "yes"
    }
  }

  expect_failures = [var.authentication]
}

# -- blocking_functions.managed_by (#153) ------------------------------------

run "blocking_functions_default_terraform_managed" {
  command = plan

  variables {
    authentication = {
      blocking_functions = {
        before_create = "https://example.com/before-create"
      }
    }
  }

  assert {
    condition     = length(module.auth) == 1 && length(module.auth_deploy_managed) == 0
    error_message = "既定 (managed_by 未指定) は terraform 管理の module.auth を使う"
  }
}

run "blocking_functions_deploy_managed" {
  command = plan

  variables {
    authentication = {
      blocking_functions = {
        managed_by = "deploy"
      }
    }
  }

  assert {
    condition     = length(module.auth) == 0 && length(module.auth_deploy_managed) == 1
    error_message = "managed_by = deploy は module.auth_deploy_managed を使う"
  }
}

run "blocking_functions_deploy_with_uri_rejected" {
  command = plan

  variables {
    authentication = {
      blocking_functions = {
        managed_by     = "deploy"
        before_sign_in = "https://example.com/before-sign-in"
      }
    }
  }

  expect_failures = [var.authentication]
}

run "blocking_functions_unknown_mode_rejected" {
  command = plan

  variables {
    authentication = {
      blocking_functions = {
        managed_by = "console"
      }
    }
  }

  expect_failures = [var.authentication]
}

run "blocking_functions_deploy_with_upgrade_false_rejected" {
  command = plan

  variables {
    authentication = {
      upgrade_to_identity_platform = false
      blocking_functions = {
        managed_by = "deploy"
      }
    }
  }

  expect_failures = [var.authentication]
}

# YAML で値を空にした (null) 場合は既定値として扱う
run "blocking_functions_null_mode_is_terraform" {
  command = plan

  variables {
    authentication = {
      blocking_functions = {
        managed_by = null
      }
    }
  }

  assert {
    condition     = length(module.auth) == 1 && length(module.auth_deploy_managed) == 0
    error_message = "managed_by = null は terraform 管理として扱う"
  }
}

run "blocking_functions_deploy_with_null_uri_allowed" {
  command = plan

  variables {
    authentication = {
      blocking_functions = {
        managed_by    = "deploy"
        before_create = null
      }
    }
  }

  assert {
    condition     = length(module.auth_deploy_managed) == 1
    error_message = "deploy 管理で URI が null なら許可する"
  }
}

run "blocking_functions_non_string_mode_rejected" {
  command = plan

  variables {
    authentication = {
      blocking_functions = {
        managed_by = ["deploy"]
      }
    }
  }

  expect_failures = [var.authentication]
}
