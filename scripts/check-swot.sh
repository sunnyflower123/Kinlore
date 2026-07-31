#!/usr/bin/env bash
# Checks whether an email domain qualifies for the student verification of the
# Shipaton Next Gen category. Devpost uses the Swot list maintained by JetBrains.
#
# This can be run WITHOUT having an address yet — knowing your institution's
# domain is enough.
#
#   ./scripts/check-swot.sh student.oulu.fi
#   ./scripts/check-swot.sh matti.meikalainen@aalto.fi

set -uo pipefail

input="${1:-}"
[ -z "$input" ] && { echo "Usage: $0 <domain or email>"; exit 1; }

# Both a bare domain and a full address are accepted.
domain="$(echo "${input##*@}" | tr '[:upper:]' '[:lower:]')"

RAW="https://raw.githubusercontent.com/JetBrains/swot/master/lib/domains"

# Swot stores domains as a reversed path: aalto.fi → fi/aalto.txt,
# edu.turku.fi → fi/turku/edu.txt. Check the most specific match first and widen
# from there, because a match on the parent domain covers its subdomains.
IFS='.' read -r -a parts <<< "$domain"
n=${#parts[@]}

for (( start = 0; start < n - 1; start++ )); do
	path=""
	for (( i = n - 1; i >= start; i-- )); do
		path="$path/${parts[$i]}"
	done
	url="${RAW}${path}.txt"
	if curl -sf -o /dev/null "$url"; then
		name="$(curl -s "$url" | head -1)"
		matched="$(IFS=.; echo "${parts[*]:$start}")"
		echo "QUALIFIES — $domain"
		echo "  matched:     $matched"
		[ -n "$name" ] && echo "  institution: $name"
		exit 0
	fi
done

echo "NOT FOUND — $domain"
echo
echo "This does not yet mean the address will be rejected: Devpost can approve"
echo "manually, and a missing institution can be added to Swot with a pull"
echo "request. Both take time, so find out at the beginning of August."
exit 1
