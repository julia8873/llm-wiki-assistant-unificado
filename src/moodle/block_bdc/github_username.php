<?php
/**
 * Página para que el alumno indique, cambie o elimine su usuario de GitHub.
 *
 * El usuario se guarda como preferencia de Moodle (disponible antes de crear el repositorio)
 * y se sincroniza con mapeo-api, que añade/revoca el acceso en los repositorios del alumno.
 *
 * @package   block_bdc
 * @copyright 2026 LLM Wiki Assistant
 * License:   http://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */

if (file_exists(__DIR__ . '/../../config.php')) {
    require_once(__DIR__ . '/../../config.php');
} else {
    require_once('/opt/bitnami/moodle/config.php');
}
require_once($CFG->dirroot . '/blocks/bdc/lib/mapeo_client.php');
require_once($CFG->dirroot . '/blocks/bdc/classes/form/github_username_form.php');

$courseid = required_param('courseid', PARAM_INT);
$action = optional_param('action', '', PARAM_ALPHA);
$confirm = optional_param('confirm', 0, PARAM_BOOL);

$course = $DB->get_record('course', ['id' => $courseid], '*', MUST_EXIST);
require_login($course);
if (isguestuser()) {
    redirect(new moodle_url('/login/index.php'));
}
$context = context_course::instance($course->id);

$pageurl = new moodle_url('/blocks/bdc/github_username.php', ['courseid' => $courseid]);
$returnurl = ($courseid == SITEID) ? new moodle_url('/') : new moodle_url('/course/view.php', ['id' => $courseid]);

$PAGE->set_url($pageurl);
$PAGE->set_context($context);
$PAGE->set_pagelayout('standard');
$PAGE->set_title(get_string('github_title', 'block_bdc'));
$PAGE->set_heading($course->fullname);

// Nombre de la preferencia (el mismo que usan view.php y block_bdc.php).
$pref = 'block_bdc_github_username';
$current = (string)get_user_preferences($pref, '');

// Eliminar (con confirmación).
if ($action === 'delete') {
    if (!$confirm) {
        echo $OUTPUT->header();
        echo $OUTPUT->heading(get_string('github_title', 'block_bdc'));
        echo $OUTPUT->confirm(
            get_string('github_delete_confirm', 'block_bdc'),
            new moodle_url($pageurl, ['action' => 'delete', 'confirm' => 1]),
            $pageurl
        );
        echo $OUTPUT->footer();
        exit;
    }
    require_sesskey();
    try {
        $client = new block_bdc_mapeo_client();
        $result = $client->delete_git_username($USER->id);
        unset_user_preference($pref);
        if (!empty($result['errors'])) {
            redirect($returnurl, get_string('github_partial', 'block_bdc', count($result['errors'])), null, \core\output\notification::NOTIFY_WARNING);
        }
        redirect($returnurl, get_string('github_deleted', 'block_bdc'), null, \core\output\notification::NOTIFY_SUCCESS);
    } catch (\moodle_exception $e) {
        \core\notification::error($e->getMessage());
        redirect($pageurl);
    }
}

// Guardar / editar.
$mform = new \block_bdc\form\github_username_form($pageurl);
$mform->set_data(['githubusername' => $current]);

if ($mform->is_cancelled()) {
    redirect($returnurl);
} else if ($data = $mform->get_data()) {
    $newuser = ltrim(trim($data->githubusername), '@');
    try {
        $client = new block_bdc_mapeo_client();
        if ($newuser === '') {
            // Campo vacío = eliminar.
            $result = $client->delete_git_username($USER->id);
            unset_user_preference($pref);
            $okmsg = get_string('github_deleted', 'block_bdc');
        } else {
            $result = $client->set_git_username($USER->id, $newuser);
            set_user_preference($pref, $newuser);
            $okmsg = get_string('github_saved', 'block_bdc');
        }
        if (!empty($result['errors'])) {
            redirect($returnurl, get_string('github_partial', 'block_bdc', count($result['errors'])), null, \core\output\notification::NOTIFY_WARNING);
        }
        redirect($returnurl, $okmsg, null, \core\output\notification::NOTIFY_SUCCESS);
    } catch (\moodle_exception $e) {
        // No se guarda nada en Moodle si la API ha rechazado el cambio.
        \core\notification::error($e->getMessage());
    }
}

echo $OUTPUT->header();
echo $OUTPUT->heading(get_string('github_title', 'block_bdc'));
echo html_writer::tag('p', get_string('github_intro', 'block_bdc'));
$mform->display();
if ($current !== '') {
    echo $OUTPUT->single_button(
        new moodle_url($pageurl, ['action' => 'delete']),
        get_string('github_delete', 'block_bdc'),
        'get'
    );
}
echo $OUTPUT->footer();
