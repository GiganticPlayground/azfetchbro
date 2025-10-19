"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
/* Server bootstrap: lightweight scaffolding that wires endpoints and core services */
const express_1 = __importDefault(require("express"));
const core_1 = require("./core");
const adxToken_1 = require("./endpoints/adxToken");
const vaultSecret_1 = require("./endpoints/vaultSecret");
const app = (0, express_1.default)();
app.disable("x-powered-by");
app.use(express_1.default.json());
const POLICY_PATH = process.env.TB_POLICY_FILE ?? "/etc/azfetchbro/policy.json";
const TOKENS_PATH = process.env.TB_TOKENS_FILE ?? "/etc/azfetchbro/tokens.json";
let policy;
let registry;
try {
    policy = new core_1.Policy(POLICY_PATH);
    registry = new core_1.TokenRegistry(TOKENS_PATH);
}
catch (e) {
    console.error(`Startup failure: ${e?.message || e}`);
    process.exit(1);
}
const broker = new core_1.AZFetchBro(policy);
// Public health check (no auth)
app.get("/healthz", (_req, res) => res.json({ ok: true }));
// Attach token key to request (for audit logs)
app.use((req, res, next) => {
    const auth = req.headers["authorization"];
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
    req.tokenKey = tokenKey;
    next();
});
// Register endpoints
(0, adxToken_1.registerAdxTokenEndpoint)(app, broker);
(0, vaultSecret_1.registerVaultSecretEndpoint)(app, broker);
const port = Number(process.env.PORT ?? 8080);
const host = process.env.HOST ?? "0.0.0.0";
app.listen(port, host, () => {
    console.log(JSON.stringify({
        ts: new Date().toISOString(),
        evt: "startup",
        policyPath: POLICY_PATH,
        tokensPath: TOKENS_PATH,
        listen: `${host}:${port}`
    }));
});
