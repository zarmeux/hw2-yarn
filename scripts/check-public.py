#!/usr/bin/env python3
"""Run outside the cluster: verify TCP, TLS, authenticated UI and denied anonymous access."""
import argparse
import base64
import concurrent.futures
import datetime
import json
import netrc
import re
import socket
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request

PORTS = (8443, 8444, 8445, 8446, 8451, 8452, 8453, 8461, 8462, 8463)

class ClusterRedirect(urllib.request.HTTPRedirectHandler):
    def __init__(self, host):
        self.host = host
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        target = urllib.parse.urlsplit(newurl)
        if target.scheme != 'https' or target.hostname != self.host or target.port not in PORTS:
            raise urllib.error.URLError('Redirect outside the published HTTPS cluster was refused')
        return super().redirect_request(req, fp, code, msg, headers, newurl)

def check(host, port, timeout, context, authorization):
    result = {'port': port, 'tcp': 'UNREACHABLE', 'tls': 'NOT_CHECKED', 'ok': False}
    try:
        with socket.create_connection((host, port), timeout=timeout) as raw:
            result['tcp'] = 'OPEN'
            with context.wrap_socket(raw, server_hostname=host) as secure:
                result['tls'] = 'VERIFIED'
                result['tls_version'] = secure.version()
        opener = urllib.request.build_opener(ClusterRedirect(host), urllib.request.HTTPSHandler(context=context), urllib.request.ProxyHandler({}))
        req = urllib.request.Request(f'https://{host}:{port}/', headers={'Authorization': authorization})
        with opener.open(req, timeout=timeout) as response:
            body = response.read()
            result['authenticated_status'] = response.status
            result['final_url'] = response.url
            result['bytes'] = len(body)
            title = re.search(br'<title>(.*?)</title>', body, re.I | re.S)
            result['title'] = title.group(1).decode(errors='replace').strip() if title else None
        try:
            with opener.open(f'https://{host}:{port}/', timeout=timeout) as response:
                result['anonymous_status'] = response.status
        except urllib.error.HTTPError as error:
            result['anonymous_status'] = error.code
        result['ok'] = result['authenticated_status'] == 200 and result['bytes'] > 0 and result['anonymous_status'] == 401
    except (OSError, urllib.error.URLError) as error:
        if result['tcp'] == 'OPEN' and result['tls'] != 'VERIFIED':
            result['tls'] = 'FAILED'
        result['reason'] = str(error)
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='111.88.130.214')
    parser.add_argument('--timeout', type=float, default=8)
    parser.add_argument('--ca-cert', required=True, help='Certificate copied over verified SSH')
    parser.add_argument('--netrc-file', required=True, help='Private credentials file; never commit it')
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    auth = netrc.netrc(args.netrc_file).authenticators(args.host)
    if not auth:
        parser.error('No credentials for --host in --netrc-file')
    login, _, password = auth
    authorization = 'Basic ' + base64.b64encode(f'{login}:{password}'.encode()).decode()
    context = ssl.create_default_context(cafile=args.ca_cert)
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(PORTS)) as pool:
        results = list(pool.map(lambda port: check(args.host, port, args.timeout, context, authorization), PORTS))
    successful = all(result['ok'] for result in results)
    print(json.dumps({'checked_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'host': args.host, 'all_ok': successful, 'checks': results}, indent=2))
    return 0 if successful else 1

if __name__ == '__main__':
    sys.exit(main())
