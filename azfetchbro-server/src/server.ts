/* Server bootstrap: lightweight scaffolding that wires endpoints and core services */
import express, { Request, Response, NextFunction } from "express";
import { Policy, TokenRegistry, AZFetchBro, logInfo } from "./core";
import { registerAdxTokenEndpoint } from "./endpoints/adxToken";
import { registerVaultSecretEndpoint } from "./endpoints/vaultSecret";

const app = express();
app.disable("x-powered-by");
app.use(express.json());

const POLICY_PATH = process.env.TB_POLICY_FILE ?? "/etc/azfetchbro/policy.json";
const TOKENS_PATH = process.env.TB_TOKENS_FILE ?? "/etc/azfetchbro/tokens.json";

let policy: Policy;
let registry: TokenRegistry;
try {
    policy = new Policy(POLICY_PATH);
    registry = new TokenRegistry(TOKENS_PATH);
} catch (e: any) {
    console.error(`Startup failure: ${e?.message || e}`);
    process.exit(1);
}

const broker = new AZFetchBro(policy);

// Public health check (no auth)
app.get("/healthz", (_req: Request, res: Response) => res.json({ ok: true }));

// Attach token key to request (for audit logs)
app.use((req: Request, res: Response, next: NextFunction) => {
    const auth = req.headers["authorization"] as string | undefined;
    if (!auth || !auth.startsWith("Bearer ")) {
        res.status(401).json({ error: "unauthorized" });
        return;
    }
    const bearer = auth.slice("Bearer ".length).trim();
    const tokenKey = registry.getKeyForBearer(bearer);
    if (!tokenKey) {
        res.status(403).json({ error: "forbidden" });
        return;
    }
    (req as any).tokenKey = tokenKey;
    next();
});

// Register endpoints
registerAdxTokenEndpoint(app, broker);
registerVaultSecretEndpoint(app, broker);

const port = Number(process.env.PORT ?? 8080);
const host = process.env.HOST ?? "0.0.0.0";

app.listen(port, host, () => {
    console.log(
        JSON.stringify({
            ts: new Date().toISOString(),
            evt: "startup",
            policyPath: POLICY_PATH,
            tokensPath: TOKENS_PATH,
            listen: `${host}:${port}`
        })
    );
});