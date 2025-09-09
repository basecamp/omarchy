echo "Add IPv6 DNS support to systemd-resolved"

if [ -f /etc/systemd/resolved.conf ]; then
  needs_ipv6_update=false
  
  if grep -q "DNS=1\.1\.1\.1#cloudflare-dns\.com" /etc/systemd/resolved.conf && ! grep -q "2606:4700:4700::1111" /etc/systemd/resolved.conf; then
    needs_ipv6_update=true
  fi
  
  if ! grep -q "DNSStubListenerExtra=\[::1\]:53" /etc/systemd/resolved.conf && ! grep -q "DNSStubListenerExtra=\[::1\]:53" /etc/systemd/resolved.conf.d/* 2>/dev/null; then
    needs_ipv6_update=true
  fi
  
  if [ "$needs_ipv6_update" = true ]; then
    if ! grep -q "DNSStubListenerExtra=\[::1\]:53" /etc/systemd/resolved.conf && ! grep -q "DNSStubListenerExtra=\[::1\]:53" /etc/systemd/resolved.conf.d/* 2>/dev/null; then
      sudo mkdir -p /etc/systemd/resolved.conf.d
      echo -e '[Resolve]\nDNSStubListenerExtra=[::1]:53' | sudo tee /etc/systemd/resolved.conf.d/30-ipv6-stub.conf >/dev/null
    fi
    
    if grep -q "DNS=1\.1\.1\.1#cloudflare-dns\.com" /etc/systemd/resolved.conf; then
      sudo sed -i 's|DNS=1\.1\.1\.1#cloudflare-dns\.com 1\.0\.0\.1#cloudflare-dns\.com|DNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com 2606:4700:4700::1111#cloudflare-dns.com 2606:4700:4700::1001#cloudflare-dns.com|' /etc/systemd/resolved.conf
    fi
    
    if grep -q "FallbackDNS=9\.9\.9\.9 149\.112\.112\.112$" /etc/systemd/resolved.conf; then
      sudo sed -i 's|FallbackDNS=9\.9\.9\.9 149\.112\.112\.112$|FallbackDNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net 2620:fe::9#dns.quad9.net|' /etc/systemd/resolved.conf
    fi
    
    sudo systemctl restart systemd-resolved
  fi
fi