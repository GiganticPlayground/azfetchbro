import { Request, Response } from "express";
import { AZFetchBro, logInfo } from "../core";

export function registerAdxTokenEndpoint(app: any, broker: AZFetchBro) {
    /*  POST /adx/token
        body: { tenantId, clientId, clientSecret }
    */
    app.post("/adx/token", async (req: Request, res: Response) => {
        const b = (req.body ?? {}) as any;
        const tokenKey = (req as any).tokenKey as string;

        try {
            const { token, expiresAt } = await broker.getAdxAccessToken({
                tenantId: String(b.tenantId || ""),
                clientId: String(b.clientId || ""),
                clientSecret: String(b.clientSecret || "")
            });

            res.setHeader("Cache-Control", "no-store");
            logInfo("adx_token_issued", {
                tokenKey,
                expiresAt,
                clientIp: req.ip
            });
            res.json({ access_token: token, token_type: "Bearer", expires_at: expiresAt });
        } catch (e: any) {
            logInfo("adx_token_error", {
                tokenKey,
                error: e?.message ?? "unknown",
                clientIp: req.ip
            });
            res.status(400).json({ error: "mint_failed", detail: e?.message ?? "unknown error" });
        }
    });
}
