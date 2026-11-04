# monitoring (通知先・log-based metric・alert policy) の配線と入力の検査 (mock provider のみ、認証不要)。
# resource の中身は modules/monitoring/tests で確かめる。
#   cd modules/firebase-project-platform
#   terraform init -backend=false && terraform test

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project_id = "test-project"
}

# 未指定なら何も作らず、API も足さない (既存の構成に差分を出さない)
run "omitted_creates_nothing" {
  command = plan

  assert {
    condition     = length(module.monitoring) == 0
    error_message = "monitoring 未指定なのに module.monitoring が呼ばれている"
  }

  assert {
    condition     = !contains(output.enabled_apis, "monitoring.googleapis.com") && !contains(output.enabled_apis, "logging.googleapis.com")
    error_message = "monitoring 未指定なのに monitoring / logging API が有効化される"
  }

  assert {
    condition     = length(data.google_project.this) == 0
    error_message = "monitoring 未指定なのに data.google_project が読まれる"
  }
}

run "creates_channels_metrics_and_policies" {
  command = apply

  variables {
    monitoring = {
      notification_channels = {
        ops    = { type = "email", labels = { email_address = "ops@example.com" } }
        alerts = { type = "pubsub", display_name = "Alerts topic", labels = { topic = "alerts" } }
      }
      log_metrics = {
        app-error-events = {
          filter           = "severity>=ERROR"
          label_extractors = { code = "EXTRACT(jsonPayload.code)" }
        }
      }
      alert_policies = {
        app-errors = {
          display_name = "App errors"
          channels     = ["ops", "alerts"]
          conditions = [{
            display_name = "error events > 0"
            threshold = {
              filter             = "metric.type=\"logging.googleapis.com/user/app-error-events\""
              comparison         = "COMPARISON_GT"
              threshold_value    = 0
              duration           = "0s"
              alignment_period   = "300s"
              per_series_aligner = "ALIGN_SUM"
            }
          }]
        }
      }
    }
  }

  assert {
    condition     = length(module.monitoring) == 1
    error_message = "monitoring を宣言したのに module.monitoring が呼ばれていない"
  }

  assert {
    condition = alltrue([
      for api in ["monitoring.googleapis.com", "logging.googleapis.com", "pubsub.googleapis.com"] : contains(output.enabled_apis, api)
    ])
    error_message = "monitoring / logging / (pubsub の通知先がある) pubsub API が有効化されていない"
  }

  assert {
    condition     = length(data.google_project.this) == 1
    error_message = "pubsub の通知先があるのに project number を読んでいない"
  }

  assert {
    condition     = toset(keys(output.monitoring_notification_channel_ids)) == toset(["ops", "alerts"])
    error_message = "output monitoring_notification_channel_ids のキーが channel の名前になっていない"
  }

  assert {
    condition     = keys(output.monitoring_alert_policy_names) == ["app-errors"]
    error_message = "output monitoring_alert_policy_names に policy が出ていない"
  }

  assert {
    condition     = output.monitoring_log_metric_types["app-error-events"] == "logging.googleapis.com/user/app-error-events"
    error_message = "output monitoring_log_metric_types が metric type になっていない"
  }
}

# email の通知先だけなら project number も Pub/Sub API も要らない
run "email_only_does_not_need_project_number" {
  command = plan

  variables {
    monitoring = {
      notification_channels = {
        ops = { type = "email", labels = { email_address = "ops@example.com" } }
      }
    }
  }

  assert {
    condition     = length(data.google_project.this) == 0 && !contains(output.enabled_apis, "pubsub.googleapis.com")
    error_message = "email の通知先だけなのに project number / Pub/Sub API を使っている"
  }
}

run "unknown_channel_type_is_rejected" {
  command = plan

  variables {
    monitoring = {
      notification_channels = {
        hook = { type = "webhook_tokenauth", labels = { url = "https://example.com/hook" } }
      }
    }
  }

  expect_failures = [var.monitoring]
}

run "email_channel_without_address_is_rejected" {
  command = plan

  variables {
    monitoring = {
      notification_channels = {
        ops = { type = "email", labels = { topic = "alerts" } }
      }
    }
  }

  expect_failures = [var.monitoring]
}

run "unknown_policy_channel_is_rejected" {
  command = plan

  variables {
    monitoring = {
      notification_channels = {
        ops = { type = "email", labels = { email_address = "ops@example.com" } }
      }
      alert_policies = {
        p = {
          display_name = "p"
          channels     = ["missing"]
          conditions = [{
            display_name = "c"
            log_match    = { filter = "severity>=ERROR" }
          }]
        }
      }
    }
  }

  expect_failures = [var.monitoring]
}

run "condition_with_two_kinds_is_rejected" {
  command = plan

  variables {
    monitoring = {
      alert_policies = {
        p = {
          display_name = "p"
          channels     = []
          conditions = [{
            display_name = "c"
            log_match    = { filter = "severity>=ERROR" }
            absent       = { filter = "metric.type=\"logging.googleapis.com/user/app-error-events\"", duration = "600s" }
          }]
        }
      }
    }
  }

  expect_failures = [var.monitoring]
}

run "condition_without_kind_is_rejected" {
  command = plan

  variables {
    monitoring = {
      alert_policies = {
        p = {
          display_name = "p"
          channels     = []
          conditions   = [{ display_name = "c" }]
        }
      }
    }
  }

  expect_failures = [var.monitoring]
}

run "log_match_with_other_conditions_is_rejected" {
  command = plan

  variables {
    monitoring = {
      alert_policies = {
        p = {
          display_name = "p"
          channels     = []
          conditions = [
            { display_name = "log", log_match = { filter = "severity>=ERROR" } },
            { display_name = "absent", absent = { filter = "metric.type=\"logging.googleapis.com/user/app-error-events\"", duration = "600s" } },
          ]
        }
      }
    }
  }

  expect_failures = [var.monitoring]
}

run "rate_limit_on_metric_policy_is_rejected" {
  command = plan

  variables {
    monitoring = {
      alert_policies = {
        p = {
          display_name            = "p"
          channels                = []
          notification_rate_limit = "300s"
          conditions = [{
            display_name = "absent"
            absent       = { filter = "metric.type=\"logging.googleapis.com/user/app-error-events\"", duration = "600s" }
          }]
        }
      }
    }
  }

  expect_failures = [var.monitoring]
}

run "invalid_severity_and_duration_are_rejected" {
  command = plan

  variables {
    monitoring = {
      alert_policies = {
        p = {
          display_name = "p"
          channels     = []
          severity     = "INFO"
          conditions = [{
            display_name = "absent"
            absent       = { filter = "metric.type=\"logging.googleapis.com/user/app-error-events\"", duration = "10m" }
          }]
        }
      }
    }
  }

  expect_failures = [var.monitoring]
}

run "label_description_without_extractor_is_rejected" {
  command = plan

  variables {
    monitoring = {
      log_metrics = {
        app-error-events = {
          filter = "severity>=ERROR"
          labels = { code = "error code" }
        }
      }
    }
  }

  expect_failures = [var.monitoring]
}

run "unsupported_comparison_is_rejected" {
  command = plan

  variables {
    monitoring = {
      alert_policies = {
        p = {
          display_name = "p"
          channels     = []
          conditions = [{
            display_name = "c"
            threshold = {
              filter          = "metric.type=\"logging.googleapis.com/user/app-error-events\""
              comparison      = "COMPARISON_GE"
              threshold_value = 0
              duration        = "0s"
            }
          }]
        }
      }
    }
  }

  expect_failures = [var.monitoring]
}

run "threshold_duration_not_multiple_of_60s_is_rejected" {
  command = plan

  variables {
    monitoring = {
      alert_policies = {
        p = {
          display_name = "p"
          channels     = []
          conditions = [{
            display_name = "c"
            threshold = {
              filter          = "metric.type=\"logging.googleapis.com/user/app-error-events\""
              comparison      = "COMPARISON_GT"
              threshold_value = 0
              duration        = "90s"
            }
          }]
        }
      }
    }
  }

  expect_failures = [var.monitoring]
}

run "absent_duration_below_120s_is_rejected" {
  command = plan

  variables {
    monitoring = {
      alert_policies = {
        p = {
          display_name = "p"
          channels     = []
          conditions = [{
            display_name = "c"
            absent       = { filter = "metric.type=\"logging.googleapis.com/user/app-error-events\"", duration = "60s" }
          }]
        }
      }
    }
  }

  expect_failures = [var.monitoring]
}

run "alignment_period_below_60s_is_rejected" {
  command = plan

  variables {
    monitoring = {
      alert_policies = {
        p = {
          display_name = "p"
          channels     = []
          conditions = [{
            display_name = "c"
            absent = {
              filter             = "metric.type=\"logging.googleapis.com/user/app-error-events\""
              duration           = "600s"
              alignment_period   = "30s"
              per_series_aligner = "ALIGN_SUM"
            }
          }]
        }
      }
    }
  }

  expect_failures = [var.monitoring]
}

run "aligner_without_alignment_period_is_rejected" {
  command = plan

  variables {
    monitoring = {
      alert_policies = {
        p = {
          display_name = "p"
          channels     = []
          conditions = [{
            display_name = "c"
            threshold = {
              filter             = "metric.type=\"logging.googleapis.com/user/app-error-events\""
              comparison         = "COMPARISON_GT"
              threshold_value    = 0
              duration           = "0s"
              per_series_aligner = "ALIGN_SUM"
            }
          }]
        }
      }
    }
  }

  expect_failures = [var.monitoring]
}

run "reducer_without_aligner_is_rejected" {
  command = plan

  variables {
    monitoring = {
      alert_policies = {
        p = {
          display_name = "p"
          channels     = []
          conditions = [{
            display_name = "c"
            threshold = {
              filter               = "metric.type=\"logging.googleapis.com/user/app-error-events\""
              comparison           = "COMPARISON_GT"
              threshold_value      = 0
              duration             = "0s"
              alignment_period     = "300s"
              cross_series_reducer = "REDUCE_SUM"
            }
          }]
        }
      }
    }
  }

  expect_failures = [var.monitoring]
}

run "group_by_without_reducer_is_rejected" {
  command = plan

  variables {
    monitoring = {
      alert_policies = {
        p = {
          display_name = "p"
          channels     = []
          conditions = [{
            display_name = "c"
            absent = {
              filter             = "metric.type=\"logging.googleapis.com/user/app-error-events\""
              duration           = "600s"
              alignment_period   = "300s"
              per_series_aligner = "ALIGN_SUM"
              group_by_fields    = ["resource.label.service_name"]
            }
          }]
        }
      }
    }
  }

  expect_failures = [var.monitoring]
}

# Logging の metric 名の規則 ("/" は階層の区切り。先頭には置けない)
run "log_metric_name_with_hierarchy_is_accepted" {
  command = plan

  variables {
    monitoring = {
      log_metrics = {
        "app/error-events" = { filter = "severity>=ERROR" }
      }
    }
  }

  assert {
    condition     = length(module.monitoring) == 1
    error_message = "\"/\" を含む metric 名が通らない"
  }
}

run "log_metric_name_with_leading_slash_is_rejected" {
  command = plan

  variables {
    monitoring = {
      log_metrics = {
        "/app-error-events" = { filter = "severity>=ERROR" }
      }
    }
  }

  expect_failures = [var.monitoring]
}

# alignment_period の上限は 90000 秒 (25 時間)
run "alignment_period_at_upper_bound_is_accepted" {
  command = plan

  variables {
    monitoring = {
      alert_policies = {
        p = {
          display_name = "p"
          channels     = []
          conditions = [{
            display_name = "c"
            threshold = {
              filter             = "metric.type=\"logging.googleapis.com/user/app-error-events\""
              comparison         = "COMPARISON_GT"
              threshold_value    = 0
              duration           = "0s"
              alignment_period   = "90000s"
              per_series_aligner = "ALIGN_SUM"
            }
          }]
        }
      }
    }
  }

  assert {
    condition     = length(module.monitoring) == 1
    error_message = "alignment_period = 90000s が通らない"
  }
}

run "alignment_period_above_upper_bound_is_rejected" {
  command = plan

  variables {
    monitoring = {
      alert_policies = {
        p = {
          display_name = "p"
          channels     = []
          conditions = [{
            display_name = "c"
            absent = {
              filter             = "metric.type=\"logging.googleapis.com/user/app-error-events\""
              duration           = "600s"
              alignment_period   = "90001s"
              per_series_aligner = "ALIGN_SUM"
            }
          }]
        }
      }
    }
  }

  expect_failures = [var.monitoring]
}
