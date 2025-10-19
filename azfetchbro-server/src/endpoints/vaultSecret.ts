import { Request, Response } from "express";
import { AZFetchBro, logInfo } from "../core";

export function registerVaultSecretEndpoint(app: any, broker: AZFetchBro) {
    /*  POST /vault/secret
        body: { tenantId, clientId, clientSecret, vaultName, secretName, secretVersion? }
    */
    app.post("/vault/secret", async (req: Request, res: Response) => {
        const b = (req.body ?? {}) as any;
        const tokenKey = (req as any).tokenKey as string;

        try {
            const result = await broker.getKeyVaultSecret(
                {
                    tenantId: String(b.tenantId || ""),
                    clientId: String(b.clientId || ""),
                    clientSecret: String(b.clientSecret || "")
                },
                String(b.vaultName || ""),
                String(b.secretName || ""),
                b.secretVersion ? String(b.secretVersion) : undefined
            );

            res.setHeader("Cache-Control", "no-store");
            logInfo("kv_secret_fetched", {
                tokenKey,
                vault: result.vault,
                name: result.name,
                clientIp: req.ip
            });
            res.json(result);
        } catch (e: any) {
            logInfo("kv_secret_error", {
                tokenKey,
                error: e?.message ?? "unknown",
                clientIp: req.ip
            });
            const code = e?.message === "vault_not_allowed" ? 403 : 400;
            res.status(code).json({ error: "kv_fetch_failed", detail: e?.message ?? "unknown error" });
        }
    });
}
