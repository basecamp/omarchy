echo "Removing UseDNS=no from network files to fix DNS issue"

for file in /etc/systemd/network/*.network; do
  [[ -f "$file" ]] || continue
  sudo sed -i '/^UseDNS=no/d' "$file"
done