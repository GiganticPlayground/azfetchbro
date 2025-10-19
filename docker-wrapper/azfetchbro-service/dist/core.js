"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AZFetchBro = exports.TokenRegistry = exports.Policy = void 0;
exports.sha256Hex = sha256Hex;
exports.normalizeHost = normalizeHost;
exports.logInfo = logInfo;
/* Core utilities and services for the Token Broker API */
const axios_1 = __importDefault(require("axios"));
const crypto_1 = __importDefault(require("crypto"));
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const url_1 = __importDefault(require("url"));
function sha256Hex(input) {
    return crypto_1.default.createHash("sha256").update(input).digest("hex");
}
function normalizeHost(hostLike) {
    return hostLike.trim().toLowerCase();
}
function logInfo(event, data) {
    const payload = {
        ts: new Date().toISOString(),
        evt: event,
        ...data
    };
    // eslint-disable-next-line no-console
    console.log(JSON.stringify(payload));
}
class Policy {
    constructor(filePath) {
        this.allowedVaults = new Set();
        const abs = path_1.default.resolve(filePath);
        if (!fs_1.default.existsSync(abs)) {
            throw new Error(`Policy file not found: ${abs}`);
        }
        const raw = fs_1.default.readFileSync(abs, "utf8");
        const parsed = JSON.parse(raw);
        const kvSection = parsed?.keyVault;
        const list = (kvSection?.allowedVaults ?? []);
        if (Array.isArray(list)) {
            for (const v of list) {
                if (typeof v === "string" && v.trim()) {
                    const name = v.trim().toLowerCase();
                    const normalized = name.endsWith(".vault.azure.net") ? name.split(".")[0] : name;
                    this.allowedVaults.add(normalized);
                }
            }
        }
        this.policy = parsed;
    }
    isVaultAllowed(vaultName) {
        const name = vaultName.trim().toLowerCase();
        const normalized = name.endsWith(".vault.azure.net") ? name.split(".")[0] : name;
        return this.allowedVaults.has(normalized);
    }
}
exports.Policy = Policy;
class TokenRegistry {
    constructor(filePath) {
        this.tokenToKey = new Map();
        const abs = path_1.default.resolve(filePath);
        if (!fs_1.default.existsSync(abs)) {
            throw new Error(`Tokens file not found: ${abs}`);
        }
        const raw = fs_1.default.readFileSync(abs, "utf8");
        const parsed = JSON.parse(raw);
        for (const t of parsed.tokens ?? []) {
            if (t?.key && t?.token) {
                this.tokenToKey.set(t.token, t.key);
            }
        }
    }
    getKeyForBearer(bearerToken) {
        return this.tokenToKey.get(bearerToken);
    }
}
exports.TokenRegistry = TokenRegistry;
class AZFetchBro {
    constructor(policy, opts) {
        this.cache = new Map();
        this.policy = policy;
        this.http = opts?.http ?? axios_1.default.create({ timeout: 10000 });
    }
    async getAdxAccessToken(sp) {
        this.validateSp(sp);
        const resource = "https://api.kusto.windows.net";
        const { access_token, expires_in } = await this.mintToken(sp, resource);
        const expiresAt = Date.now() + expires_in * 1000 - 15000; // small safety margin
        return { token: access_token, expiresAt };
    }
    async getKeyVaultSecret(sp, vaultName, secretName, secretVersion) {
        this.validateSp(sp);
        if (!vaultName || !secretName)
            throw new Error("vaultName and secretName are required");
        // policy check
        if (!this.policy.isVaultAllowed(vaultName)) {
            throw new Error("vault_not_allowed");
        }
        // 1) get AAD token for KV
        const { access_token } = await this.mintToken(sp, "https://vault.azure.net");
        const fqdn = vaultName.endsWith(".vault.azure.net") ? vaultName : `${vaultName}.vault.azure.net`;
        const ver = secretVersion ? `/${encodeURIComponent(secretVersion)}` : "";
        const secretUrl = `https://${fqdn}/secrets/${encodeURIComponent(secretName)}${ver}?api-version=7.4`;
        const res = await this.http.get(secretUrl, {
            headers: {
                Authorization: `Bearer ${access_token}`
            },
            validateStatus: (s) => s >= 200 && s < 500
        });
        if (res.status === 404) {
            throw new Error("secret_not_found");
        }
        if (res.status < 200 || res.status >= 300) {
            const detail = typeof res.data === "string" ? res.data : JSON.stringify(res.data);
            throw new Error(`kv_http_${res.status}:${detail}`);
        }
        const payload = res.data ?? {};
        const value = payload?.value;
        const contentType = payload?.contentType;
        const updatedOn = payload?.attributes?.updated;
        return { vault: fqdn, name: secretName, value, contentType, updatedOn };
    }
    async mintToken(sp, resource) {
        const t = `client_credentials`;
        const cacheKey = this.cacheKey(sp, resource, t);
        const cached = this.cache.get(cacheKey);
        if (cached && !this.isExpired(cached.expiresAt)) {
            return { access_token: cached.value, expires_in: Math.floor((cached.expiresAt - Date.now()) / 1000) };
        }
        const form = new url_1.default.URLSearchParams({
            grant_type: t,
            client_id: sp.clientId,
            client_secret: sp.clientSecret,
            resource
        });
        const tokenUrl = `https://login.microsoftonline.com/${encodeURIComponent(sp.tenantId)}/oauth2/token`;
        const res = await this.http.post(tokenUrl, form.toString(), {
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            validateStatus: (s) => s >= 200 && s < 500
        });
        if (res.status < 200 || res.status >= 300) {
            const detail = typeof res.data === "string" ? res.data : JSON.stringify(res.data);
            throw new Error(`aad_http_${res.status}:${detail}`);
        }
        if (!res?.data?.access_token || !res?.data?.expires_in) {
            throw new Error("AAD did not return access_token/expires_in");
        }
        const expiresAt = Date.now() + res.data.expires_in * 1000 - 10000;
        this.cache.set(cacheKey, { value: res.data.access_token, expiresAt, cachedAt: Date.now() });
        return res.data;
    }
    cacheKey(sp, resource, t) {
        const id = JSON.stringify({
            t,
            tenantId: sp.tenantId,
            clientId: sp.clientId,
            secretLen: sp.clientSecret?.length ?? 0,
            res: resource
        });
        return sha256Hex(id);
    }
    isExpired(expiresAtMs) {
        return Date.now() >= expiresAtMs;
    }
    validateSp(sp) {
        if (!sp?.tenantId || !sp?.clientId || !sp?.clientSecret) {
            throw new Error("Invalid Service Principal: tenantId, clientId, clientSecret are required.");
        }
    }
}
exports.AZFetchBro = AZFetchBro;
