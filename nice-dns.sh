#!/bin/bash

# Ga na of de map voor de DNS-inhoud bestaat. Indien niet, maak ze aan
if [ "${#}" -eq '0' ]; then
  echo "At least one argument expected, exiting..."
  exit 0
fi

sudo chown vagrant /etc
if ! rpm -q dnsmasq > /dev/null 2>&1; then
  # Install dnsmasq
  sudo dnf -y install dnsmasq
  sudo systemctl restart dnsmasq
fi

sudo setenforce 0

# Pas de configuratie van de DNS server aan
# Change the conf-dir option in dnsmasq.conf to /var/dns/
sudo sed -i 's/conf-dir=\/etc\/dnsmasq.d/conf-dir=\/var\/dns/' /etc/dnsmasq.conf
sudo sed -i 's/conf-dir=\/var\/dns,.rpmnew,.rpmsave,.rpmorig/conf-dir=\/var\/dns/' /etc/dnsmasq.conf
# Check if the /var/dns directory exists
if ! -d "/var/dns" > /dev/null 2>&1; then
  # Create the /var/dns directory
  sudo mkdir -p /var/dns
fi
# Restart the dnsmasq service
sudo systemctl restart dnsmasq

# maak server actief op intnet en localhost maar niet NAT(=eth0) 
if ! grep -q "interface=eth1" /etc/dnsmasq.conf ; then
  sed -i '$a\interface=eth1' /etc/dnsmasq.conf
  sed -i '/interface=eth0/d' /etc/dnsmasq.conf
fi
# enable en start dnsmasq
sudo systemctl enable dnsmasq
sudo systemctl start dnsmasq
#poort accesible via alle IP-adressen
firewall-cmd --permanent --add-port=53/tcp > /dev/null 2>&1

sudo dnf -y install epel-release > /dev/null 2>&1
sudo dnf -y update > /dev/null 2>&1
sudo dnf -y install cowsay > /dev/null 2>&1

# Look up the first name in the local authoritative DNS server of DNSmasq
name=$(nslookup "$1" localhost)

# Format the output with a newline, today's date, and cowsay
today=$(date +%Y-%m-%d)
echo -e "\nVandaag is het $today.\n"
echo "$name" | cowsay