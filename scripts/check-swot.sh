#!/usr/bin/env bash
# Tarkistaa kelpaako sähköpostidomain Shipatonin Next Gen -sarjan
# opiskelijaverifiointiin. Devpost käyttää JetBrainsin ylläpitämää Swot-listaa.
#
# Tämän voi ajaa ILMAN että sinulla on vielä osoitetta — riittää että tiedät
# oppilaitoksesi domainin.
#
#   ./scripts/check-swot.sh student.oulu.fi
#   ./scripts/check-swot.sh matti.meikalainen@aalto.fi

set -uo pipefail

input="${1:-}"
[ -z "$input" ] && { echo "Käyttö: $0 <domain tai sähköposti>"; exit 1; }

# Hyväksytään sekä pelkkä domain että kokonainen osoite.
domain="$(echo "${input##*@}" | tr '[:upper:]' '[:lower:]')"

RAW="https://raw.githubusercontent.com/JetBrains/swot/master/lib/domains"

# Swot tallentaa domainit käänteisenä polkuna: aalto.fi → fi/aalto.txt,
# edu.turku.fi → fi/turku/edu.txt. Tarkistetaan tarkin osuma ensin ja
# kavennetaan siitä ylöspäin, koska osuma emodomainiin kattaa alidomainit.
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
		echo "KELPAA — $domain"
		echo "  osuma:      $matched"
		[ -n "$name" ] && echo "  oppilaitos: $name"
		exit 0
	fi
done

echo "EI LÖYTYNYT — $domain"
echo
echo "Tämä ei vielä tarkoita ettei osoite kelpaisi: Devpost voi hyväksyä"
echo "manuaalisesti, ja Swotiin voi lähettää pull requestin puuttuvasta"
echo "oppilaitoksesta. Molemmat vievät aikaa, joten selvitä se elokuun alussa."
exit 1
