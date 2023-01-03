#!/bin/bash

# Ga na of de map voor de DNS-inhoud bestaat. Indien niet, maak ze aan
if [ "${#}" -eq '0' ]; then
  echo "At least one argument expected, exiting..."
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
sed -i '$a\interface=eth1' /etc/dnsmasq.conf
sed -i '/interface=eth0/d' /etc/dnsmasq.conf
# enable en start dnsmasq
sudo systemctl enable dnsmasq
sudo systemctl start dnsmasq
#poort accesible via alle IP-adressen
firewall-cmd --permanent --add-port=53/tcp > /dev/null 2>&1
