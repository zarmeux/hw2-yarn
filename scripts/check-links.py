#!/usr/bin/env python3
"""Check the deployed NameNode link map against live DataNodes and open each published UI."""
import json
import re
import urllib.parse
import urllib.request

BASE = 'http://127.0.0.1:19870'
def read(url):
    with urllib.request.urlopen(url, timeout=15) as response:
        if response.status != 200:
            raise RuntimeError(f'HTTP {response.status}: {url}')
        return response.read().decode()
source = read(BASE + '/dfshealth.js')
match = re.search(r'n\.dnWebAddress = (\{[^\n]*\})\[n\.name\.split', source)
if not match:
    raise SystemExit('LINK_CHECK_FAILED: published DataNode map missing from live UI JavaScript')
links = json.loads(match.group(1))
info = json.loads(read(BASE + '/jmx?qry=Hadoop:service=NameNode,name=NameNodeInfo'))['beans'][0]
nodes = json.loads(info['LiveNodes'])
if len(nodes) != 3:
    raise SystemExit(f'LINK_CHECK_FAILED: expected three live DataNodes, found {len(nodes)}')
seen = set()
for node in sorted(nodes):
    host = node.rsplit(':', 1)[0]
    url = links.get(host)
    target = urllib.parse.urlsplit(url or '')
    if target.scheme != 'http' or target.hostname != '127.0.0.1' or target.port not in (19864, 19865, 19866):
        raise SystemExit(f'LINK_CHECK_FAILED: invalid published address for {node}: {url}')
    html = read(url + '/')
    if 'Hadoop Administration' not in html and 'DataNode' not in html:
        raise SystemExit(f'LINK_CHECK_FAILED: not a DataNode UI: {url}')
    seen.add(target.port)
    print(f'DATANODE_LINK_OK {node} -> {url} HTTP=200')
if len(seen) != 3:
    raise SystemExit('LINK_CHECK_FAILED: DataNodes must map to three distinct frontends')
print('LINKS_OK')
