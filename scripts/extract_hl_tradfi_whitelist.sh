chmod +x scripts/extract_hl_tradfi_whitelist.sh

# tutti i simboli TradFi/HIP-3 candidati
./scripts/extract_hl_tradfi_whitelist.sh

# solo equity
./scripts/extract_hl_tradfi_whitelist.sh /freqtrade/user_data/config_discovery.json equity

# solo indici
./scripts/extract_hl_tradfi_whitelist.sh /freqtrade/user_data/config_discovery.json index

# solo commodities
./scripts/extract_hl_tradfi_whitelist.sh /freqtrade/user_data/config_discovery.json commodity