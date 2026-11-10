<?php
/**
 * Script de inicialización para ajustar automáticamente $CFG->wwwroot
 * a partir de la variable de entorno MOODLE_URL (Issues #2 y #4).
 */
$f = '/bitnami/moodle/config.php';
if (!file_exists($f)) {
    exit(0);
}

$c = file_get_contents($f);
if (strpos($c, 'moodle_env_url') !== false && strpos($c, 'sslproxy') !== false) {
    exit(0);
}

// Buscar el bloque que define $CFG->wwwroot generado por Bitnami o versión previa
$pattern = '/(\$moodle_env_url\s*=.*?else\s*\{[\s\r\n]*\$CFG->wwwroot\s*=.*?;[\s\r\n]*\}|(if\s*\(isset\(\$_SERVER\[.HTTPS.\]\).*?\$CFG->wwwroot\s*=.*?;[\s\r\n]*\}[\s\r\n]*else[\s\r\n]*\{[\s\r\n]*\$CFG->wwwroot\s*=.*?;[\s\r\n]*\}))/s';
$replacement = <<<'PHP'
$moodle_env_url = getenv('MOODLE_URL');
if (!empty($moodle_env_url)) {
  $CFG->wwwroot   = rtrim($moodle_env_url, '/');
  if (stripos($moodle_env_url, 'https://') === 0) {
    $CFG->sslproxy = true;
    $CFG->reverseproxy = true;
  }
} else {
  $is_https = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on') ||
              (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https');
  $host = getenv('MOODLE_HOST') ?: (!empty($_SERVER['HTTP_X_FORWARDED_HOST']) ? $_SERVER['HTTP_X_FORWARDED_HOST'] : (!empty($_SERVER['HTTP_HOST']) ? $_SERVER['HTTP_HOST'] : '127.0.0.1:8080'));
  if ($is_https) {
    $CFG->sslproxy = true;
    $CFG->reverseproxy = true;
    $CFG->wwwroot = 'https://' . $host;
  } else {
    $CFG->wwwroot = 'http://' . $host;
  }
}
PHP;

$new_c = preg_replace($pattern, $replacement, $c, 1);
if ($new_c && $new_c !== $c) {
    file_put_contents($f, $new_c);
    echo "Moodle config.php actualizado automáticamente para usar MOODLE_URL dinámico con soporte HTTPS/SSL proxy.\n";
}
