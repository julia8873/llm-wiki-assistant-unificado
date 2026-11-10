<?php
/**
 * Event observers for block_bdc.
 *
 * @package   block_bdc
 * @copyright 2026 LLM Wiki Assistant
 * License:   http://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */

/// @cond DOXYGEN_IGNORE
namespace block_bdc;
/// @endcond

defined('MOODLE_INTERNAL') || die();

require_once(__DIR__ . '/../lib/mapeo_client.php');

class observer {

    /**
     * Triggered when a course is created.
     * Calls the mapeo-api to provision the official repository
     * and automatically registers the creator teacher in mapeo-api
     * so the course immediately appears in Metrics API / Dashboard.
     *
     * @param \core\event\course_created $event
     */
    public static function course_created(\core\event\course_created $event) {
        global $DB;
        
        $course = $event->get_record_snapshot('course', $event->objectid);
        if (!$course) {
            $course = $DB->get_record('course', array('id' => $event->objectid));
        }
        
        if ($course && !empty($course->shortname)) {
            $baseurl = getenv('MAPEO_API_URL');
            if (empty($baseurl)) {
                debugging('MAPEO_API_URL no está configurado en el entorno.', DEBUG_DEVELOPER);
                return;
            }
            $token = getenv('MAPEO_API_TOKEN');
            if (empty($token) || $token === 'changeme') {
                debugging('MAPEO_API_TOKEN no está configurado en el entorno.', DEBUG_DEVELOPER);
                return;
            }
            
            $curl = new \curl(['ignoresecurity' => true]);
            $curl->setHeader('Authorization: Bearer ' . $token);
            $curl->setHeader('Content-Type: application/json');
            
            $payload = json_encode([
                'moodle_course_shortname' => $course->shortname
            ]);
            
            $url = $baseurl . '/cursos';
            
            // Llama a la API de forma síncrona para crear la plantilla oficial en el proveedor Git
            $response = $curl->post($url, $payload);
            $status = $curl->get_info()['http_code'];
            
            if ($status === 201 || $status === 200) {
                \core\notification::success('Repositorio oficial de la asignatura (' . $course->shortname . '-Oficial) creado correctamente en el proveedor Git.');
            } else {
                \core\notification::error('Error al crear el repositorio oficial en el proveedor Git. Por favor contacte con soporte técnico. (HTTP ' . $status . ')');
                debugging('Error al aprovisionar la plantilla oficial en mapeo-api. HTTP ' . $status . ': ' . $response, DEBUG_DEVELOPER);
            }

            // Registrar al usuario creador / profesor para que el curso cargue automáticamente en Metrics
            if (!empty($event->userid) && (int)$event->userid > 1) {
                $creator = $DB->get_record('user', array('id' => $event->userid));
                if ($creator) {
                    self::ensure_teacher_mapeo($course, $creator);
                }
            }
        }
    }

    /**
     * Triggered when a user is enrolled in a course.
     * If the user has teacher capabilities, automatically registers them in mapeo-api.
     *
     * @param \core\event\user_enrolment_created $event
     */
    public static function user_enrolment_created(\core\event\user_enrolment_created $event) {
        global $DB;

        $userid = (int)$event->relateduserid;
        $courseid = (int)$event->courseid;
        if ($userid <= 1 || $courseid <= 1) {
            return;
        }

        $context = \context_course::instance($courseid, IGNORE_MISSING);
        if (!$context) {
            return;
        }

        $is_teacher = has_capability('moodle/course:update', $context, $userid) ||
                      has_capability('moodle/course:viewhiddenactivities', $context, $userid) ||
                      has_capability('moodle/grade:edit', $context, $userid);

        if ($is_teacher) {
            $user = $DB->get_record('user', array('id' => $userid));
            $course = $DB->get_record('course', array('id' => $courseid));
            if ($user && $course) {
                self::ensure_teacher_mapeo($course, $user);
            }
        }
    }

    /**
     * Triggered when a role is assigned in a context.
     * If assigned to a teacher in a course context, automatically registers them in mapeo-api.
     *
     * @param \core\event\role_assigned $event
     */
    public static function role_assigned(\core\event\role_assigned $event) {
        global $DB;

        $context = \context::instance_by_id($event->contextid, IGNORE_MISSING);
        if (!$context || $context->contextlevel != CONTEXT_COURSE) {
            return;
        }

        $courseid = (int)$context->instanceid;
        $userid = (int)$event->relateduserid;
        if ($userid <= 1 || $courseid <= 1) {
            return;
        }

        $is_teacher = has_capability('moodle/course:update', $context, $userid) ||
                      has_capability('moodle/course:viewhiddenactivities', $context, $userid) ||
                      has_capability('moodle/grade:edit', $context, $userid);

        if ($is_teacher) {
            $user = $DB->get_record('user', array('id' => $userid));
            $course = $DB->get_record('course', array('id' => $courseid));
            if ($user && $course) {
                self::ensure_teacher_mapeo($course, $user);
            }
        }
    }

    /**
     * Helper to ensure a teacher mapping exists in mapeo-api for the given course and user.
     *
     * @param \stdClass $course Objeto del curso de Moodle.
     * @param \stdClass $user Objeto del usuario (profesor) de Moodle.
     */
    public static function ensure_teacher_mapeo($course, $user) {
        try {
            $client = new \block_bdc_mapeo_client();
            $existing = $client->get_mapeo($user->id, $course->id);
            if (!$existing) {
                $client->create_mapeo(
                    $user->id,
                    $course->id,
                    '', // github_repo_url (mapeo-api asocia automáticamente el repositorio oficial para profesores)
                    '', // matrix_room_id
                    $user->username,
                    $course->shortname,
                    true, // is_teacher = true
                    $course->fullname
                );
            }
        } catch (\Exception $e) {
            debugging('Error asegurando mapeo de profesor en mapeo-api: ' . $e->getMessage(), DEBUG_DEVELOPER);
        }
    }
}
