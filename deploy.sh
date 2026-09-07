#!/usr/bin/env bash
# Tek komutluk yayina alma: rename -> push -> Pages -> IndexNow ping -> dogrulama.
# Token'i ~/.ghtoken dosyasindan okur; ekrana veya loga asla basmaz.
set -euo pipefail

USER=mrtlawless
NEW=mrtlawless.github.io
OLD=backlinkindex
ROOT="$(cd "$(dirname "$0")" && pwd)"

[ -f ~/.ghtoken ] || { echo "HATA: ~/.ghtoken yok."; exit 1; }
GH_TOKEN="$(tr -d ' \t\r\n' < ~/.ghtoken)"
export GH_TOKEN
api() { curl -sS -H "Authorization: Bearer $GH_TOKEN" \
             -H "Accept: application/vnd.github+json" "$@"; }

echo "==> token dogrulaniyor"
who=$(api https://api.github.com/user | grep -o '"login": *"[^"]*"' | cut -d'"' -f4)
[ "$who" = "$USER" ] || { echo "HATA: token '$who' hesabina ait, '$USER' bekleniyordu."; exit 1; }
echo "    ok: $who"

echo "==> repo adi kontrol ediliyor"
if api -o /dev/null -w '%{http_code}' "https://api.github.com/repos/$USER/$NEW" | grep -q 200; then
  echo "    zaten $NEW"
else
  echo "    $OLD -> $NEW yeniden adlandiriliyor"
  api -X PATCH "https://api.github.com/repos/$USER/$OLD" -d "{\"name\":\"$NEW\"}" >/dev/null
  sleep 3
fi

echo "==> push"
cd "$ROOT/site"
git remote remove origin 2>/dev/null || true
git remote add origin "https://x-access-token:${GH_TOKEN}@github.com/$USER/$NEW.git"
git push -q -u origin main --force-with-lease 2>&1 | grep -v "^remote:" || true
git remote set-url origin "https://github.com/$USER/$NEW.git"   # token'i .git/config'te birakma
echo "    ok"

echo "==> GitHub Pages aciliyor"
code=$(api -o /dev/null -w '%{http_code}' -X POST "https://api.github.com/repos/$USER/$NEW/pages" \
        -d '{"source":{"branch":"main","path":"/"}}')
case "$code" in
  201) echo "    olusturuldu" ;;
  409) echo "    zaten acik"  ;;
  *)   echo "    beklenmeyen yanit: $code" ;;
esac

echo "==> yayina cikmasi bekleniyor (en fazla 5 dk)"
for i in $(seq 1 30); do
  s=$(curl -s -o /dev/null -w '%{http_code}' -L "https://$NEW/")
  [ "$s" = "200" ] && { echo "    canli: https://$NEW/"; break; }
  sleep 10
done
[ "${s:-}" = "200" ] || echo "    henuz 200 degil (son kod: ${s:-yok}) - Pages birkac dk gecikebilir"

echo "==> IndexNow ping"
cd "$ROOT" && python3 indexer.py ping || true

echo "==> dogrulama"
for u in "/" "/g/1/" "/g/4/" "/sitemap.xml" "/feed.xml" "/robots.txt"; do
  printf "    %-14s %s\n" "$u" "$(curl -s -o /dev/null -w '%{http_code}' -L "https://$NEW$u")"
done

echo
echo "BITTI. Kalan tek manuel is: Google Search Console dogrulamasi."
