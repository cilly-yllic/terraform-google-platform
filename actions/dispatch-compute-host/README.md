# dispatch-tfc-compute-host

A GitHub Action that starts Terraform Cloud Runs for [`modules/compute-host-platform`](../../modules/compute-host-platform/) (a project that hosts Compute Engine VMs, separate from the Firebase project).

`settings.yml` の env ごとの `compute_host` を compute-host-platform モジュールの変数に渡し、env ごとに **`{service}-{env}` workspace の upsert → 変数の同期 → Run の作成**を順に行う。対象の env の選び方（`environments` / `labels`・`status`）、workspace の後片付け（`retained_envs`）、Dynamic Credentials は [`dispatch-firebase-platform`](../dispatch-firebase-platform/)（Action B）と同じ。

プロジェクトと terraform の SA は [`dispatch-project-bootstrap`](../dispatch-project-bootstrap/)（Action A）で作る。compute host 用の settings.yml を Firebase のプロジェクトのものとは別に置き、`service` を compute host 用の短い名前にすると、プロジェクト ID は `${service}-${env}`（例 `example-host-dev-001`）になる。

## Usage

```yaml
- uses: cilly-yllic/terraform-google-platform/actions/dispatch-compute-host@v2.1.0
  with:
    module_version: "~> 2.1"                # Action のタグと同じ major に固定
    service: example-host
    environments: '["dev-001"]'
    settings_path: terraform/compute-host.settings.yml
    tfc_org: my-tfc-org
    bootstrap_project_number: "123456789012"
    tfc_token: ${{ secrets.TFC_TOKEN }}
```

## settings.yml

```yaml
service: example-host

environments:
  dev-001:
    labels: ["tier:dev"]
    billing_account_id: "000000-000000-000000"   # Action A が読む
    compute_host:
      region: asia-northeast1
      network:
        name: vm
        subnets:
          - name: vm-asia-northeast1
            cidr: 10.10.0.0/20
      cloud_nat:
        router_name: vm-router
        nat_name: vm-nat
      firewall_rules:
        - name: deny-internal-egress
          direction: EGRESS
          action: deny
          priority: 900
          ranges: ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
      service_accounts:
        - account_id: vm-runtime
      custom_roles:
        - role_id: vmManager
          title: VM manager
          permissions: ["compute.instances.create", "compute.instances.start", "compute.instances.stop"]
      iam_bindings:
        - name: manager-vms
          role: custom:vmManager
          members:
            manager: serviceAccount:manager@other-project.iam.gserviceaccount.com
      service_account_iam:
        - name: manager-acts-as-runtime
          service_account: vm-runtime
          role: roles/iam.serviceAccountUser
          members:
            manager: serviceAccount:manager@other-project.iam.gserviceaccount.com
```

- 受け付けるキーは `region`・`apis`・`api_propagation_wait`・`network`・`firewall_rules`・`cloud_nat`・`service_accounts`・`service_account_iam`・`custom_roles`・`iam_bindings`（モジュールの変数と同じ。`project_id` はこの Action が決める）。知らないキー・形の違う値は Action が止める
- 書いたキーだけを TFC の変数にする。書いていないキーはモジュールの既定値になり、消したキーの変数は消える
- `${service}`・`${env}`・`${BOOTSTRAP_PROJECT_NUMBER}` の placeholder を使える（dispatch-firebase-platform と同じ）
- 中身の検証はモジュールの変数の検証で行う（plan で止まる）

## Inputs / Outputs

[`action.yml`](./action.yml) を参照（dispatch-firebase-platform から `cloud_sql_secrets` を除いたもの）。
