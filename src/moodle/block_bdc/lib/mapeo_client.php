<?php
/**
 * @file
 * Mapeo API Client.
 *
 * @package   block_bdc
 * @copyright 2026 LLM Wiki Assistant
 * License:   http://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */


defined('MOODLE_INTERNAL') || die();

require_once($CFG->libdir . '/filelib.php');

/**
 * Cliente HTTP para comunicarse con mapeo-api (Fase 2).
 */
class block_bdc_mapeo_client {
    
    /**
     * Endpoint base del microservicio
     */
    private $baseurl;
    
    /**
     * Token de autorización
     */
    private $token;

    /**
     * Constructor del cliente.
     */
    public function __construct() {
        $this->baseurl = getenv('MAPEO_API_URL');
        if (empty($this->baseurl)) {
            throw new moodle_exception('error_missing_config', 'block_bdc', '', 'MAPEO_API_URL no está configurado en el entorno.');
        }
        $this->token = getenv('MAPEO_API_TOKEN');
        if (empty($this->token) || $this->token === 'changeme') {
            throw new moodle_exception('error_missing_token', 'block_bdc', '', 'MAPEO_API_TOKEN no está configurado en el entorno.');
        }
    }

    /**
     * Obtiene el mapeo para un usuario y curso dados.
     *
     * @param int $userid
     * @param int $courseid
     * @return array|null Null si no existe o hay error.
     */
    public function get_mapeo($userid, $courseid) {
        $curl = new \curl(['ignoresecurity' => true]);
        $curl->setHeader('Authorization: Bearer ' . $this->token);
        
        $url = $this->baseurl . '/mapeos?moodle_user_id=' . (int)$userid . '&moodle_course_id=' . (int)$courseid;
        $response = $curl->get($url);
        
        $status = $curl->get_info()['http_code'];
        if ($status === 200) {
            $data = json_decode($response, true);
            if (is_array($data) && count($data) > 0) {
                return $data[0]; // Retorna el primer y único mapeo
            }
        }
        
        return null;
    }

    /**
     * Llama al microservicio central para registrar un nuevo alumno-curso y aprovisionar en GitHub.
     *
     * @param int $userid ID de usuario en Moodle.
     * @param int $courseid ID del curso en Moodle.
     * @param string $github_url URL base de Github (ahora manejada por la API central, enviar vacío).
     * @param string $matrix_room ID de sala en Matrix generado por Synapse Admin API.
     * @param string $username Username del usuario en Moodle para generar el repositorio [asignatura]-[usuario].
     * @param string $course_shortname Nombre corto del curso para usar como base del repositorio template.
     * @param bool $is_teacher Indica si el usuario es un profesor.
     * @param string $course_fullname Nombre completo del curso.
     * @param string $git_username Usuario de GitHub (opcional) para añadirlo como colaborador: el alumno en su repositorio y el profesor en el repositorio oficial.
     * @return array Resultado de la API devolviendo el mapeo generado.
     * @throws moodle_exception Si hay un error, como un 409 Conflict.
     */
    public function create_mapeo($userid, $courseid, $github_url, $matrix_room, $username = "", $course_shortname = "", $is_teacher = false, $course_fullname = "", $git_username = "") {
        $curl = new \curl(['ignoresecurity' => true]);
        $curl->setHeader('Authorization: Bearer ' . $this->token);
        $curl->setHeader('Content-Type: application/json');
        
        $payload = json_encode([
            'moodle_user_id' => (int)$userid,
            'moodle_course_id' => (int)$courseid,
            'github_repo_url' => $github_url,
            'matrix_room_id' => $matrix_room,
            'moodle_username' => $username,
            'moodle_course_shortname' => $course_shortname,
            'moodle_course_fullname' => $course_fullname ?: $course_shortname,
            'is_teacher' => $is_teacher,
            'git_username' => $git_username !== '' ? $git_username : null
        ]);
        
        $url = $this->baseurl . '/mapeos';
        $response = $curl->post($url, $payload);
        
        $status = $curl->get_info()['http_code'];
        
        if ($status === 409) {
            throw new \moodle_exception('Conflict: Ya existe un mapeo para este usuario y curso (HTTP 409).', 'block_bdc');
        } else if ($status !== 201) {
            throw new \moodle_exception('Error creando mapeo (HTTP ' . $status . '): ' . $response, 'block_bdc');
        }
        
        return json_decode($response, true);
    }

    /**
     * Solicita a la API un login token temporal de Matrix (m.login.token) para auto-login del usuario.
     *
     * @param string $username Nombre de usuario en Moodle (ej. 'student1')
     * @param string $domain Dominio de Matrix (opcional)
     * @return string|null El token de login temporal o null si falla.
     */
    public function get_matrix_login_token($username, $domain = '') {
        $curl = new \curl(['ignoresecurity' => true]);
        $curl->setHeader('Authorization: Bearer ' . $this->token);
        $curl->setHeader('Content-Type: application/json');

        $payload = json_encode([
            'username' => $username,
            'domain' => $domain
        ]);

        $url = $this->baseurl . '/v1/auth/matrix-token';
        $response = $curl->post($url, $payload);
        $status = $curl->get_info()['http_code'];

        if ($status === 200) {
            $data = json_decode($response, true);
            if (!empty($data['login_token'])) {
                return $data['login_token'];
            }
        } else {
            error_log("BLOCK_BDC: Error obteniendo matrix login token (HTTP $status): $response");
        }
        return null;
    }

    /**
     * Fija o cambia el usuario Git del alumno o profesor. La API revoca el anterior y da acceso al nuevo
     * en todos sus repositorios (el propio del alumno o el repositorio oficial de la asignatura del profesor).
     *
     * @param int $userid ID de usuario en Moodle.
     * @param string $git_username Nuevo usuario de GitHub.
     * @return array Respuesta de la API: git_username, repos_updated, errors.
     * @throws moodle_exception Si la API rechaza la petición o no está disponible.
     */
    public function set_git_username($userid, $git_username) {
        $curl = new \curl(['ignoresecurity' => true]);
        $curl->setHeader('Authorization: Bearer ' . $this->token);
        $curl->setHeader('Content-Type: application/json');

        $url = $this->baseurl . '/v1/usuarios/' . (int)$userid . '/git-username';
        $response = $curl->post($url, json_encode(['git_username' => $git_username]), ['CURLOPT_CUSTOMREQUEST' => 'PUT']);
        return $this->parse_git_username_response($curl, $response);
    }

    /**
     * Elimina el usuario Git del alumno o profesor y revoca su acceso a sus repositorios.
     *
     * @param int $userid ID de usuario en Moodle.
     * @return array Respuesta de la API: git_username, repos_updated, errors.
     * @throws moodle_exception Si la API rechaza la petición o no está disponible.
     */
    public function delete_git_username($userid) {
        $curl = new \curl(['ignoresecurity' => true]);
        $curl->setHeader('Authorization: Bearer ' . $this->token);
        $curl->setHeader('Content-Type: application/json');

        $url = $this->baseurl . '/v1/usuarios/' . (int)$userid . '/git-username';
        $response = $curl->post($url, '', ['CURLOPT_CUSTOMREQUEST' => 'DELETE']);
        return $this->parse_git_username_response($curl, $response);
    }

    /**
     * Interpreta la respuesta de los endpoints de git-username.
     *
     * @param \curl $curl Cliente usado en la petición.
     * @param string|bool $response Cuerpo de la respuesta.
     * @return array
     * @throws moodle_exception
     */
    private function parse_git_username_response($curl, $response) {
        $status = (int)($curl->get_info()['http_code'] ?? 0);
        if ($status === 200) {
            $data = json_decode($response, true);
            return is_array($data) ? $data : [];
        }
        if ($status === 404) {
            throw new \moodle_exception('error_github_not_found', 'block_bdc');
        }
        if ($status === 422) {
            throw new \moodle_exception('error_github_invalid', 'block_bdc');
        }
        error_log("BLOCK_BDC: Error sincronizando git_username (HTTP $status): $response");
        throw new \moodle_exception('error_github_sync', 'block_bdc', '', $status);
    }
}
