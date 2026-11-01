#!/usr/bin/env python3
"""Read-only public discovery probe. Never handles or prints OAuth secrets."""
import json
import urllib.request
import urllib.error
from datetime import datetime, timezone
from pathlib import Path

endpoints = {
    'resource': 'https://mcp.desktopcommander.app/.well-known/oauth-protected-resource',
    'authorization': 'https://mcp.desktopcommander.app/.well-known/oauth-authorization-server',
}
result = {'checked_at': datetime.now(timezone.utc).isoformat(), 'authenticated': False}
for name, url in endpoints.items():
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={'Accept': 'application/json'}), timeout=20) as r:
            result[name] = {'status': r.status, 'metadata': json.load(r)}
    except urllib.error.HTTPError as e:
        result[name] = {'status': e.code, 'error': 'Discovery denied; no authentication attempted.'}
    except Exception as e:
        result[name] = {'error': type(e).__name__}
Path('Verification').mkdir(exist_ok=True)
Path('Verification/rdc-public-probe.json').write_text(json.dumps(result, indent=2))
print(json.dumps(result, indent=2))
