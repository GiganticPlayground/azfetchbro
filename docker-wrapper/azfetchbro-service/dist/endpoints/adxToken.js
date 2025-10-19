"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.registerAdxTokenEndpoint = registerAdxTokenEndpoint;
const core_1 = require("../core");
function registerAdxTokenEndpoint(app, broker) {
    /*  POST /adx/token
        body: { tenantId, clientId, clientSecret }
    */
    app.post("/adx/token", async (req, res) => {
        const b = (req.body ?? {});
        const tokenKey = req.tokenKey;
        try {
            const { token, expiresAt } = await broker.getAdxAccessToken({
                tenantId: String(b.tenantId || ""),
                clientId: String(b.clientId || ""),
                clientSecret: String(b.clientSecret || "")
            });
            res.setHeader("Cache-Control", "no-store");
            (0, core_1.logInfo)("adx_token_issued", {
                tokenKey,
                expiresAt,
                clientIp: req.ip
            });
            res.json({ access_token: token, token_type: "Bearer", expires_at: expiresAt });
        }
        catch (e) {
            (0, core_1.logInfo)("adx_token_error", {
                tokenKey,
                error: e?.message ?? "unknown",
                clientIp: req.ip
            });
            res.status(400).json({ error: "mint_failed", detail: e?.message ?? "unknown error" });
        }
    });
}
