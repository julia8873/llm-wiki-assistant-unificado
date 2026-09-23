#!/bin/bash
cat << 'IN' > test_config.yaml
database: sqlite:/data/maubot.db
crypto_db_pickle_key: "${MAUBOT_CRYPTO_PICKLE_KEY}"

admins:
    admin: "${MAUBOT_ADMIN_PASSWORD}"
IN

m_hash="my_hash_value"
m_key="my_key_value"

sed -i "s|^[[:space:]]*admin: .*|    admin: $m_hash|" test_config.yaml
sed -i "s/^crypto_db_pickle_key:.*/crypto_db_pickle_key: $m_key/" test_config.yaml

cat test_config.yaml
