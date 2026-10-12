#!/usr/bin/env bash
set -euo pipefail
[[ $EUID == 0 ]] || exit 1
PUBLIC=$1 UI_USER=$2 EDGE=$3 NN=$4 SNN=$5; shift 5
[[ "$PUBLIC" =~ ^[a-zA-Z0-9.-]+$ && "$UI_USER" =~ ^[a-zA-Z0-9_-]+$ ]] || exit 1
export DEBIAN_FRONTEND=noninteractive
if ! dpkg-query -W -f='${Status}' nginx 2>/dev/null | grep -q 'install ok installed'; then
 apt-get update -qq; apt-get install -y -qq nginx openssl
fi
install -d -m 0700 /etc/nginx/hw2
if [[ ! -f /etc/nginx/hw2/.managed && -f /etc/nginx/conf.d/hw2.conf ]]; then
 echo 'Unmanaged hw2.conf exists.' >&2; exit 1
fi
# Remove only the vendor default symlink, retaining its target for recovery.
[[ ! -L /etc/nginx/sites-enabled/default ]] || unlink /etc/nginx/sites-enabled/default
python3 "$(dirname -- "$0")/publish.py" "$PUBLIC" "$UI_USER" "$EDGE" "$NN" "$SNN" "$@"
nginx -t
systemctl enable nginx >/dev/null
systemctl reload-or-restart nginx
echo 'PUBLISH_OK: HTTPS ports 8443-8446,8451-8453,8461-8463; credentials in /etc/nginx/hw2/access.json'
