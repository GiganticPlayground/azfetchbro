# _tls_helper README — local TLS developer tool

This directory contains a tiny, self-contained helper to generate a local Certificate Authority (CA) and a self-signed 
server certificate for development. It is intended for quick local HTTPS testing with the dockerized NGINX reverse proxy 
included in this repo.

What this is (and isn’t)
- Is: a convenience for DEV to get you running HTTPS locally without touching real PKI.
- Is not: production-ready PKI. The generated CA and server certificate are not trusted by clients and are insecure for 
  production use. Use only in development.

Outputs
The helper writes all artifacts to _tls_helper/certs/:
- ca.crt.pem — Local root CA certificate (10 years)
- ca.key.pem — Local root CA private key (kept locally; do not commit)
- server.key.pem — Server private key (2048-bit)
- server.csr.pem — CSR for the server certificate
- server.crt.pem — Server certificate signed by the local CA (10 years)
- server.fullchain.pem — Server cert + CA cert (concatenated)
- dhparam.pem — 4096-bit Diffie–Hellman parameters
- _tls_helper.state — Remembers the last hostname you generated for

Files in _tls_helper/certs/ and docker-wrapper/nginx-service/certs/ are git-ignored to prevent accidental commits.

Scripts
1) _tls_helper/x-tls-generate.sh
   - Creates/refreshes the local CA (if missing/expired) and a server certificate for a hostname you provide.
   - Adds SANs for:
     - DNS: <your-hostname>
     - DNS: localhost
     - IP: 127.0.0.1
   - Re-entrant: if you run it again with the same hostname, it won’t regenerate unnecessarily. If you change the 
     hostname, it cleans up the old server artifacts and issues a new cert.
   - Usage:
     - Interactive: bash _tls_helper/x-tls-generate.sh
       - It will prompt for a hostname (defaults to last used).
     - Non-interactive: bash _tls_helper/x-tls-generate.sh my.dev.host

2) _tls_helper/x-tls-distribute-to-docker.sh
   - Copies the generated TLS materials into the NGINX service’s certs directory used by docker-compose.
   - Source files (must exist):
     - _tls_helper/certs/server.crt.pem
     - _tls_helper/certs/server.key.pem
     - _tls_helper/certs/dhparam.pem
   - Destination directory:
     - docker-wrapper/nginx-service/certs/
   - Usage:
     - bash _tls_helper/x-tls-distribute-to-docker.sh

How it plugs into docker-compose and NGINX
- docker-wrapper/compose.yml mounts docker-wrapper/nginx-service/certs as /etc/nginx/external inside the NGINX container.
- docker-wrapper/nginx-service/nginx.conf references:
  - ssl_certificate     /etc/nginx/external/server.crt.pem
  - ssl_certificate_key /etc/nginx/external/server.key.pem
  - ssl_dhparam         /etc/nginx/external/dhparam.pem
- The NGINX service listens on 8443 by default and is bound to 127.0.0.1 (override port with NGINX_PORT env var).

End-to-end quick start (DEV only)
1) Generate TLS assets
   - `./_tls_helper/x-tls-generate.sh my.dev.host`
2) Copy them to NGINX certs folder
   - `./_tls_helper/x-tls-distribute-to-docker.sh`
3) Start the stack
   - `cd docker-wrapper`
   - `docker compose up -d --build`
4) Test HTTPS
   - The reverse proxy exposes https://127.0.0.1:8443 by default.
   - Because the cert is self-signed, curl and browsers will not trust it by default. For curl in DEV, add --insecure:
     - `curl --insecure -sS https://127.0.0.1:8443/healthz`
   - For API calls proxied to the app, include Authorization and Content-Type as usual:
     ```bash
     curl --insecure -sS -X POST https://127.0.0.1:8443/adx/token \
     -H "Authorization: Bearer X..." \
     -H "Content-Type: application/json" \
     -d '{"tenantId":"...","clientId":"...","clientSecret":"..."}'
     ```

Trusting the local CA (optional, still DEV only)
- If you want to avoid --insecure on your machine, you can add ca.crt.pem to your OS trust store so that the generated 
  server certificate chains to a trusted CA locally. Steps vary by OS and organization policy. Only do this on DEV 
  machines, never in production.

Security disclaimer
- The artifacts produced by _tls_helper are for development only:
  - The private keys are stored in your working copy.
  - The CA is locally generated and trusted by no one by default.
  - The server certificate is signed by that local CA and would not validate publicly.
- Do not use these certificates for anything beyond local development.
- For production, use certificates issued by a proper CA and follow your organization’s security practices.
