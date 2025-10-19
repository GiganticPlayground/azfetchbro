/* Core utilities and services for the Token Broker API */
import axios, { AxiosInstance } from "axios";
import crypto from "crypto";
import fs from "fs";
import path from "path";
import url from "url";

export type AdxServicePrincipalAuth = {
    tenantId: string;
    clientId: string;
    clientSecret: string;
};

export type CachedEntry = {
    value: string;       // token (ADX JWT) or SAS
    expiresAt: number;   // epoch ms
    cachedAt: number;    // epoch ms
};

export type AADTokenResponse = {
    access_token: string;
    expires_in: number;  // seconds
    token_type?: string;
};

export type AZFetchBroPolicy = Record<string, unknown>;

export type TokensFile = {
    tokens: Array<{ key: string; token: string }>;
};

export function sha256Hex(input: string): string {
    return crypto.createHash("sha256").update(input).digest("hex");
}

export function normalizeHost(hostLike: string): string {
    return hostLike.trim().toLowerCase();
}

export function logInfo(event: string, data: Record<string, unknown>) {
    const payload = {
        ts: new Date().toISOString(),
        evt: event,
        ...data
    };
    // eslint-disable-next-line no-console
    console.log(JSON.stringify(payload));
}

export class Policy {
    private policy: AZFetchBroPolicy;
    private allowedVaults: Set<string> = new Set<string>();

    constructor(filePath: string) {
        const abs = path.resolve(filePath);
        if (!fs.existsSync(abs)) {
            throw new Error(`Policy file not found: ${abs}`);
        }
        const raw = fs.readFileSync(abs, "utf8");
        const parsed = JSON.parse(raw) as AZFetchBroPolicy;

        const kvSection = (parsed as any)?.keyVault;
        const list = (kvSection?.allowedVaults ?? []) as unknown;
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

    public isVaultAllowed(vaultName: string): boolean {
        const name = vaultName.trim().toLowerCase();
        const normalized = name.endsWith(".vault.azure.net") ? name.split(".")[0] : name;
        return this.allowedVaults.has(normalized);
    }
}

export class TokenRegistry {
    private tokenToKey = new Map<string, string>();

    constructor(filePath: string) {
        const abs = path.resolve(filePath);
        if (!fs.existsSync(abs)) {
            throw new Error(`Tokens file not found: ${abs}`);
        }
        const raw = fs.readFileSync(abs, "utf8");
        const parsed = JSON.parse(raw) as TokensFile;
        for (const t of parsed.tokens ?? []) {
            if (t?.key && t?.token) {
                this.tokenToKey.set(t.token, t.key);
            }
        }
    }

    public getKeyForBearer(bearerToken: string): string | undefined {
        return this.tokenToKey.get(bearerToken);
    }
}

export class AZFetchBro {
    private http: AxiosInstance;
    private cache = new Map<string, CachedEntry>();
    private policy: Policy;

    constructor(policy: Policy, opts?: { http?: AxiosInstance }) {
        this.policy = policy;
        this.http = opts?.http ?? axios.create({ timeout: 10000 });
    }

    public async getAdxAccessToken(sp: AdxServicePrincipalAuth): Promise<{ token: string; expiresAt: number }> {
        this.validateSp(sp);
        const resource = "https://api.kusto.windows.net";
        const { access_token, expires_in } = await this.mintToken(sp, resource);
        const expiresAt = Date.now() + expires_in * 1000 - 15_000; // small safety margin
        return { token: access_token, expiresAt };
    }

    public async getKeyVaultSecret(
        sp: AdxServicePrincipalAuth,
        vaultName: string,
        secretName: string,
        secretVersion?: string
    ): Promise<{ vault: string; name: string; value: string; contentType?: string; updatedOn?: string }>
    {
        this.validateSp(sp);
        if (!vaultName || !secretName) throw new Error("vaultName and secretName are required");

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

    private async mintToken(sp: AdxServicePrincipalAuth, resource: string): Promise<AADTokenResponse> {
        const t = `client_credentials`;
        const cacheKey = this.cacheKey(sp, resource, t);
        const cached = this.cache.get(cacheKey);
        if (cached && !this.isExpired(cached.expiresAt)) {
            return { access_token: cached.value, expires_in: Math.floor((cached.expiresAt - Date.now()) / 1000) };
        }

        const form = new url.URLSearchParams({
            grant_type: t,
            client_id: sp.clientId,
            client_secret: sp.clientSecret,
            resource
        });

        const tokenUrl = `https://login.microsoftonline.com/${encodeURIComponent(sp.tenantId)}/oauth2/token`;
        const res = await this.http.post<AADTokenResponse>(tokenUrl, form.toString(), {
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
        const expiresAt = Date.now() + res.data.expires_in * 1000 - 10_000;
        this.cache.set(cacheKey, { value: res.data.access_token, expiresAt, cachedAt: Date.now() });
        return res.data;
    }

    private cacheKey(sp: AdxServicePrincipalAuth, resource: string, t: string): string {
        const id = JSON.stringify({
            t,
            tenantId: sp.tenantId,
            clientId: sp.clientId,
            secretLen: sp.clientSecret?.length ?? 0,
            res: resource
        });
        return sha256Hex(id);
    }

    private isExpired(expiresAtMs: number): boolean {
        return Date.now() >= expiresAtMs;
    }

    private validateSp(sp: AdxServicePrincipalAuth) {
        if (!sp?.tenantId || !sp?.clientId || !sp?.clientSecret) {
            throw new Error("Invalid Service Principal: tenantId, clientId, clientSecret are required.");
        }
    }
}
