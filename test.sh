m_pass="maubotpass_changeme"
docker run --rm alpine sh -c "
  apk add --no-cache python3 py3-bcrypt >/dev/null 2>&1 || true
  m_hash=\$(python3 -c \"import bcrypt; print(bcrypt.hashpw('${m_pass}'.encode('utf-8'), bcrypt.gensalt()).decode('utf-8'))\" 2>/dev/null)
  echo \$m_hash
"
