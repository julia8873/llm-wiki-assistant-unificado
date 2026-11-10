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
$replacement = "\$moodle_env_url = getenv('MOODLE_URL');\nif (!empty(\$moodle_env_url)) {\n  \$CFG->wwwroot   = rtrim(\$moodle_env_url, '/');\n  if (stripos(\$moodle_env_url, 'https://') === 0) {\n    \$CFG->sslproxy = true;\n    \$CFG->reverseproxy = true;\n  }\n} else if (isset(\$_SERVER['HTTPS']) && \$_SERVER['HTTPS'] == 'on') {\n  \$CFG->wwwroot   = 'https://' . (getenv('MOODLE_HOST') ?: \$_SERVER['HTTP_HOST']);\n} else {\n  \$CFG->wwwroot   = 'http://' . (getenv('MOODLE_HOST') ?: \$_SERVER['HTTP_HOST']);\n}";

$new_c = preg_replace($pattern, $replacement, $c, 1);
if ($new_c && $new_c !== $c) {
    file_put_contents($f, $new_c);
    echo "Moodle config.php actualizado automáticamente para usar MOODLE_URL dinámico con soporte HTTPS/SSL proxy.\n";
}
