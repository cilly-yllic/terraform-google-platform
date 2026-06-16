.PHONY: bootstrap bootstrap-check bootstrap-print-env grant-billing
.PHONY: create-billing-account create-billing-account-check create-billing-account-print-env
.PHONY: setup-router-hmac rotate-router-hmac sync-router-hmac set-github-app-private-key

bootstrap:
	bash scripts/bootstrap.sh apply

bootstrap-check:
	bash scripts/bootstrap.sh check

bootstrap-print-env:
	bash scripts/bootstrap.sh print-env

# Grant `roles/billing.user` on a specific billing account to the
# Terraform Project Factory SA. Use this for **external billing accounts**
# (different org from BOOTSTRAP_PROJECT) where the bootstrap's org-level
# grant does not reach. For org-owned billing accounts, `make bootstrap` already
# covers all of them via the org-level binding — this target is unnecessary.
# usage: make grant-billing BILLING=01XXXX-XXXXXX-XXXXXX
grant-billing:
	@[ -n "$(BILLING)" ] || (echo "Usage: make grant-billing BILLING=<billing-account-id>" >&2; exit 1)
	bash scripts/grant-billing.sh "$(BILLING)"

create-billing-account:
	bash scripts/create-billing-account.sh apply

create-billing-account-check:
	bash scripts/create-billing-account.sh check

create-billing-account-print-env:
	bash scripts/create-billing-account.sh print-env

# --- Cloud Run router runtime secrets ---

# Initial setup: generate HMAC, register in Secret Manager,
# sync to TFC_NOTIFICATION_SECRET_REPOS GitHub repos.
setup-router-hmac:
	bash scripts/router-hmac.sh setup

# Rotate: generate new HMAC, add new version, re-sync to all repos.
# Cloud Run service の revision を更新 (再 deploy) しないと latest version
# が読み込まれない点に注意。
rotate-router-hmac:
	bash scripts/router-hmac.sh rotate

# Sync existing latest value to TFC_NOTIFICATION_SECRET_REPOS GitHub repos
# (useful after adding a new repo to the list without rotating the secret).
sync-router-hmac:
	bash scripts/router-hmac.sh sync

# Add GitHub App private key (PEM) to Secret Manager as new version.
# usage: make set-github-app-private-key PEM=path/to/key.pem
set-github-app-private-key:
	@[ -n "$(PEM)" ] || (echo "Usage: make set-github-app-private-key PEM=path/to/key.pem" >&2; exit 1)
	bash scripts/router-pem.sh add "$(PEM)"
