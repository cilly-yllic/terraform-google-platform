# iam_bindings (任意の member への project-level の付与) の回帰テスト (mock provider のみ、認証不要)。
#   cd modules/firebase-project-platform
#   terraform init -backend=false && terraform test

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project_id = "test-project"
}

# 未指定なら何も作らない (既存の構成に差分を出さない)
run "omitted_creates_nothing" {
  command = plan

  assert {
    condition     = length(google_project_iam_member.binding) == 0
    error_message = "iam_bindings 未指定なのに付与が作られている"
  }
}

run "grants_each_member_with_name_and_label_key" {
  command = apply

  variables {
    iam_bindings = [
      {
        name = "ci-project-viewer"
        role = "roles/browser"
        members = {
          github = "principalSet://iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/example-pool/attribute.repository/your-org/example-service"
          ops    = "group:ops@example.com"
        }
      },
      {
        name = "external-sa"
        role = "projects/test-project/roles/exampleReader"
        members = {
          reader = "serviceAccount:reader@other-project.iam.gserviceaccount.com"
          person = "principal://iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/example-pool/subject/example-subject"
        }
        condition = {
          title      = "expires"
          expression = "request.time < timestamp(\"2030-01-01T00:00:00Z\")"
        }
      },
    ]
  }

  assert {
    condition = toset(keys(google_project_iam_member.binding)) == toset([
      "ci-project-viewer|github",
      "ci-project-viewer|ops",
      "external-sa|reader",
      "external-sa|person",
    ])
    error_message = "resource のキーが \"<name>|<label>\" になっていない"
  }

  assert {
    condition = (
      google_project_iam_member.binding["ci-project-viewer|github"].role == "roles/browser" &&
      startswith(google_project_iam_member.binding["ci-project-viewer|github"].member, "principalSet://") &&
      google_project_iam_member.binding["ci-project-viewer|github"].project == "test-project"
    )
    error_message = "principalSet の付与の role / member / project が違う"
  }

  assert {
    condition     = length(google_project_iam_member.binding["ci-project-viewer|ops"].condition) == 0
    error_message = "condition を書いていない付与に condition が付いている"
  }

  assert {
    condition = (
      google_project_iam_member.binding["external-sa|reader"].condition[0].title == "expires" &&
      google_project_iam_member.binding["external-sa|person"].role == "projects/test-project/roles/exampleReader"
    )
    error_message = "condition / custom role が付与に反映されていない"
  }

  assert {
    condition     = output.iam_binding_members["external-sa|reader"].member == "serviceAccount:reader@other-project.iam.gserviceaccount.com"
    error_message = "output iam_binding_members に付与が出ていない"
  }
}

run "unsupported_member_prefix_is_rejected" {
  command = plan

  variables {
    iam_bindings = [
      { name = "bad", role = "roles/viewer", members = { all = "allUsers" } },
    ]
  }

  expect_failures = [var.iam_bindings]
}

run "duplicate_name_is_rejected" {
  command = plan

  variables {
    iam_bindings = [
      { name = "dup", role = "roles/viewer", members = { a = "user:a@example.com" } },
      { name = "dup", role = "roles/browser", members = { b = "user:b@example.com" } },
    ]
  }

  expect_failures = [var.iam_bindings]
}

run "label_with_separator_is_rejected" {
  command = plan

  variables {
    iam_bindings = [
      { name = "x", role = "roles/viewer", members = { "a|b" = "user:a@example.com" } },
    ]
  }

  expect_failures = [var.iam_bindings]
}

run "invalid_role_is_rejected" {
  command = plan

  variables {
    iam_bindings = [
      { name = "x", role = "viewer", members = { a = "user:a@example.com" } },
    ]
  }

  expect_failures = [var.iam_bindings]
}

run "empty_members_is_rejected" {
  command = plan

  variables {
    iam_bindings = [
      { name = "x", role = "roles/viewer", members = {} },
    ]
  }

  expect_failures = [var.iam_bindings]
}

run "same_role_and_member_twice_is_rejected" {
  command = plan

  variables {
    iam_bindings = [
      { name = "a", role = "roles/viewer", members = { x = "user:a@example.com" } },
      { name = "b", role = "roles/viewer", members = { y = "user:a@example.com" } },
    ]
  }

  expect_failures = [var.iam_bindings]
}

# メール形式の member は大文字・小文字を区別せずに重なりを見る (provider が小文字に正規化する)
run "same_member_with_different_case_is_rejected" {
  command = plan

  variables {
    iam_bindings = [
      { name = "a", role = "roles/browser", members = { x = "user:Alice@example.com" } },
      { name = "b", role = "roles/browser", members = { y = "user:alice@example.com" } },
    ]
  }

  expect_failures = [var.iam_bindings]
}

# principal:// / principalSet:// は大文字・小文字を区別するので、別の member として通す
run "principal_set_is_case_sensitive" {
  command = plan

  variables {
    iam_bindings = [
      { name = "a", role = "roles/browser", members = { x = "principalSet://iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/example-pool/attribute.repository/your-org/Example" } },
      { name = "b", role = "roles/browser", members = { y = "principalSet://iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/example-pool/attribute.repository/your-org/example" } },
    ]
  }

  assert {
    condition     = length(google_project_iam_member.binding) == 2
    error_message = "大文字・小文字だけが違う principalSet が別の付与にならない"
  }
}

# condition が違えば別の付与 (provider も condition を含めて識別する)
run "same_member_with_different_conditions_is_allowed" {
  command = plan

  variables {
    iam_bindings = [
      { name = "plain", role = "roles/browser", members = { x = "user:a@example.com" } },
      {
        name      = "timed"
        role      = "roles/browser"
        members   = { x = "user:a@example.com" }
        condition = { title = "until-2030", expression = "request.time < timestamp(\"2030-01-01T00:00:00Z\")" }
      },
    ]
  }

  assert {
    condition     = length(google_project_iam_member.binding) == 2
    error_message = "condition が違う同じ role・member が別の付与にならない"
  }
}

run "condition_on_basic_role_is_rejected" {
  command = plan

  variables {
    iam_bindings = [
      {
        name      = "x"
        role      = "roles/viewer"
        members   = { a = "user:a@example.com" }
        condition = { title = "t", expression = "true" }
      },
    ]
  }

  expect_failures = [var.iam_bindings]
}

# 同じモジュールの users の付与と、条件なしで同じ role・member (大文字・小文字違い) は plan で止める
run "overlap_with_users_is_rejected" {
  command = plan

  variables {
    users = [{ email = "Lead@example.com", role = "editor" }]
    iam_bindings = [
      { name = "x", role = "roles/editor", members = { a = "user:lead@example.com" } },
    ]
  }

  expect_failures = [google_project_iam_member.binding]
}

run "overlap_with_ci_sa_is_rejected" {
  command = plan

  variables {
    ci_service_account = true
    iam_bindings = [
      { name = "x", role = "roles/runtimeconfig.admin", members = { a = "serviceAccount:ci-deploy@test-project.iam.gserviceaccount.com" } },
    ]
  }

  expect_failures = [google_project_iam_member.binding]
}

run "overlap_with_service_accounts_is_rejected" {
  command = plan

  variables {
    service_accounts = [{ account_id = "app-runtime", type = "runtime", roles = ["roles/datastore.user"] }]
    iam_bindings = [
      { name = "x", role = "roles/datastore.user", members = { a = "serviceAccount:app-runtime@test-project.iam.gserviceaccount.com" } },
    ]
  }

  expect_failures = [google_project_iam_member.binding]
}

# 条件付きなら、モジュールのほかの付与と同じ role・member でも別の binding なので通す
# (deploy = true の user に付く roles/cloudfunctions.admin と本当に重なる組み合わせ)
run "conditional_overlap_with_users_is_allowed" {
  command = plan

  variables {
    users = [{ email = "Lead@example.com", role = "viewer", deploy = true }]
    iam_bindings = [
      {
        name      = "x"
        role      = "roles/cloudfunctions.admin"
        members   = { a = "user:lead@example.com" }
        condition = { title = "t", expression = "true" }
      },
    ]
  }

  assert {
    condition     = length(google_project_iam_member.binding) == 1
    error_message = "条件付きの付与が、同じ role・member の users の付与と重なるとして断られている"
  }
}

# 条件なしなら同じ組み合わせは断る (上の run と対)
run "unconditional_overlap_with_users_deploy_is_rejected" {
  command = plan

  variables {
    users = [{ email = "Lead@example.com", role = "viewer", deploy = true }]
    iam_bindings = [
      { name = "x", role = "roles/cloudfunctions.admin", members = { a = "user:lead@example.com" } },
    ]
  }

  expect_failures = [google_project_iam_member.binding]
}

# 初回作成: project の API が作成予定なので google_project data の読み込みが apply に遅れ、
# project number が plan で unknown になる (mock でも unknown)。それでも入力だけで分かる users との
# 重なりは plan で止まる。
# 注: terraform test の expect_failures は、条件が unknown で plan 時に評価されなかった check も
# 失敗扱いにせず pass させる。この run だけでは「plan で止まる」ことまでは保証しないので、
# expect_failures を外した plan がエラーになることも合わせて確かめている (変更時は手で確かめる)。
run "overlap_with_users_is_rejected_while_project_number_is_unknown" {
  command = plan

  variables {
    cloud_functions    = true
    default_compute_sa = { roles = ["roles/secretmanager.secretAccessor"] }
    users              = [{ email = "lead@example.com", role = "editor" }]
    iam_bindings = [
      { name = "x", role = "roles/editor", members = { a = "user:lead@example.com" } },
    ]
  }

  expect_failures = [google_project_iam_member.binding]
}

# project number が要る付与 (既定 compute SA) との重なりは、number が決まっていれば plan で止まる
run "overlap_with_default_compute_sa_is_rejected" {
  command = plan

  override_data {
    target = data.google_project.this
    values = {
      number = "123456789012"
    }
  }

  variables {
    default_compute_sa = { roles = ["roles/secretmanager.secretAccessor"] }
    iam_bindings = [
      { name = "x", role = "roles/secretmanager.secretAccessor", members = { a = "serviceAccount:123456789012-compute@developer.gserviceaccount.com" } },
    ]
  }

  expect_failures = [google_project_iam_member.binding]
}
