# shellcheck shell=bash
show_help() {
  cat <<'EOF'
Usage: scripts/bootstrap.sh [OPTIONS] <SUBCOMMAND>

Bootstrap the infra-bootstrap GCP Project, Service Account, and Workload
Identity Federation resources required by the project-bootstrap module.

SUBCOMMANDS
  check       Verify prerequisites (commands, auth, env vars, existing
              GCP resources). No changes are made.
  apply       Create all bootstrap resources (idempotent). Runs check
              first, then creates missing resources.
  print-env   Print the Terraform Cloud Workspace variables to configure
              after a successful apply.

OPTIONS
  -h, --help      Show this help message and exit.
  -d, --dry-run   Self-check mode: display environment variable status
                  and configuration summary without calling any GCP API.
  -i, --init      Generate a .env or .envrc template from
                  scripts/bootstrap.example.env.
                  Interactive by default; use --init=env or --init=envrc
                  to skip the prompt.

ENVIRONMENT VARIABLES (loaded from .env)
  Required:
    BOOTSTRAP_PROJECT_ID                 GCP Project ID for bootstrap
    BOOTSTRAP_PROJECT_NAME               Display name for the project
    BILLING_ACCOUNT_ID                   Billing Account to link
    TERRAFORM_PROJECT_FACTORY_SA_ID      Service Account ID
    WORKLOAD_IDENTITY_POOL_ID            WIF Pool ID
    WORKLOAD_IDENTITY_PROVIDER_ID        WIF Provider ID
    TFC_ORGANIZATION_NAME                Terraform Cloud org name

  Required (one of):
    ORGANIZATION_ID                      Numeric org ID
    FOLDER_ID                            Numeric folder ID

  Optional:
    TERRAFORM_PROJECT_FACTORY_SA_DISPLAY_NAME
                                         SA display name
    WORKLOAD_IDENTITY_POOL_DISPLAY_NAME  Pool display name
    WORKLOAD_IDENTITY_PROVIDER_DISPLAY_NAME
                                         Provider display name
    CONFIRM_BEFORE_APPLY                 Prompt before apply (default: true)

  Optional (Budget — created only when BUDGET_AMOUNT is set):
    BUDGET_AMOUNT                        Monthly budget amount (e.g. 1000).
                                         Budget is created only when set.
    BUDGET_CURRENCY                      Budget currency (default: USD)
    BUDGET_DISPLAY_NAME                  Budget display name
                                         (default: "${BOOTSTRAP_PROJECT_NAME} Budget")
    BUDGET_SCOPE                         'project' (default) — monitors
                                         BOOTSTRAP_PROJECT_ID only.
                                         'billing-account' — monitors entire
                                         billing account.
    BUDGET_THRESHOLDS                    Comma-separated alert thresholds as
                                         fractions (default:
                                         0.1,0.3,0.5,0.9,1.0)

  Optional (Cloud Run deploy — created only when
   ENABLE_CLOUD_RUN_DEPLOY_SETUP=true):
    ENABLE_CLOUD_RUN_DEPLOY_SETUP        Set to 'true' to provision GitHub
                                         WIF Provider + deploy/runtime SAs
                                         for cloud-run-router. Default: false.
    GITHUB_REPOSITORY                    'owner/repo' allowed to authenticate
                                         via the GitHub WIF Provider.
                                         Required when ENABLE_CLOUD_RUN_DEPLOY_SETUP=true.
    CLOUD_RUN_DEPLOY_SA_ID               Deploy SA ID
                                         (default: cloud-run-router-deploy)
    CLOUD_RUN_DEPLOY_SA_DISPLAY_NAME     Deploy SA display name
                                         (default: Cloud Run Router Deploy)
    CLOUD_RUN_RUNTIME_SA_ID              Runtime SA ID
                                         (default: cloud-run-router-runtime)
    CLOUD_RUN_RUNTIME_SA_DISPLAY_NAME    Runtime SA display name
                                         (default: Cloud Run Router Runtime)
    GITHUB_WIF_PROVIDER_ID               GitHub OIDC Provider ID
                                         (default: github-actions)
    GITHUB_WIF_PROVIDER_DISPLAY_NAME     Provider display name
                                         (default: GitHub Actions)

EXAMPLES
  # Show this help
  scripts/bootstrap.sh --help

  # Generate .env template
  scripts/bootstrap.sh --init

  # Self-check environment variables
  scripts/bootstrap.sh --dry-run

  # Run full check (calls GCP APIs)
  scripts/bootstrap.sh check

  # Create resources
  scripts/bootstrap.sh apply

  # Print TFC workspace variables
  scripts/bootstrap.sh print-env

See also: docs/bootstrap.md, scripts/README.md
EOF
}
