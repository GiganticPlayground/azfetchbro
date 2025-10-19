"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.registerVaultSecretEndpoint = registerVaultSecretEndpoint;
const core_1 = require("../core");
function registerVaultSecretEndpoint(app, broker) {
    /*  POST /vault/secret
        body: { tenantId, clientId, clientSecret, vaultName, secretName, secretVersion? }
    */
    app.post("/vault/secret", async (req, res) => {
        const b = (req.body ?? {});
        const tokenKey = req.tokenKey;
        try {
            const result = await broker.getKeyVaultSecret({
                tenantId: String(b.tenantId || ""),
                clientId: String(b.clientId || ""),
                clientSecret: String(b.clientSecret || "")
            }, String(b.vaultName || ""), String(b.secretName || ""), b.secretVersion ? String(b.secretVersion) : undefined);
            res.setHeader("Cache-Control", "no-store");
            (0, core_1.logInfo)("kv_secret_fetched", {
                tokenKey,
                vault: result.vault,
                name: result.name,
                clientIp: req.ip
            });
            res.json(result);
        }
        catch (e) {
            (0, core_1.logInfo)("kv_secret_error", {
                tokenKey,
                error: e?.message ?? "unknown",
                clientIp: req.ip
            });
            const code = e?.message === "vault_not_allowed" ? 403 : 400;
            res.status(code).json({ error: "kv_fetch_failed", detail: e?.message ?? "unknown error" });
        }
    });
}
