# AZFetchBro README
A small, secure token broker that requests short‑lived tokens for:
- Azure Data Explorer (ADX) — AAD access tokens using a Service Principal
- Azure Key Vault — policy‑controlled retrieval of secrets using a Service Principal

azfetchbro runs as a minimal HTTP service (Node.js/Express) intended to sit behind your own network boundaries. Callers 
authenticate with a static Bearer token from a registry file, and requests are policy‑checked before any token is 
requested or secret is retrieved. Results are cached in‑memory until shortly before expiry to reduce upstream calls.

## Highlights
- Multiple clients: support for multiple Bearer tokens (each mapped to a "key" for audit logging)
- In‑memory caching with skew: avoids re‑requesting too close to expiry
- Minimal surface area: small set of endpoints plus a health check
- Container‑first: small, non‑root Docker image and Docker Compose example

## How it works
- Authentication: every request must include Authorization: Bearer <token>. Tokens are validated against tokens.json. 
  Unknown tokens are rejected.
- Token requests:
  - ADX: exchanges a Service Principal (tenantId, clientId, clientSecret) for an AAD token scoped to https://api.kusto.windows.net 
    (configurable via TB_ADX_RESOURCE)
- Caching: tokens are cached in memory until expiry minus TB_EXPIRY_SKEW_MS (default 120s).
- Logging: structured JSON logs with event names like startup, adx_token_issued, adx_token_error. Sensitive values 
  (secrets/tokens) are not logged.

## Quick start
You can run azfetchbro locally or via Docker. Example config templates are included:
- policy.example.json (template; can be an empty JSON object {})
- tokens.example.json (template; caller token registry)

Use these example files as templates to create your real configuration files (policy.json and tokens.json). The real 
files are intentionally not committed to source control (see .gitignore) because they may contain sensitive values.

### Running Locally via NodeJS

1) Install and build
- Node.js 20+
- npm ci
- npm run build
- npm start

2) Environment variables (defaults are suitable for local use)
- TB_ADX_RESOURCE: https://api.kusto.windows.net
- TB_EXPIRY_SKEW_MS: 120000 (ms)
- TB_POLICY_FILE: ./policy.json
- TB_TOKENS_FILE: ./tokens.json

3) Provide config files
- Place policy.json and tokens.json somewhere readable by the process
- Point TB_POLICY_FILE and TB_TOKENS_FILE to those paths

Example minimal policy.json:
```json
{
  "keyVault": {
    "allowedVaults": [
      "myvault"
    ]
  }
}
```

Example minimal tokens.json:
```json
{
  "tokens": [
    { "key": "P123-AWS-SERVER", "token": "XXXXXXXXXXXXXXXX" },
    { "key": "P123-SITE-SERVER",  "token": "YYYYYYYYYYYYYYYY" }
  ]
}
```

## Running via Docker

A hardened image is provided via the Dockerfile. It runs as a non‑root user, and the container stack exposes HTTPS via 
NGINX with a built‑in healthcheck.

Build locally:
- `npm run build`
- `docker compose build`

Docker Compose Run (compose.yml):
- Two services: azfetchbro (Node app on 8080, internal to Docker only) and nginx (TLS terminator/reverse proxy) exposed 
  on 8443 to the host.
- nginx terminates TLS and proxies to azfetchbro on http://127.0.0.1:8080
- nginx binds to 127.0.0.1 by default and exposes the external HTTPS port on the host (default 8443)
- nginx health endpoint: GET https://127.0.0.1:8443/nginx-health
- Mounts policy.json and tokens.json read‑only to the azfetchbro service
- Sets conservative ulimits and drops capabilities
- `docker compose up -d`

NGINX config and certs used by docker-compose:
- Config file: docker-wrapper/nginx-service/nginx.conf (mounted to /etc/nginx/nginx.conf)
- TLS materials directory (mounted read-only as /etc/nginx/external): docker-wrapper/nginx-service/certs/
- See _tls_helper/ for generating dev certs and distributing them to the nginx certs directory

## API reference
All endpoints require Authorization: Bearer <token>. The bearer tokens are defined in tokens.json. Unknown tokens get 403. 
Missing/invalid header gets 401.

Common headers:
- Content-Type: application/json
- Authorization: Bearer XXXXXXXXXXXXXXXXXXXX

1) POST /adx/token
- Body:
  ```text
  {
    "tenantId": "<GUID>",
    "clientId": "<GUID>",
    "clientSecret": "<secret>"
  }
  ```
- Response 200:
  ```
  {
    "access_token": "<token>",
    "token_type": "Bearer",
    "expires_at": 1730000000000
  }
  ```
- Notes:
  - access_token is cached until expires_at - TB_EXPIRY_SKEW_MS
  - TB_ADX_RESOURCE controls the AAD resource (default: https://api.kusto.windows.net)

Example curl:
```bash
curl -sS --insecure -X POST https://localhost:8443/adx/token \
-H "Authorization: Bearer XXXXXXXXXXXXXXXXX" \
-H "Content-Type: application/json" \
-d '{
      "tenantId":"<tenant>",
      "clientId":"<client>",
      "clientSecret":"<secret>"
    }'
```
2) POST /vault/secret
- Body:
  ```text
  {
    "tenantId": "<GUID>",
    "clientId": "<GUID>",
    "clientSecret": "<secret>",
    "vaultName": "myvault",          // bare name or FQDN
    "secretName": "my-secret",       // required
    "secretVersion": "<optional>"    // optional
  }
  ```
- Response 200:
  ```
  {
    "vault": "kv-azfetchbro-demo.vault.azure.net",
    "name": "apiKey",
    "value": "super-secret-value",
    "contentType": "managed-by-terraform",
    "updatedOn": 1760829339
  }
  ```
- Notes:
  - The vaultName must be allowed by policy.json under keyVault.allowedVaults (see Policy section below)
  - Uses the provided Service Principal to get an AAD token for https://vault.azure.net
  - The response's vault field is always the FQDN form (e.g., myvault.vault.azure.net) regardless of whether you pass a bare name or FQDN
  - updatedOn is the Unix epoch time in seconds returned by Azure Key Vault (attributes.updated)
  - The requested token is cached with skew similar to ADX tokens

Example curl:
```bash
curl -sS --insecure -X POST https://localhost:8443/vault/secret \
 -H "Authorization: Bearer XXXXXXXXXXXXXXXXX" \
 -H "Content-Type: application/json" \
 -d '{
       "tenantId":"<tenant>",
       "clientId":"<client>",
       "clientSecret":"<secret>",
       "vaultName":"myvault",
       "secretName":"my-secret"
     }'
```

3) GET /healthz
- Response 200: `{ "ok": true }`

Example curl:
```bash
curl -sS --insecure -X POST https://localhost:8443/healthz \
 -H "Authorization: Bearer XXXXXXXXXXXXXXXXX"
```

### Errors
- 401 unauthorized — missing/invalid Authorization header
- 403 forbidden — bearer token not found in tokens.json
- 400 mint_failed — validation or token request failure; JSON body includes a detail message


## Configuration
Environment variables (with defaults):
- TB_ADX_RESOURCE: ADX resource for AAD (default https://api.kusto.windows.net)
- TB_EXPIRY_SKEW_MS: milliseconds to subtract from upstream expires_in when caching (default 120000)
- TB_POLICY_FILE: path to policy.json
- TB_TOKENS_FILE: path to tokens.json

Policy file (policy.json):
- keyVault.allowedVaults: array of allowed Azure Key Vaults by name (bare name or FQDN). Requests to /vault/secret are 
  denied if vaultName is not on this list.

Example policy.json:
```
{
  "keyVault": {
    "allowedVaults": [
      "myvault",                    
      "anothervault.vault.azure.net"
    ]
  }
}
```

Tokens file (tokens.json):
- tokens: array of { key, token }
- key is an identifier written to logs; token is the secret presented as the Bearer value
- keys and tokens must be unique; file must contain at least one entry

## Logging and observability
- Structured JSON to stdout with event names: startup, adx_token_issued, adx_token_error
- Fields avoid secrets; includes tokenKey, expiresAt, and clientIp
- Health check at /nginx-health

## Security model and recommendations
- Keep azfetchbro on a trusted network; do not expose publicly
- Store tokens.json and policy.json as read‑only mounts in containers; restrict file access
- Rotate bearer tokens periodically; each token maps to a distinct key for auditing
- Present this via a reverse proxy with TLS termination (nginx reverse proxy is included in the Docker image and compose setup)
- For ADX, prefer limiting which services can call azfetchbro rather than embedding SP secrets widely

## NGINX front-end responsibilities
- TLS termination for inbound HTTPS
- Reverse proxy to the azfetchbro service over HTTP on 127.0.0.1:8080
- Health endpoint exposed at /nginx-health (used by Docker healthcheck)
- External bind/port control via the compose `ports` mapping (defaults to host 127.0.0.1 and port 8443)
- Configuration and certificates are provided from the repository and mounted read-only into the container

Where to find/change things:
- docker-wrapper/compose.yml controls service wiring and the host port via the `NGINX_PORT` environment variable.
- docker-wrapper/nginx-service/nginx.conf contains the NGINX server block and proxy settings.
- docker-wrapper/nginx-service/certs/ contains TLS files referenced by nginx.conf (see that folder’s README and _tls_helper/).

## Change the external HTTPS port (NGINX_PORT)
By default the stack binds NGINX to 127.0.0.1:8443 on the host:
- compose.yml excerpt: `ports: ["127.0.0.1:${NGINX_PORT:-8443}:8443"]`
- Inside the container, NGINX listens on 8443. The host-side port is configurable via the `NGINX_PORT` env var.

Change the port temporarily when starting:
- `NGINX_PORT=9443 docker compose up -d`

Or set it in a .env file (same directory as compose.yml):
- Create docker-wrapper/.env with: `NGINX_PORT=9443`
- Then run: `docker compose up -d`

Verify with curl (self-signed dev certs require --insecure):
- `curl --insecure -sS https://127.0.0.1:9443/healthz`
- `curl --insecure -sS https://127.0.0.1:9443/nginx-health`

Note:
- Only the host port changes via NGINX_PORT. The container’s NGINX continues to listen on 8443 as defined in nginx.conf.
- The compose mapping binds to 127.0.0.1 by default for local-only exposure. If you need to expose on all interfaces, you can
  edit compose.yml to use `${NGINX_BIND_ADDR:-127.0.0.1}` and set NGINX_BIND_ADDR to 0.0.0.0 in your environment.

## Development
- npm run dev to run with TSX and auto‑reload (reads .env if present)
- npm run build to emit dist/
- npm start runs the compiled server (also reads .env)

## Troubleshooting
- Startup failure: check that TB_POLICY_FILE and TB_TOKENS_FILE point to readable JSON files and have valid structure
- 401/403 errors: confirm Authorization header and that the bearer token exists in tokens.json
- Clock skew issues: adjust TB_EXPIRY_SKEW_MS if tokens are used right at the edge of expiry

## Developer tool: _tls_helper (self-signed TLS)
The repository includes a small developer tool in the _tls_helper directory to help you stand up HTTPS locally using a 
self-signed certificate. This is intended only for development.

- What it does:
  - Generates a local CA and a server certificate valid for your chosen hostname, plus localhost and 127.0.0.1.
  - Produces server.crt.pem, server.key.pem, and dhparam.pem under _tls_helper/certs/.
  - Provides a helper script to copy those files into docker-wrapper/nginx-service/certs/, which docker-compose mounts 
    into NGINX at /etc/nginx/external.
- Where to start:
  - See _tls_helper/README.md for step-by-step instructions.
- Important when testing with curl:
  - Because these certs are self-signed, curl will reject them by default. When you hit the HTTPS endpoint 
    (e.g., https://127.0.0.1:8443), add --insecure to your curl commands during DEV:
    - curl --insecure -sS https://127.0.0.1:8443/healthz
  - Alternatively, you can add the generated ca.crt.pem to your local trust store (DEV machines only) to avoid --insecure.

## Infrastructure demo (Terraform)
The repository includes a helper Terraform stack in the `_infrastructure_demo` directory that you can use to quickly s
pin up Azure resources for testing azfetchbro end‑to‑end.

What it sets up:
- An Azure Resource Group
- An Azure Key Vault
- An Azure AD Application and Service Principal (with a client secret)
- RBAC so the Service Principal can read Key Vault secrets
- A few demo secrets written into the Key Vault

Important:
- You must have an active Azure subscription to use this demo.
- Applying this Terraform will create Azure resources that may incur charges from Microsoft. Use at your own cost and 
  remember to destroy when finished.

Getting started:
- See `_infrastructure_demo/README.md` for prerequisites, variables, and helper scripts (`./x-plan.sh`, `./x-apply.sh`, 
  `./x-destroy.sh`).
- After apply, you can use the created Service Principal (tenantId, clientId, clientSecret) and Key Vault name with 
  the azfetchbro’s `/vault/secret` endpoint to validate your setup.
