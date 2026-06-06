import { parse as parseYaml } from "yaml";
import { z } from "zod";

const billingAccountEntrySchema = z.object({
  billing_account_id: z.string(),
  description: z.string().optional(),
});

const billingAccountsSchema = z.object({
  billing_accounts: z.record(z.string(), billingAccountEntrySchema),
});

export function resolveBillingAccount(raw: string, key: string): string {
  const parsed: unknown = parseYaml(raw);
  const registry = billingAccountsSchema.parse(parsed);
  const entry = registry.billing_accounts[key];
  if (!entry) {
    throw new Error(
      `billing_account_key "${key}" not found in billing-accounts.yml. ` +
        `Available keys: ${Object.keys(registry.billing_accounts).join(", ")}`
    );
  }
  return entry.billing_account_id;
}
