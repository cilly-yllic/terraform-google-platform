variable "project_id" {
  description = "compute host のプロジェクト ID（project-bootstrap で作ったもの）"
  type        = string
}

variable "region" {
  description = "サブネット・Cloud NAT の既定のリージョン"
  type        = string
  default     = "asia-northeast1"
}

variable "apis" {
  description = <<-EOT
    追加で有効にする API。compute / iam / iamcredentials / logging / monitoring は常に有効にする。
  EOT
  type        = list(string)
  default     = []
}

variable "api_propagation_wait" {
  description = "API を有効にした後、ほかの資源を作る前に待つ時間（API の伝播待ち）"
  type        = string
  default     = "60s"
}

variable "network" {
  description = <<-EOT
    カスタムモードの VPC と、そのサブネット。null なら作らない（既定のネットワークは作らない前提）。
      name    = VPC の名前
      subnets = [{
        name                     = サブネットの名前
        cidr                     = 例 "10.10.0.0/20"
        region                   = 省略時は var.region
        private_google_access    = Google の API に外部 IP 無しで届くか（既定 true）
        flow_logs                = VPC フローログ（既定 false）
      }]
  EOT
  type = object({
    name = string
    subnets = list(object({
      name                  = string
      cidr                  = string
      region                = optional(string)
      private_google_access = optional(bool, true)
      flow_logs             = optional(bool, false)
    }))
  })
  default = null

  validation {
    # Terraform 1.10 系は || を短絡評価しないので、null の属性を読まないよう条件式で分ける
    condition     = var.network == null ? true : length(var.network.subnets) > 0
    error_message = "network.subnets を 1 つ以上指定してください。"
  }
}

variable "firewall_rules" {
  description = <<-EOT
    VPC のファイアウォールのルール（network が必要）。GCP の暗黙のルール（受信は拒否・送信は許可）の上に足す。
      name                    = ルールの名前
      direction               = "INGRESS" / "EGRESS"
      action                  = "allow" / "deny"
      priority                = 0〜65535（小さいほど先。既定 1000）
      ranges                  = INGRESS なら送信元、EGRESS なら宛先の CIDR（1 つ以上。すべてなら "0.0.0.0/0" を明示する）
      protocols               = [{ protocol = "tcp" / "udp" / "icmp" / "all", ports = ["22", "443"] }]（既定は all）
      target_tags             = 対象の VM のネットワークタグ（target_service_accounts と同時には使えない）
      target_service_accounts = 対象の VM の SA のメール。account_id だけを書くと、このモジュールの SA のメールにする
      description             = 説明
      log                     = ファイアウォールのログ（既定 false）
  EOT
  type = list(object({
    name      = string
    direction = string
    action    = string
    priority  = optional(number, 1000)
    ranges    = list(string)
    protocols = optional(list(object({
      protocol = string
      ports    = optional(list(string), [])
    })), [{ protocol = "all", ports = [] }])
    target_tags             = optional(list(string), [])
    target_service_accounts = optional(list(string), [])
    description             = optional(string, "")
    log                     = optional(bool, false)
  }))
  default = []

  validation {
    condition = alltrue([
      for rule in var.firewall_rules :
      contains(["INGRESS", "EGRESS"], rule.direction) && contains(["allow", "deny"], rule.action)
    ])
    error_message = "firewall_rules の direction は INGRESS / EGRESS、action は allow / deny にしてください。"
  }

  validation {
    condition = alltrue([
      for rule in var.firewall_rules : !(length(rule.target_tags) > 0 && length(rule.target_service_accounts) > 0)
    ])
    error_message = "firewall_rules の target_tags と target_service_accounts は同時に指定できません。"
  }

  validation {
    condition     = alltrue([for rule in var.firewall_rules : rule.priority >= 0 && rule.priority <= 65535])
    error_message = "firewall_rules の priority は 0〜65535 にしてください。"
  }

  validation {
    condition     = alltrue([for rule in var.firewall_rules : length(rule.ranges) > 0])
    error_message = "firewall_rules の ranges を 1 つ以上指定してください（空のまま渡すと、すべての送信元・宛先が対象になる）。"
  }

  validation {
    condition     = length(distinct([for rule in var.firewall_rules : rule.name])) == length(var.firewall_rules)
    error_message = "firewall_rules の name が重なっています。"
  }

  validation {
    condition     = length(var.firewall_rules) == 0 || var.network != null
    error_message = "firewall_rules を使うには network を指定してください。"
  }

  validation {
    condition = alltrue(flatten([
      for rule in var.firewall_rules : [
        for value in rule.target_service_accounts :
        strcontains(value, "@") || contains([for sa in var.service_accounts : sa.account_id], value)
      ]
    ]))
    error_message = "firewall_rules の target_service_accounts の account_id が service_accounts にありません（メールなら @ を含めてください）。"
  }
}

variable "cloud_nat" {
  description = <<-EOT
    Cloud Router と Cloud NAT（network が必要）。VM に外部 IP を持たせずに外へ出るために使う。
      Cloud NAT が効くのは同じリージョンのサブネットだけ。network.subnets はすべて NAT と同じリージョンにする
      （違うリージョンのサブネットがあれば断る）。
      router_name      = Cloud Router の名前
      nat_name         = Cloud NAT の名前
      region           = 省略時は var.region
      min_ports_per_vm = VM ごとの最小ポート数（既定 64）
      log_filter       = "ERRORS_ONLY" / "TRANSLATIONS_ONLY" / "ALL" / "NONE"（ログを出さない）。既定 "ERRORS_ONLY"
  EOT
  type = object({
    router_name      = string
    nat_name         = string
    region           = optional(string)
    min_ports_per_vm = optional(number, 64)
    log_filter       = optional(string, "ERRORS_ONLY")
  })
  default = null

  validation {
    condition     = var.cloud_nat == null ? true : contains(["ERRORS_ONLY", "TRANSLATIONS_ONLY", "ALL", "NONE"], var.cloud_nat.log_filter)
    error_message = "cloud_nat.log_filter は ERRORS_ONLY / TRANSLATIONS_ONLY / ALL / NONE にしてください。"
  }

  validation {
    condition = var.cloud_nat == null || var.network == null ? true : alltrue([
      for subnet in var.network.subnets :
      coalesce(subnet.region, var.region) == coalesce(var.cloud_nat.region, var.region)
    ])
    error_message = "cloud_nat と違うリージョンのサブネットがあります（Cloud NAT は同じリージョンのサブネットにだけ効く）。"
  }

  validation {
    condition     = var.cloud_nat == null || var.network != null
    error_message = "cloud_nat を使うには network を指定してください。"
  }
}

variable "service_accounts" {
  description = <<-EOT
    このプロジェクトに作る SA。
      account_id   = SA ID（6〜30 文字）
      display_name = 表示名
      roles        = プロジェクト単位の role（"custom:<role_id>" で custom_roles のロールを指す）
  EOT
  type = list(object({
    account_id   = string
    display_name = optional(string, "")
    roles        = optional(list(string), [])
  }))
  default = []

  validation {
    condition     = alltrue([for sa in var.service_accounts : can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", sa.account_id))])
    error_message = "service_accounts の account_id は小文字で始まる 6〜30 文字（小文字・数字・ハイフン）にしてください。"
  }

  validation {
    condition     = length(distinct([for sa in var.service_accounts : sa.account_id])) == length(var.service_accounts)
    error_message = "service_accounts の account_id が重なっています。"
  }

  validation {
    condition = alltrue(flatten([
      for sa in var.service_accounts : [
        for role in sa.roles :
        !startswith(role, "custom:") || contains([for custom in var.custom_roles : custom.role_id], trimprefix(role, "custom:"))
      ]
    ]))
    error_message = "service_accounts の roles の custom:<role_id> が custom_roles にありません。"
  }
}

variable "service_account_iam" {
  description = <<-EOT
    SA を対象にした IAM（例: 管理用の SA に、VM に付ける SA の roles/iam.serviceAccountUser を付ける）。非排他。
      name            = この付与の名前（重ならない。並べ替え・追加で既存の付与を作り直さないための識別子）
      service_account = 対象の SA（このモジュールの service_accounts の account_id）
      role            = 付ける role
      members         = 付ける相手（ラベル → メンバー）。ラベルは付与の識別子に使うので、メンバーの値が apply まで
                        決まらなくてもよい。"serviceAccount:<email>" など。"sa:<account_id>" でこのモジュールの SA を指す
  EOT
  type = list(object({
    name            = string
    service_account = string
    role            = string
    members         = map(string)
  }))
  default = []

  validation {
    condition     = length(distinct([for binding in var.service_account_iam : binding.name])) == length(var.service_account_iam)
    error_message = "service_account_iam の name が重なっています。"
  }

  validation {
    condition = alltrue(flatten([
      for binding in var.service_account_iam : concat(
        [can(regex("^[A-Za-z0-9_.-]{1,63}$", binding.name))],
        [for label in keys(binding.members) : can(regex("^[A-Za-z0-9_.-]{1,63}$", label))]
      )
    ]))
    error_message = "service_account_iam の name と members のラベルは 1〜63 文字の英数字・_・.・- にしてください。"
  }

  # 同じ SA・同じ role・同じ相手の付与を二重に持たない（片方を外すと、もう片方の付与まで消える）。
  # sa:<account_id> は SA のメールに直して比べる。apply まで決まらない値は比べられない
  validation {
    condition = length(flatten([
      for binding in var.service_account_iam : [
        for member in values(binding.members) : "${binding.service_account}|${binding.role}|${lower(startswith(member, "sa:") ? "serviceAccount:${trimprefix(member, "sa:")}@${var.project_id}.iam.gserviceaccount.com" : member)}"
      ]
      ])) == length(distinct(flatten([
        for binding in var.service_account_iam : [
          for member in values(binding.members) : "${binding.service_account}|${binding.role}|${lower(startswith(member, "sa:") ? "serviceAccount:${trimprefix(member, "sa:")}@${var.project_id}.iam.gserviceaccount.com" : member)}"
        ]
    ])))
    error_message = "service_account_iam に同じ SA・同じ role・同じ相手の付与が重なっています。"
  }

  validation {
    condition = alltrue([
      for binding in var.service_account_iam :
      contains([for sa in var.service_accounts : sa.account_id], binding.service_account)
    ])
    error_message = "service_account_iam の service_account が service_accounts にありません。"
  }

  validation {
    condition = alltrue(flatten([
      for binding in var.service_account_iam : [
        for member in values(binding.members) :
        !startswith(member, "sa:") || contains([for sa in var.service_accounts : sa.account_id], trimprefix(member, "sa:"))
      ]
    ]))
    error_message = "service_account_iam の members の sa:<account_id> が service_accounts にありません。"
  }
}

variable "custom_roles" {
  description = <<-EOT
    プロジェクトのカスタムロール。iam_bindings・service_accounts の roles から "custom:<role_id>" で指す。
      role_id     = 3〜64 文字（英数字・_・.）
      title       = 表示名
      description = 説明
      permissions = 含める権限
      stage       = "GA" / "BETA" / "ALPHA" など（既定 "GA"）
  EOT
  type = list(object({
    role_id     = string
    title       = string
    description = optional(string, "")
    permissions = list(string)
    stage       = optional(string, "GA")
  }))
  default = []

  validation {
    condition     = alltrue([for role in var.custom_roles : can(regex("^[a-zA-Z0-9_.]{3,64}$", role.role_id))])
    error_message = "custom_roles の role_id は 3〜64 文字の英数字・_・. にしてください。"
  }

  validation {
    condition     = alltrue([for role in var.custom_roles : length(role.permissions) > 0])
    error_message = "custom_roles の permissions を 1 つ以上指定してください。"
  }

  validation {
    condition     = length(distinct([for role in var.custom_roles : role.role_id])) == length(var.custom_roles)
    error_message = "custom_roles の role_id が重なっています。"
  }
}

variable "iam_bindings" {
  description = <<-EOT
    プロジェクト単位の IAM（非排他。ほかの付与を消さない）。別のプロジェクトの SA にも付けられる。
      name      = この付与の名前（重ならない。並べ替え・追加で既存の付与を作り直さないための識別子）
      role      = 付ける role（"custom:<role_id>" で custom_roles のロールを指す）
      members   = 付ける相手（ラベル → メンバー）。ラベルは付与の識別子に使うので、メンバーの値が apply まで
                  決まらなくてもよい（別の資源で作る SA のメールなど）。"serviceAccount:<email>" など。
                  "sa:<account_id>" でこのモジュールの SA を指す
      condition = IAM の条件（任意）。{ title, expression, description }
                  例: 資源の名前の接頭辞で絞る
                  resource.name.extract("/instances/{name}").startsWith("vm-")
                  ※ 条件は、同じ相手・同じ role の条件なしの付与（service_accounts の roles や、このモジュールの外の
                    付与）を狭めない。絞りたい相手には条件なしの付与を作らないこと
  EOT
  type = list(object({
    name    = string
    role    = string
    members = map(string)
    condition = optional(object({
      title       = string
      expression  = string
      description = optional(string, "")
    }))
  }))
  default = []

  validation {
    condition     = length(distinct([for binding in var.iam_bindings : binding.name])) == length(var.iam_bindings)
    error_message = "iam_bindings の name が重なっています。"
  }

  validation {
    condition = alltrue(flatten([
      for binding in var.iam_bindings : concat(
        [can(regex("^[A-Za-z0-9_.-]{1,63}$", binding.name))],
        [for label in keys(binding.members) : can(regex("^[A-Za-z0-9_.-]{1,63}$", label))]
      )
    ]))
    error_message = "iam_bindings の name と members のラベルは 1〜63 文字の英数字・_・.・- にしてください。"
  }

  validation {
    condition = alltrue([
      for binding in var.iam_bindings :
      !startswith(binding.role, "custom:") || contains([for custom in var.custom_roles : custom.role_id], trimprefix(binding.role, "custom:"))
    ])
    error_message = "iam_bindings の role の custom:<role_id> が custom_roles にありません。"
  }

  validation {
    condition = alltrue(flatten([
      for binding in var.iam_bindings : [
        for member in values(binding.members) :
        !startswith(member, "sa:") || contains([for sa in var.service_accounts : sa.account_id], trimprefix(member, "sa:"))
      ]
    ]))
    error_message = "iam_bindings の members の sa:<account_id> が service_accounts にありません。"
  }

  # 同じ相手・同じ role の付与を、iam_bindings の中と service_accounts の roles とで二重に持たない
  # （片方を外すと、もう片方の付与まで消える。条件なしの付与があると条件が効かない）。
  # sa:<account_id> は SA のメールに直し、ほかは小文字にして比べる。apply まで決まらない値は比べられない
  validation {
    condition = length(flatten([
      for binding in var.iam_bindings : [for member in values(binding.members) : "${binding.role}|${lower(startswith(member, "sa:") ? "serviceAccount:${trimprefix(member, "sa:")}@${var.project_id}.iam.gserviceaccount.com" : member)}"]
      ])) == length(distinct(flatten([
        for binding in var.iam_bindings : [for member in values(binding.members) : "${binding.role}|${lower(startswith(member, "sa:") ? "serviceAccount:${trimprefix(member, "sa:")}@${var.project_id}.iam.gserviceaccount.com" : member)}"]
    ])))
    error_message = "iam_bindings に同じ role・同じ相手の付与が重なっています。"
  }

  validation {
    condition = alltrue(flatten([
      for binding in var.iam_bindings : [
        for member in values(binding.members) :
        !contains(
          flatten([for sa in var.service_accounts : [for role in sa.roles : lower("${role}|serviceAccount:${sa.account_id}@${var.project_id}.iam.gserviceaccount.com")]]),
          lower("${binding.role}|${lower(startswith(member, "sa:") ? "serviceAccount:${trimprefix(member, "sa:")}@${var.project_id}.iam.gserviceaccount.com" : member)}")
        )
      ]
    ]))
    error_message = "iam_bindings と service_accounts の roles に同じ付与があります（どちらか一方にしてください）。"
  }
}
